// Widget tests for the chat screen's offline and limit-reached handling:
// attempting to send while offline surfaces the network-required message in a
// snack bar without ever calling the repository, and a limit-reached terminal
// event surfaces the clear usage-limit message. (Requirements 4.5, 4.6)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/network/connectivity.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/chat/application/chat_controller.dart';
import 'package:learnx/features/chat/data/chat_providers.dart';
import 'package:learnx/features/chat/data/chat_repository.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/chat/presentation/chat_screen.dart';

/// A fake [ChatRepository] whose [sendMessage] replays canned stream events and
/// records whether it was ever called, so the offline test can assert the
/// backend was never reached. (Mirrors the controller unit-test fake.)
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this.events);

  /// The events the next [sendMessage] stream yields, in order.
  final List<ChatStreamEvent> events;

  /// Whether [sendMessage] was ever invoked.
  bool wasCalled = false;
  String? lastText;

  @override
  Stream<ChatStreamEvent> sendMessage({
    required String sessionId,
    required String text,
  }) async* {
    wasCalled = true;
    lastText = text;
    for (final event in events) {
      // Yield across microtasks so streaming is observably incremental.
      await Future<void>.delayed(Duration.zero);
      yield event;
    }
  }

  @override
  Future<Result<Report>> fileReport({
    required String uid,
    required Report report,
  }) => throw UnimplementedError();

  @override
  Future<Result<ChatHistoryPage>> loadHistory({
    required String uid,
    required String sessionId,
    int pageSize = ChatRepository.defaultHistoryPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async => const Result.success(ChatHistoryPage.empty);
}

/// Watches [connectivityStatusProvider] so the overridden status stream is
/// subscribed and its first value lands before a send, letting the controller
/// observe a resolved online/offline status synchronously. The chat screen
/// itself does not watch connectivity, so this keeper stands in for a live
/// subscriber in the widget tree.
class _ConnectivityKeeper extends ConsumerWidget {
  const _ConnectivityKeeper({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(connectivityStatusProvider);
    return child;
  }
}

void main() {
  const uid = 'learner-1';

  Future<void> pumpScreen(
    WidgetTester tester, {
    required ChatRepository repository,
    ConnectivityStatus connectivity = ConnectivityStatus.online,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatRepositoryProvider.overrideWithValue(repository),
          authStateProvider.overrideWithValue(const AuthState(uid: uid)),
          connectivityStatusProvider.overrideWith(
            (ref) => Stream<ConnectivityStatus>.value(connectivity),
          ),
        ],
        child: const MaterialApp(
          home: _ConnectivityKeeper(child: ChatScreen()),
        ),
      ),
    );
    // Let the overridden connectivity stream deliver its first value so the
    // controller can read a resolved status when a send is attempted.
    await tester.pumpAndSettle();
  }

  /// Types [text] into the composer and taps the send control.
  Future<void> sendMessage(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'sending while offline shows the network-required message and never '
    'calls the repository (Req 4.5)',
    (tester) async {
      final repo = _FakeChatRepository(const []);
      await pumpScreen(
        tester,
        repository: repo,
        connectivity: ConnectivityStatus.offline,
      );

      await sendMessage(tester, 'hello');

      // The offline message is surfaced in a snack bar.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(ChatController.offlineMessage), findsOneWidget);
      // The repository was never reached and no bubbles were appended.
      expect(repo.wasCalled, isFalse);
      expect(find.byType(ChatBubble), findsNothing);
    },
  );

  testWidgets(
    'a limit-reached response shows the clear usage-limit message (Req 4.6)',
    (tester) async {
      // UsageLimitException's default message is the clear limit-reached text.
      final repo = _FakeChatRepository([
        const ChatLimitReached(UsageLimitException()),
      ]);
      await pumpScreen(
        tester,
        repository: repo,
        connectivity: ConnectivityStatus.online,
      );

      await sendMessage(tester, 'hi');

      expect(repo.wasCalled, isTrue);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(
        find.text(
          'You have reached your usage limit. Try again later or upgrade.',
        ),
        findsOneWidget,
      );
      // The pending assistant bubble was dropped; only the learner message
      // bubble remains in the transcript.
      expect(find.byType(ChatBubble), findsOneWidget);
    },
  );
}
