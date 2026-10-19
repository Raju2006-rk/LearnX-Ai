// Unit tests for ChatController: consuming the streamed reply from
// ChatRepository.sendMessage and rendering reply tokens into a growing
// assistant bubble, then finalizing on the terminal event.
// (Requirements 4.1, 4.4)

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

/// A fake [ChatRepository] whose [sendMessage] replays canned stream events,
/// recording the last call's arguments. [fileReport] is unused here.
class _FakeChatRepository implements ChatRepository {
  _FakeChatRepository(this.events);

  /// The events the next [sendMessage] stream yields, in order.
  List<ChatStreamEvent> events;

  String? lastSessionId;
  String? lastText;

  @override
  Stream<ChatStreamEvent> sendMessage({
    required String sessionId,
    required String text,
  }) async* {
    lastSessionId = sessionId;
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

  /// Pages the next [loadHistory] returns, consumed front-to-back so a test
  /// can drive successive load-more calls. Defaults to a single empty page.
  List<Result<ChatHistoryPage>> historyPages = <Result<ChatHistoryPage>>[];

  int loadHistoryCalls = 0;

  @override
  Future<Result<ChatHistoryPage>> loadHistory({
    required String uid,
    required String sessionId,
    int pageSize = ChatRepository.defaultHistoryPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    loadHistoryCalls++;
    if (historyPages.isEmpty) {
      return const Result.success(ChatHistoryPage.empty);
    }
    return historyPages.removeAt(0);
  }
}

/// A fake [ChatRepository] whose [sendMessage] returns a caller-supplied
/// stream, so a test can drive events manually and observe the in-flight
/// (pending-bubble) state before the terminal event.
class _ManualChatRepository implements ChatRepository {
  _ManualChatRepository(this._stream);

  final Stream<ChatStreamEvent> _stream;

  @override
  Stream<ChatStreamEvent> sendMessage({
    required String sessionId,
    required String text,
  }) => _stream;

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
  }) => throw UnimplementedError();
}

void main() {
  const uid = 'learner-1';

  ChatMessage assistant(String text) =>
      ChatMessage(id: 'm1', role: ChatRole.assistant, text: text);

  ProviderContainer makeContainer(
    ChatRepository repository, {
    String? signedInUid = uid,
    ConnectivityStatus connectivity = ConnectivityStatus.online,
  }) {
    final container = ProviderContainer(
      overrides: [
        chatRepositoryProvider.overrideWithValue(repository),
        authStateProvider.overrideWithValue(
          signedInUid == null
              ? const AuthState.signedOut()
              : AuthState(uid: signedInUid),
        ),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(connectivity),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Subscribes to [connectivityStatusProvider] and pumps until its first
  /// value lands, so the controller observes a resolved online/offline status
  /// synchronously on send (the overridden stream emits via a microtask).
  Future<void> settleConnectivity(ProviderContainer container) async {
    final sub = container.listen(connectivityStatusProvider, (_, _) {});
    addTearDown(sub.close);
    while (container.read(connectivityStatusProvider).asData == null) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('build starts with an empty transcript and nothing sending', () {
    final container = makeContainer(_FakeChatRepository(const []));
    final state = container.read(chatControllerProvider);
    expect(state.messages, isEmpty);
    expect(state.isSending, isFalse);
    expect(state.errorMessage, isNull);
  });

  test(
    'send appends the learner message and the completed reply (Req 4.1)',
    () async {
      final repo = _FakeChatRepository([
        const ChatToken('Hel'),
        const ChatToken('lo'),
        ChatReply(assistant('Hello there!')),
      ]);
      final container = makeContainer(repo);

      await container.read(chatControllerProvider.notifier).send('helo');

      final state = container.read(chatControllerProvider);
      expect(repo.lastText, 'helo');
      expect(state.isSending, isFalse);
      expect(state.messages.length, 2);
      expect(state.messages[0].role, ChatRole.user);
      expect(state.messages[0].text, 'helo');
      expect(state.messages[1].role, ChatRole.assistant);
      expect(state.messages[1].text, 'Hello there!');
    },
  );

  test(
    'reply bubble grows as tokens arrive before finalizing (Req 4.4)',
    () async {
      final repo = _FakeChatRepository([
        const ChatToken('Hel'),
        const ChatToken('lo'),
        ChatReply(assistant('Hello there!')),
      ]);
      final container = makeContainer(repo);

      final snapshots = <String>[];
      container.listen<ChatState>(chatControllerProvider, (previous, next) {
        if (next.messages.isNotEmpty &&
            next.messages.last.role == ChatRole.assistant) {
          snapshots.add(next.messages.last.text);
        }
      });

      await container.read(chatControllerProvider.notifier).send('helo');

      // The assistant bubble was present from empty and grew incrementally.
      expect(snapshots, containsAllInOrder(<String>['', 'Hel', 'Hello']));
      expect(
        container.read(chatControllerProvider).messages.last.text,
        'Hello there!',
      );
    },
  );

  test('a pending bubble exists while the reply is still streaming', () async {
    // A controllable stream that stays open after the first token so the
    // in-flight (pending-bubble) state can be observed before it resolves.
    final controllerStream = StreamController<ChatStreamEvent>();
    final repo = _ManualChatRepository(controllerStream.stream);
    final container = makeContainer(repo);

    // Kick off a send but do not await it to completion yet.
    final future = container.read(chatControllerProvider.notifier).send('hi');
    controllerStream.add(const ChatToken('Hi'));
    // Let the user message + first token land.
    await Future<void>.delayed(Duration.zero);

    final midState = container.read(chatControllerProvider);
    expect(midState.isSending, isTrue);
    expect(midState.messages.last.role, ChatRole.assistant);
    expect(midState.messages.last.text, 'Hi');

    // Resolve the stream with a terminal reply and let the send finish.
    controllerStream.add(ChatReply(assistant('Hi there!')));
    await controllerStream.close();
    await future;

    final done = container.read(chatControllerProvider);
    expect(done.isSending, isFalse);
    expect(done.messages.last.text, 'Hi there!');
  });

  test(
    'a limit-reached terminal event surfaces the error and drops the bubble',
    () async {
      final repo = _FakeChatRepository([
        const ChatLimitReached(UsageLimitException('Daily limit reached.')),
      ]);
      final container = makeContainer(repo);

      await container.read(chatControllerProvider.notifier).send('hi');

      final state = container.read(chatControllerProvider);
      expect(state.isSending, isFalse);
      expect(state.errorMessage, 'Daily limit reached.');
      // Only the learner message remains; the pending assistant bubble is gone.
      expect(state.messages.length, 1);
      expect(state.messages.single.role, ChatRole.user);
    },
  );

  test('a failed terminal event surfaces the error message', () async {
    final repo = _FakeChatRepository([
      const ChatFailed(NetworkException('No connection.')),
    ]);
    final container = makeContainer(repo);

    await container.read(chatControllerProvider.notifier).send('hi');

    final state = container.read(chatControllerProvider);
    expect(state.errorMessage, 'No connection.');
    expect(state.messages.length, 1);
  });

  test('blank input is ignored and the repository is not called', () async {
    final repo = _FakeChatRepository(const []);
    final container = makeContainer(repo);

    await container.read(chatControllerProvider.notifier).send('   ');

    expect(repo.lastText, isNull);
    expect(container.read(chatControllerProvider).messages, isEmpty);
  });

  test(
    'a signed-out send surfaces an auth error without calling the repo',
    () async {
      final repo = _FakeChatRepository(const []);
      final container = makeContainer(repo, signedInUid: null);

      await container.read(chatControllerProvider.notifier).send('hi');

      expect(repo.lastText, isNull);
      expect(
        container.read(chatControllerProvider).errorMessage,
        'You need to be signed in to chat.',
      );
    },
  );

  test(
    'an offline send surfaces a network-required message without calling the '
    'repository or queuing the message (Req 4.5, 8.4)',
    () async {
      final repo = _FakeChatRepository(const []);
      final container = makeContainer(
        repo,
        connectivity: ConnectivityStatus.offline,
      );

      // Let the overridden connectivity stream deliver its first value so the
      // controller can observe the offline status synchronously on send.
      await settleConnectivity(container);

      await container.read(chatControllerProvider.notifier).send('hi');

      final state = container.read(chatControllerProvider);
      // The repository was never called and nothing was queued: no bubbles.
      expect(repo.lastText, isNull);
      expect(state.messages, isEmpty);
      expect(state.isSending, isFalse);
      expect(state.errorMessage, ChatController.offlineMessage);
    },
  );

  test(
    'an online send reaches the repository as before (Req 4.5 happy path)',
    () async {
      final repo = _FakeChatRepository([ChatReply(assistant('ok'))]);
      final container = makeContainer(
        repo,
        connectivity: ConnectivityStatus.online,
      );
      await settleConnectivity(container);

      await container.read(chatControllerProvider.notifier).send('hi');

      expect(repo.lastText, 'hi');
      expect(container.read(chatControllerProvider).messages.last.text, 'ok');
    },
  );

  test(
    'the limit-reached message is clear and surfaced from the terminal event '
    '(Req 4.6)',
    () async {
      // The repository emits a UsageLimitException; its default message is the
      // clear free-tier limit-reached text the UI surfaces.
      final repo = _FakeChatRepository([
        const ChatLimitReached(UsageLimitException()),
      ]);
      final container = makeContainer(repo);

      await container.read(chatControllerProvider.notifier).send('hi');

      final state = container.read(chatControllerProvider);
      expect(state.isSending, isFalse);
      expect(
        state.errorMessage,
        'You have reached your usage limit. Try again later or upgrade.',
      );
      // Only the learner message remains; the pending bubble was dropped.
      expect(state.messages.length, 1);
      expect(state.messages.single.role, ChatRole.user);
    },
  );

  test('the forwarded session id matches the controller session', () async {
    final repo = _FakeChatRepository([ChatReply(assistant('ok'))]);
    final container = makeContainer(repo);

    final controller = container.read(chatControllerProvider.notifier);
    await controller.send('hi');

    expect(repo.lastSessionId, controller.sessionId);
  });

  ChatMessage historyMessage(String id, ChatRole role, String text) =>
      ChatMessage(id: id, role: role, text: text);

  test(
    'loadMoreHistory prepends an older page and tracks hasMore (Req 9.3)',
    () async {
      final repo = _FakeChatRepository(const [])
        ..historyPages = [
          Result.success(
            ChatHistoryPage(
              messages: [
                historyMessage('h1', ChatRole.user, 'old hello'),
                historyMessage('h2', ChatRole.assistant, 'old reply'),
              ],
              hasMore: true,
            ),
          ),
        ];
      final container = makeContainer(repo);

      await container.read(chatControllerProvider.notifier).loadMoreHistory();

      final state = container.read(chatControllerProvider);
      expect(repo.loadHistoryCalls, 1);
      expect(state.isLoadingHistory, isFalse);
      expect(state.hasMoreHistory, isTrue);
      expect(state.messages.map((m) => m.text), ['old hello', 'old reply']);
    },
  );

  test(
    'loadMoreHistory prepends older messages ahead of the live transcript',
    () async {
      final repo = _FakeChatRepository([ChatReply(assistant('live reply'))])
        ..historyPages = [
          Result.success(
            ChatHistoryPage(
              messages: [historyMessage('h1', ChatRole.user, 'older msg')],
              hasMore: false,
            ),
          ),
        ];
      final container = makeContainer(repo);
      final controller = container.read(chatControllerProvider.notifier);

      // A live send first, then load older history: the older page lands ahead.
      await controller.send('hi');
      await controller.loadMoreHistory();

      final texts = container
          .read(chatControllerProvider)
          .messages
          .map((m) => m.text)
          .toList();
      expect(texts.first, 'older msg');
      expect(texts, containsAll(['hi', 'live reply']));
      expect(container.read(chatControllerProvider).hasMoreHistory, isFalse);
    },
  );

  test('a signed-out loadMoreHistory is a no-op', () async {
    final repo = _FakeChatRepository(const []);
    final container = makeContainer(repo, signedInUid: null);

    await container.read(chatControllerProvider.notifier).loadMoreHistory();

    expect(repo.loadHistoryCalls, 0);
    expect(container.read(chatControllerProvider).messages, isEmpty);
  });

  test(
    'a failed history load surfaces the error without dropping messages',
    () async {
      final repo = _FakeChatRepository([ChatReply(assistant('live'))])
        ..historyPages = [
          const Result.failure(NetworkException('No connection.')),
        ];
      final container = makeContainer(repo);
      final controller = container.read(chatControllerProvider.notifier);

      await controller.send('hi');
      await controller.loadMoreHistory();

      final state = container.read(chatControllerProvider);
      expect(state.errorMessage, 'No connection.');
      expect(state.isLoadingHistory, isFalse);
      // The live transcript is preserved.
      expect(state.messages.map((m) => m.text), containsAll(['hi', 'live']));
    },
  );
}
