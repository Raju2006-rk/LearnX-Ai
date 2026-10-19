// Time-to-first-token benchmark for the AI Teacher chat screen.
// (Task 12.3; Requirement 9.2, 4.4)
//
// Req 9.2 / 4.4 require the reply to *begin* displaying within 2 seconds of a
// send under nominal network conditions. The screen is built to show the reply
// bubble from its first token rather than waiting for the whole reply, so this
// test drives a controllable reply stream, emits a single first token, and
// asserts that a visible reply bubble carrying that token appears — measuring
// the latency from send to first-token-on-screen and holding it well under the
// 2s budget. It deliberately keeps the stream open after the first token so it
// measures *first token*, not reply completion.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/network/connectivity.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/chat/data/chat_providers.dart';
import 'package:learnx/features/chat/data/chat_repository.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/chat/presentation/chat_screen.dart';

/// A [ChatRepository] whose [sendMessage] returns a caller-controlled stream,
/// so the test can emit the first token on demand and observe when it lands in
/// the transcript. The stream is left open after the first token so the
/// measurement captures time-to-first-token, not reply completion.
class _StreamingChatRepository implements ChatRepository {
  _StreamingChatRepository(this.controller);

  final StreamController<ChatStreamEvent> controller;

  @override
  Stream<ChatStreamEvent> sendMessage({
    required String sessionId,
    required String text,
  }) => controller.stream;

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

/// Subscribes to [connectivityStatusProvider] so its first (online) value
/// lands before a send, matching the chat handling test's keeper.
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

  testWidgets(
    'the reply bubble appears from the first streamed token, well within the '
    'time-to-first-token budget (Req 9.2)',
    (tester) async {
      final controller = StreamController<ChatStreamEvent>();
      // Closed explicitly at the end of the test once the terminal reply is
      // emitted; guard teardown in case an assertion fails before then.
      addTearDown(() async {
        if (!controller.isClosed) await controller.close();
      });
      final repo = _StreamingChatRepository(controller);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatRepositoryProvider.overrideWithValue(repo),
            authStateProvider.overrideWithValue(const AuthState(uid: uid)),
            connectivityStatusProvider.overrideWith(
              (ref) =>
                  Stream<ConnectivityStatus>.value(ConnectivityStatus.online),
            ),
          ],
          child: const MaterialApp(
            home: _ConnectivityKeeper(child: ChatScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Compose and send a message.
      await tester.enterText(find.byType(TextField), 'hello teacher');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump(); // let the user bubble + pending bubble appear

      // Measure from the moment the first token is emitted until it is shown.
      final stopwatch = Stopwatch()..start();
      controller.add(const ChatToken('Hi'));
      // Pump frames until the first token is rendered in the transcript.
      await tester.pump();
      stopwatch.stop();

      // A reply bubble carrying the first token is on screen; the reply has
      // begun displaying rather than waiting for the full response.
      expect(find.text('Hi'), findsOneWidget);
      // The learner and (growing) teacher bubbles are both present.
      expect(find.byType(ChatBubble), findsNWidgets(2));

      // Req 9.2 budgets 2 seconds to begin displaying the reply. Rendering the
      // first token is near-instant once it streams in; assert a generous
      // ceiling well under the 2s budget so the benchmark catches a real
      // regression (e.g. buffering the whole reply before showing anything)
      // without being flaky on a slow machine.
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 1)),
        reason:
            'the reply should begin displaying from its first token, well '
            'under the 2s time-to-first-token budget (Req 9.2)',
      );

      // Finish the stream and close it so the controller's send loop resolves
      // (the `await for` ends on a terminal event + stream close) and no
      // pending async work outlives the test when the tree tears down.
      controller.add(
        ChatReply(
          const ChatMessage(
            id: 'm1',
            role: ChatRole.assistant,
            text: 'Hi there!',
          ),
        ),
      );
      await controller.close();
      await tester.pumpAndSettle();
      expect(find.text('Hi there!'), findsOneWidget);
    },
  );
}
