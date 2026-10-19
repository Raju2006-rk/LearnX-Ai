import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/network/connectivity.dart';
import '../data/chat_providers.dart';
import '../data/chat_repository.dart';
import '../domain/chat.dart';

/// The live state of the AI Teacher chat the UI renders. (Requirements 4.1, 4.4)
///
/// [messages] is the ordered transcript: learner messages and teacher replies,
/// oldest first. While a reply is streaming the last entry is a placeholder
/// assistant [ChatMessage] whose [ChatMessage.text] grows token by token, so a
/// bubble appears and fills in as tokens arrive (backing the time-to-first-
/// token target). [isSending] is true from the moment the learner submits
/// until the terminal event resolves, so the composer can disable the send
/// control and avoid overlapping requests. [errorMessage], when set, carries a
/// user-facing explanation of a failed send for the UI to surface. It carries
/// an `error` status or a thrown SDK error, the free-tier limit-reached
/// message (Requirement 4.6), a moderation refusal, and the network-required
/// message shown when a send is attempted while offline (Requirements 4.5,
/// 8.4). Grammar-feedback presentation is refined into dedicated UI by task
/// 7.3.
@immutable
class ChatState {
  const ChatState({
    this.messages = const [],
    this.isSending = false,
    this.errorMessage,
    this.isLoadingHistory = false,
    this.hasMoreHistory = false,
  });

  /// The ordered chat transcript, oldest first.
  final List<ChatMessage> messages;

  /// Whether a send is in flight (from submit until the terminal event).
  final bool isSending;

  /// A user-facing error for the most recent failed send, or `null`.
  final String? errorMessage;

  /// Whether a history page is currently being fetched, so the UI can show a
  /// load-more spinner and avoid issuing overlapping history reads.
  /// (Requirement 9.3)
  final bool isLoadingHistory;

  /// Whether at least one older message exists beyond what is loaded, so the
  /// UI can offer a load-more affordance. (Requirement 9.3)
  final bool hasMoreHistory;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isSending,
    String? errorMessage,
    bool? isLoadingHistory,
    bool? hasMoreHistory,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isSending: isSending ?? this.isSending,
      // errorMessage is intentionally cleared unless explicitly provided, so a
      // new send starts from a clean slate.
      errorMessage: errorMessage,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      hasMoreHistory: hasMoreHistory ?? this.hasMoreHistory,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatState &&
      listEquals(other.messages, messages) &&
      other.isSending == isSending &&
      other.errorMessage == errorMessage &&
      other.isLoadingHistory == isLoadingHistory &&
      other.hasMoreHistory == hasMoreHistory;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(messages),
    isSending,
    errorMessage,
    isLoadingHistory,
    hasMoreHistory,
  );
}

/// Drives the AI Teacher chat: sends the learner's message and consumes the
/// streamed reply from [ChatRepository.sendMessage], rendering reply tokens
/// into a growing assistant bubble as they arrive. (Requirements 4.1, 4.4)
///
/// This controller is the orchestration seam between the chat screen and the
/// repository. The repository branches on the function's explicit `status`
/// and never throws, surfacing a terminal [ChatStreamEvent]; this controller
/// mirrors those events into [ChatState]:
///
/// - [ChatToken] — append the chunk to the pending assistant bubble so the
///   reply fills in incrementally.
/// - [ChatReply] — replace the pending bubble with the completed assistant
///   message (full text plus any [GrammarFeedback]).
/// - [ChatLimitReached] / [ChatRefused] / [ChatFailed] — drop the pending
///   bubble and surface the typed message as [ChatState.errorMessage].
///
/// Chat requires an active network connection: before a send reaches the
/// repository this controller checks connectivity and, when offline, fails
/// fast with a clear message rather than calling the backend or queuing the
/// message. (Requirements 4.5, 8.4)
///
/// A chat session id is minted once per controller lifecycle; the server owns
/// persisting messages under `chatSessions/{sessionId}/messages`, so this
/// controller holds only the in-memory transcript for the live session.
///
/// Persisted history is paginated via [loadMoreHistory], which fetches a
/// bounded page of older messages at a time and prepends them to the
/// transcript. Paging keeps the initial read and scroll-back work small so a
/// long conversation never forces one large read on a low-end device or slow
/// network. (Requirement 9.3)
class ChatController extends Notifier<ChatState> {
  /// The id the pending assistant bubble is tracked by while streaming. It is
  /// not a persisted document id — the server assigns that on [ChatReply].
  static const String _pendingId = '__pending__';

  /// Surfaced when a send is attempted while the device is offline. Chat is
  /// network-required, so the learner is told plainly and the message is not
  /// queued for later. (Requirements 4.5, 8.4)
  @visibleForTesting
  static const String offlineMessage =
      'Chat requires a network connection. Reconnect and try again.';

  late final String _sessionId;

  /// The cursor for the next (older) history page, or `null` before the first
  /// page is fetched or once the oldest message has been loaded.
  DocumentSnapshot<Map<String, dynamic>>? _historyCursor;

  ChatRepository get _repository => ref.read(chatRepositoryProvider);

  /// The signed-in learner's uid, or `null` when signed out.
  String? get _uid => ref.read(authStateProvider).uid;

  /// Whether the device is currently known to be offline.
  ///
  /// Reads the latest [connectivityStatusProvider] value. The status stream
  /// emits the current connectivity immediately on subscription, so by the
  /// time the learner can send a message a value is normally present; while
  /// the first reading is still pending (or errored) the send is allowed to
  /// proceed so a transient unknown state never blocks a legitimate message —
  /// the repository still surfaces a network failure if the call cannot reach
  /// the backend. (Requirements 4.5, 8.4)
  bool get _isOffline =>
      ref.read(connectivityStatusProvider).asData?.value.isOffline ?? false;

  @override
  ChatState build() {
    _sessionId = _newSessionId();
    return const ChatState();
  }

  /// The chat session id for the live conversation. Forwarded by the chat UI
  /// to the Grammar_Feedback card so a reported item captures its session.
  String get sessionId => _sessionId;

  /// Sends [text] to the AI teacher and streams the reply into the transcript.
  ///
  /// Appends the learner's message and a pending assistant bubble immediately,
  /// then grows that bubble as tokens arrive and finalizes it on the terminal
  /// event. Blank input and overlapping sends (while [ChatState.isSending] is
  /// true) are ignored. Requires a signed-in learner; a signed-out send
  /// surfaces an auth error without calling the repository. Chat is
  /// network-required: a send attempted while offline surfaces
  /// [offlineMessage] without calling the repository or queuing the message.
  Future<void> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isSending) return;

    if (_uid == null) {
      state = state.copyWith(errorMessage: 'You need to be signed in to chat.');
      return;
    }

    // Chat is network-required. Fail fast when offline so the learner gets a
    // clear message instead of a hanging request, and do not queue the
    // message or append a bubble. (Requirements 4.5, 8.4)
    if (_isOffline) {
      state = state.copyWith(errorMessage: offlineMessage);
      return;
    }

    // Show the learner's message and an empty assistant bubble right away so
    // the UI reflects the send before the first token arrives.
    final userMessage = ChatMessage.user(trimmed);
    const pendingReply = ChatMessage(
      id: _pendingId,
      role: ChatRole.assistant,
      text: '',
    );
    state = state.copyWith(
      messages: [...state.messages, userMessage, pendingReply],
      isSending: true,
    );

    final stream = _repository.sendMessage(
      sessionId: _sessionId,
      text: trimmed,
    );

    await for (final event in stream) {
      switch (event) {
        case ChatToken(:final text):
          _appendToken(text);
        case ChatReply(:final message):
          _resolveReply(message);
        case ChatLimitReached(:final exception):
          _resolveFailure(exception);
        case ChatRefused(:final exception):
          _resolveFailure(exception);
        case ChatFailed(:final exception):
          _resolveFailure(exception);
      }
    }

    // The stream always ends with a terminal event that clears `isSending`;
    // guard against a stream that closes without one so the composer re-enables.
    if (state.isSending) {
      state = state.copyWith(messages: _withoutPending(state.messages));
    }
  }

  /// Loads one older page of persisted history and prepends it to the
  /// transcript, paginating from the last fetched cursor. (Requirement 9.3)
  ///
  /// The first call fetches the newest page; subsequent calls page backwards
  /// through older messages. Overlapping calls (while
  /// [ChatState.isLoadingHistory] is true) are ignored, and a signed-out
  /// learner is a no-op. Loading a bounded page at a time keeps main-thread
  /// work small on low-end devices instead of reading the whole conversation.
  /// Older messages are prepended ahead of the in-memory live transcript so
  /// their chronological order is preserved; a read failure surfaces as
  /// [ChatState.errorMessage] without dropping what is already shown.
  Future<void> loadMoreHistory() async {
    if (state.isLoadingHistory) return;
    final uid = _uid;
    if (uid == null) return;

    state = state.copyWith(isLoadingHistory: true);

    final result = await _repository.loadHistory(
      uid: uid,
      sessionId: _sessionId,
      startAfter: _historyCursor,
    );

    result.fold(
      (page) {
        _historyCursor = page.nextCursor ?? _historyCursor;
        state = state.copyWith(
          messages: [...page.messages, ...state.messages],
          isLoadingHistory: false,
          hasMoreHistory: page.hasMore,
        );
      },
      (exception) {
        state = state.copyWith(
          isLoadingHistory: false,
          errorMessage: exception.message,
        );
      },
    );
  }

  /// Appends [token] to the pending assistant bubble, growing the reply.
  void _appendToken(String token) {
    final messages = [...state.messages];
    final index = _pendingIndex(messages);
    if (index == -1) return;
    messages[index] = messages[index].copyWith(
      text: messages[index].text + token,
    );
    state = state.copyWith(messages: messages, isSending: true);
  }

  /// Replaces the pending bubble with the completed assistant [message].
  void _resolveReply(ChatMessage message) {
    final messages = [...state.messages];
    final index = _pendingIndex(messages);
    if (index == -1) {
      messages.add(message);
    } else {
      messages[index] = message;
    }
    state = state.copyWith(messages: messages, isSending: false);
  }

  /// Drops the pending bubble and surfaces [exception]'s message as the error.
  void _resolveFailure(AppException exception) {
    state = state.copyWith(
      messages: _withoutPending(state.messages),
      isSending: false,
      errorMessage: exception.message,
    );
  }

  /// The index of the pending assistant bubble, or -1 when none is present.
  int _pendingIndex(List<ChatMessage> messages) =>
      messages.indexWhere((m) => m.id == _pendingId);

  /// A copy of [messages] with the pending assistant bubble removed.
  List<ChatMessage> _withoutPending(List<ChatMessage> messages) =>
      messages.where((m) => m.id != _pendingId).toList();

  /// Mints a session id for the live conversation, unique per controller
  /// lifecycle so a fresh chat does not collide with a prior session.
  String _newSessionId() => 'session-${DateTime.now().microsecondsSinceEpoch}';
}

/// Exposes the [ChatController] and its [ChatState] to the chat UI.
final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
  name: 'chatControllerProvider',
);
