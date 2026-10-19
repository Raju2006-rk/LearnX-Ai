// Navigation widget/property tests for the bottom-navigation shell (task 6.2).
//
// Property 24: Navigation maps destinations to screens — for any selected
// bottom-navigation destination, the displayed screen equals the screen mapped
// to that destination. The destination space is the finite set of bottom-nav
// tabs (Home, AI, Account), so the property is checked exhaustively across
// every destination rather than with random sampling. (Requirement 12.2)
//
// Also covers the Premium placeholder: the Premium destination renders the
// placeholder screen in the MVP. (Requirement 12.3)

import 'package:cloud_firestore/cloud_firestore.dart' hide Type;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:learnx/app/app.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/chat/data/chat_providers.dart';
import 'package:learnx/features/chat/data/chat_repository.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/chat/presentation/chat_screen.dart';
import 'package:learnx/features/shell/presentation/account_screen.dart';
import 'package:learnx/features/shell/presentation/home_screen.dart';
import 'package:learnx/features/shell/presentation/premium_screen.dart';

/// A no-op [ChatRepository] so mounting [ChatScreen] in the navigation tests
/// does not reach the real Firebase Functions / Firestore backend.
///
/// [ChatScreen.initState] eagerly loads the first history page on mount; this
/// fake returns an empty page and never touches the network, so navigating to
/// the AI tab is safe in a widget test without Firebase initialized.
class _FakeChatRepository implements ChatRepository {
  @override
  Stream<ChatStreamEvent> sendMessage({
    required String sessionId,
    required String text,
  }) => const Stream<ChatStreamEvent>.empty();

  @override
  Future<Result<Report>> fileReport({
    required String uid,
    required Report report,
  }) async => const Result.success(
    Report(
      sessionId: '',
      messageId: '',
      originalText: '',
      grammarFeedback: null,
      reason: '',
    ),
  );

  @override
  Future<Result<ChatHistoryPage>> loadHistory({
    required String uid,
    required String sessionId,
    int pageSize = ChatRepository.defaultHistoryPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async => const Result.success(ChatHistoryPage.empty);
}

void main() {
  const uid = 'user-123';

  /// A bottom-navigation destination paired with the screen it must display.
  ///
  /// This is the mapping Property 24 ranges over: selecting [label] must bring
  /// the screen type [screen] to the foreground.
  final destinations = <({String label, Type screen})>[
    (label: 'Home', screen: HomeScreen),
    (label: 'AI', screen: ChatScreen),
    (label: 'Account', screen: AccountScreen),
  ];

  /// Pumps the full app routed straight to the home shell by satisfying every
  /// redirect gate (signed in, consented, onboarded), mirroring the setup used
  /// by the consent routing tests.
  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWithValue(const AuthState(uid: uid)),
          firebaseFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          // ChatScreen loads history on mount; override its repository with a
          // no-op fake so navigating to the AI tab never touches Firebase.
          chatRepositoryProvider.overrideWithValue(_FakeChatRepository()),
          consentProvider.overrideWithValue(true),
          onboardedProvider.overrideWithValue(true),
        ],
        child: const LearnXApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Property 24: selecting any bottom-navigation destination displays its '
    'mapped screen',
    (tester) async {
      await pumpShell(tester);

      // Start on the home shell with the navigation bar present.
      expect(find.byType(NavigationBar), findsOneWidget);

      // For every destination in the mapping, select it and assert the mapped
      // screen is the one displayed while the others are not.
      for (final destination in destinations) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(destination.label),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(destination.screen),
          findsOneWidget,
          reason:
              'Selecting "${destination.label}" should display '
              '${destination.screen}.',
        );

        // No other destination's screen is displayed at the same time.
        for (final other in destinations) {
          if (other.screen == destination.screen) continue;
          expect(
            find.byType(other.screen),
            findsNothing,
            reason:
                'Selecting "${destination.label}" should not display '
                '${other.screen}.',
          );
        }
      }
    },
  );

  testWidgets(
    'the Premium destination renders the placeholder screen (Requirement 12.3)',
    (tester) async {
      await pumpShell(tester);

      // Navigate to the Premium placeholder route (nested under Home).
      final context = tester.element(find.byType(NavigationBar));
      GoRouter.of(context).goNamed('premium');
      await tester.pumpAndSettle();

      expect(find.byType(PremiumScreen), findsOneWidget);
      expect(find.text('Premium coming soon'), findsOneWidget);
    },
  );
}

