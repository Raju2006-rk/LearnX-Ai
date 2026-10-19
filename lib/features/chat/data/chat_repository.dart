import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter/foundation.dart';

import '../../../core/ai/ai_function_client.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/chat.dart';

/// An event emitted while streaming a reply from `chatWithTeacher`.
///
/// A successful stream yields zero or more [ChatToken]s (incremental reply
/// text, backing the time-to-first-token target) followed by exactly one
/// terminal event: a [ChatReply] on success, or one of the failure events
/// ([ChatLimitReached], [ChatRefused], [ChatFailed]) when the function
/// reports a non-`ok` status or the call throws. Branching is on the explicit
/// event type, never on inspecting free-form reply text. (Requirement 4.6)
sealed class ChatStreamEvent {
  const ChatStreamEvent();
}

/// An incremental chunk of streamed reply text.
final class ChatToken extends ChatStreamEvent {
  const ChatToken(this.text);

  /// The partial reply text received in this chunk.
  final String text;

  @override
  bool operator ==(Object other) => other is ChatToken && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'ChatToken("$text")';
}

/// The terminal success event: the assistant [message] (full reply text plus
/// any [GrammarFeedback]) that the function returned and persisted.
final class ChatReply extends ChatStreamEvent {
  const ChatReply(this.message);

  /// The completed assistant message.
  final ChatMessage message;

  @override
  bool operator ==(Object other) =>
      other is ChatReply && other.message == message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ChatReply($message)';
}

/// Terminal failure event for a `limit_reached` status: the learner's daily
/// AI usage limit was reached and the provider was not invoked.
/// (Requirement 4.6)
final class ChatLimitReached extends ChatStreamEvent {
  const ChatLimitReached(this.exception);

  /// The typed failure carrying a user-facing message.
  final UsageLimitException exception;

  @override
  bool operator ==(Object other) =>
      other is ChatLimitReached && other.exception == exception;

  @override
  int get hashCode => exception.hashCode;

  @override
  String toString() => 'ChatLimitReached($exception)';
}

/// Terminal failure event for a `refusal` status: moderation withheld the
/// content and the server returned a safe substitute/refusal.
final class ChatRefused extends ChatStreamEvent {
  const ChatRefused(this.exception);

  /// The typed failure carrying the safe refusal message.
  final ModerationRefusalException exception;

  @override
  bool operator ==(Object other) =>
      other is ChatRefused && other.exception == exception;

  @override
  int get hashCode => exception.hashCode;

  @override
  String toString() => 'ChatRefused($exception)';
}

/// Terminal failure event for an `error` status or a thrown error (network,
/// auth, malformed payload).
final class ChatFailed extends ChatStreamEvent {
  const ChatFailed(this.exception);

  /// The mapped typed failure.
  final AppException exception;

  @override
  bool operator ==(Object other) =>
      other is ChatFailed && other.exception == exception;

  @override
  int get hashCode => exception.hashCode;

  @override
  String toString() => 'ChatFailed($exception)';
}

/// One page of persisted chat history, newest-first within the page, plus the
/// cursor needed to fetch the next (older) page. (Requirement 9.3)
///
/// Chat history is paginated so a long-running conversation never forces a
/// single large read of the whole `messages` subcollection on a low-end device
/// or slow network; the UI loads a bounded page and fetches older messages on
/// demand. [messages] holds the page ordered oldest-first (so it can be
/// prepended directly to the in-memory transcript); [hasMore] is true when at
/// least one older message remains beyond this page; [nextCursor] is the
/// document to start after on the next call, or `null` when [hasMore] is false.
@immutable
class ChatHistoryPage {
  const ChatHistoryPage({
    required this.messages,
    required this.hasMore,
    this.nextCursor,
  });

  /// An empty page with no more history to load.
  static const ChatHistoryPage empty = ChatHistoryPage(
    messages: <ChatMessage>[],
    hasMore: false,
  );

  /// The page of messages, ordered oldest-first for easy prepending.
  final List<ChatMessage> messages;

  /// Whether at least one older message exists beyond this page.
  final bool hasMore;

  /// The cursor (last document read, newest-first) to page from next, or
  /// `null` when there is nothing older to fetch.
  final DocumentSnapshot<Map<String, dynamic>>? nextCursor;

  @override
  bool operator ==(Object other) =>
      other is ChatHistoryPage &&
      listEquals(other.messages, messages) &&
      other.hasMore == hasMore &&
      other.nextCursor == nextCursor;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(messages), hasMore, nextCursor);
}

/// Mediates the AI Teacher chat between the UI and the server-side
/// `chatWithTeacher` streaming callable, and files wrong-correction reports.
/// (Requirements 4.1, 4.6)
///
/// [sendMessage] streams reply tokens as they arrive and resolves the terminal
/// event by branching on the function's explicit `status`
/// (`ok | limit_reached | refusal | error`) — never by inspecting free-form
/// reply text, matching the design's error-handling contract. The function
/// itself persists the message and feedback to
/// `chatSessions/{sessionId}/messages`, so this repository does not write chat
/// documents; it only maps the streamed payload into domain events. Filing a
/// report (task 7.5) is a client-side write under the learner's own
/// `reports/{reportId}`.
class ChatRepository {
  ChatRepository({
    required AiFunctionClient aiClient,
    required FirebaseFirestore firestore,
  }) : _aiClient = aiClient,
       _firestore = firestore;

  /// The callable name of the server-side streaming chat function.
  static const String callableName = 'chatWithTeacher';

  final AiFunctionClient _aiClient;
  final FirebaseFirestore _firestore;

  /// Sends [text] to the teacher in session [sessionId] and streams the reply.
  ///
  /// Yields a [ChatToken] for each streamed chunk, then exactly one terminal
  /// event: [ChatReply] on `ok`, [ChatLimitReached] on `limit_reached`,
  /// [ChatRefused] on `refusal`, or [ChatFailed] on `error`, a malformed
  /// payload, or a thrown SDK error. The stream never throws — failures are
  /// surfaced as a terminal [ChatFailed]/typed event so the controller can
  /// render a consistent state.
  Stream<ChatStreamEvent> sendMessage({
    required String sessionId,
    required String text,
  }) async* {
    try {
      final events = _aiClient.stream(callableName, <String, dynamic>{
        'sessionId': sessionId,
        'text': text,
      });

      await for (final event in events) {
        switch (event) {
          case AiChunk(:final text):
            if (text.isNotEmpty) yield ChatToken(text);
          case AiStreamResult(:final data):
            yield _terminalFromResult(data);
        }
      }
    } catch (error) {
      yield ChatFailed(_mapError(error));
    }
  }

  /// Files a wrong-correction report for [report] under the learner [uid]'s
  /// own `reports` collection, returning the stored [Report] (with its
  /// generated id) so the UI can confirm receipt. (Requirements 5.3, 5.4)
  ///
  /// Reports are written with the full context snapshot the learner was
  /// shown. The server owns advancing `status` to reviewed; the client always
  /// writes an `open` report with a server timestamp.
  Future<Result<Report>> fileReport({
    required String uid,
    required Report report,
  }) async {
    try {
      final docRef = _firestore
          .collection(FirestorePaths.reportsCollection(uid))
          .doc();
      final dto = _toReportDto(report);
      final map = dto.toMap()
        // Let Firestore stamp the creation time server-side.
        ..['createdAt'] = FieldValue.serverTimestamp();
      await docRef.set(map);
      return Result.success(
        Report(
          id: docRef.id,
          sessionId: report.sessionId,
          messageId: report.messageId,
          originalText: report.originalText,
          grammarFeedback: report.grammarFeedback,
          reason: report.reason,
          status: ReportStatus.open,
        ),
      );
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// The default number of messages fetched per history page. Kept small so a
  /// single read stays cheap on low-end devices and slow networks.
  /// (Requirement 9.3)
  static const int defaultHistoryPageSize = 20;

  /// Loads one page of persisted chat history for session [sessionId] under
  /// learner [uid], newest messages first on the wire but returned
  /// oldest-first, paginating from [startAfter] when fetching older pages.
  /// (Requirement 9.3)
  ///
  /// Reads `users/{uid}/chatSessions/{sessionId}/messages` ordered by
  /// `createdAt` descending and limited to [pageSize] + 1: the extra document
  /// is a look-ahead that tells us whether an older page exists without a
  /// second query. The returned [ChatHistoryPage.messages] are reversed to
  /// oldest-first so the controller can prepend them to the live transcript,
  /// and [ChatHistoryPage.nextCursor] carries the last in-page document to
  /// page from next. A paginated read keeps startup and scroll-up work bounded
  /// instead of loading an entire conversation at once. Connectivity failures
  /// map to [NetworkException]; other read failures map to [AuthException].
  Future<Result<ChatHistoryPage>> loadHistory({
    required String uid,
    required String sessionId,
    int pageSize = defaultHistoryPageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection(FirestorePaths.messagesCollection(uid, sessionId))
          .orderBy('createdAt', descending: true)
          // Fetch one extra to detect whether an older page remains.
          .limit(pageSize + 1);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snap = await query.get();
      final docs = snap.docs;
      final hasMore = docs.length > pageSize;
      // Drop the look-ahead document from the page we actually return.
      final pageDocs = hasMore ? docs.sublist(0, pageSize) : docs;

      // Reverse to oldest-first so the page can be prepended to the transcript.
      final messages = <ChatMessage>[
        for (final doc in pageDocs.reversed)
          ChatMessage.fromDto(ChatMessageDto.fromMap(doc.data()), id: doc.id),
      ];

      return Result.success(
        ChatHistoryPage(
          messages: messages,
          hasMore: hasMore,
          nextCursor: pageDocs.isEmpty ? null : pageDocs.last,
        ),
      );
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Maps the terminal `chatWithTeacher` payload into a domain stream event by
  /// branching on the explicit `status`.
  ChatStreamEvent _terminalFromResult(Map<String, dynamic> data) {
    final status = data['status'];
    switch (status) {
      case 'limit_reached':
        return const ChatLimitReached(UsageLimitException());
      case 'refusal':
        final message = data['safeMessage'];
        return ChatRefused(
          ModerationRefusalException(
            message is String && message.isNotEmpty
                ? message
                : 'This request was blocked by content moderation.',
          ),
        );
      case 'error':
        final message = data['message'];
        return ChatFailed(
          NetworkException(
            message is String && message.isNotEmpty
                ? message
                : 'Something went wrong. Please try again.',
          ),
        );
      case 'ok':
        return _replyFromResult(data);
      default:
        return const ChatFailed(
          NetworkException('Something went wrong. Please try again.'),
        );
    }
  }

  /// Builds the terminal [ChatReply] from an `ok` payload, mapping the reply
  /// text and optional `grammarFeedback` into a domain [ChatMessage]. A
  /// missing/unusable result maps to a [ChatFailed] so the UI never renders a
  /// broken reply.
  ChatStreamEvent _replyFromResult(Map<String, dynamic> data) {
    final result = _asStringMap(data['result']) ?? data;
    final replyText = result['reply'] ?? result['text'];
    if (replyText is! String) {
      return const ChatFailed(
        NetworkException('Could not load the reply. Please try again.'),
      );
    }

    final feedbackMap = _asStringMap(result['grammarFeedback']);
    final feedback = feedbackMap == null
        ? null
        : GrammarFeedback.fromDto(GrammarFeedbackDto.fromMap(feedbackMap));

    final messageId = result['messageId'];
    return ChatReply(
      ChatMessage(
        id: messageId is String ? messageId : null,
        role: ChatRole.assistant,
        text: replyText,
        grammarFeedback: feedback,
      ),
    );
  }

  ReportDto _toReportDto(Report report) {
    final feedback = report.grammarFeedback;
    return ReportDto(
      sessionId: report.sessionId,
      messageId: report.messageId,
      originalText: report.originalText,
      grammarFeedback: feedback == null ? null : _toFeedbackDto(feedback),
      reason: report.reason,
      status: report.status.wireValue,
    );
  }

  GrammarFeedbackDto _toFeedbackDto(GrammarFeedback feedback) {
    final span = feedback.mistakeSpan;
    return GrammarFeedbackDto(
      hasMistake: feedback.hasMistake,
      mistakeSpan: span == null
          ? null
          : MistakeSpanDto(start: span.start, end: span.end, text: span.text),
      correctedSentence: feedback.correctedSentence,
      tip: feedback.tip,
      translation: TranslationDto(
        language: feedback.translation.language.wireValue,
        text: feedback.translation.text,
      ),
    );
  }

  static Map<String, dynamic>? _asStringMap(dynamic value) {
    if (value is Map) {
      return value.map((key, v) => MapEntry(key.toString(), v));
    }
    return null;
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy, mirroring
  /// the other AI repositories: `unauthenticated` → [AuthException],
  /// connectivity codes → [NetworkException], resource-exhausted →
  /// [UsageLimitException], everything else → [NetworkException] for the
  /// callable path and [AuthException] for the Firestore write path.
  AppException _mapError(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return AuthException(
            error.message ?? 'Please sign in and try again.',
            error,
          );
        case 'resource-exhausted':
          return UsageLimitException(
            error.message ??
                'You have reached your usage limit. Try again later or upgrade.',
            error,
          );
        case 'permission-denied':
          return AuthException(
            error.message ?? 'This request was blocked by content moderation.',
            error,
          );
      }
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return NetworkException(
        error.message ?? 'Something went wrong. Please try again.',
        error,
      );
    }
    if (error is FirebaseException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return AuthException(
        error.message ?? 'Could not save your report.',
        error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return const NetworkException();
    }
    return const NetworkException('Something went wrong. Please try again.');
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
