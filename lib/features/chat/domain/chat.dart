import 'package:flutter/foundation.dart';

import '../../../shared/models/dtos/dtos.dart';
import '../../onboarding/domain/onboarding_selections.dart';

/// Who authored a [ChatMessage] in the AI Teacher chat.
///
/// The [wireValue] matches the `role` string stored on a message document
/// (`"user" | "assistant"`), so the feature never hand-writes these literals.
enum ChatRole {
  /// A message the learner sent.
  user('user'),

  /// A reply from the AI teacher.
  assistant('assistant');

  const ChatRole(this.wireValue);

  /// The Firestore/wire representation of this role.
  final String wireValue;

  /// Parses a stored [value] into a [ChatRole], defaulting to [assistant]
  /// when the value is missing or unrecognized (replies are the common case
  /// carrying structured feedback, and an unknown role should never be shown
  /// as a learner's own message).
  static ChatRole fromWire(String? value) {
    for (final role in ChatRole.values) {
      if (role.wireValue == value) return role;
    }
    return ChatRole.assistant;
  }
}

/// The span of a learner's message the AI flagged as a mistake.
///
/// Present only when the feedback [GrammarFeedback.hasMistake] is true. The
/// [start]/[end] indices are offsets into the learner's original message and
/// [text] is the flagged substring the UI renders in red. Mirrors the
/// design's `Grammar_Feedback.mistakeSpan`.
@immutable
class MistakeSpan {
  const MistakeSpan({
    required this.start,
    required this.end,
    required this.text,
  });

  /// Builds a [MistakeSpan] from its DTO.
  factory MistakeSpan.fromDto(MistakeSpanDto dto) =>
      MistakeSpan(start: dto.start, end: dto.end, text: dto.text);

  /// Inclusive start offset into the original message.
  final int start;

  /// Exclusive end offset into the original message.
  final int end;

  /// The flagged substring.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is MistakeSpan &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'MistakeSpan($start, $end, "$text")';
}

/// A native-language translation attached to [GrammarFeedback].
///
/// [language] is the learner's selected [NativeLanguage] (one of
/// `hi|ta|te|bn|mr`) and [text] is the tip/explanation rendered in that
/// language. Mirrors the design's `Grammar_Feedback.translation`.
@immutable
class FeedbackTranslation {
  const FeedbackTranslation({required this.language, required this.text});

  /// Builds a [FeedbackTranslation] from its DTO, parsing the raw language
  /// string into a [NativeLanguage]. Returns `null` when the language is not
  /// one of the supported set, since an unknown language cannot be rendered.
  static FeedbackTranslation? fromDto(TranslationDto dto) {
    final language = NativeLanguage.fromWire(dto.language);
    if (language == null) return null;
    return FeedbackTranslation(language: language, text: dto.text);
  }

  /// The language the [text] is written in.
  final NativeLanguage language;

  /// The translated tip/explanation.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is FeedbackTranslation &&
      other.language == language &&
      other.text == text;

  @override
  int get hashCode => Object.hash(language, text);

  @override
  String toString() => 'FeedbackTranslation(${language.wireValue}, "$text")';
}

/// Structured grammar feedback the AI teacher returns for a learner message.
///
/// Mirrors the design's `Grammar_Feedback` schema: when [hasMistake] is true
/// the [mistakeSpan] marks what to render in red and [correctedSentence] is
/// rendered in green; [tip] is a short coaching note and [translation] carries
/// the native-language explanation. When [hasMistake] is false, [mistakeSpan]
/// is `null` and no red styling is applied. (Requirements 4.2, 4.3)
@immutable
class GrammarFeedback {
  const GrammarFeedback({
    required this.hasMistake,
    this.mistakeSpan,
    required this.correctedSentence,
    required this.tip,
    required this.translation,
  });

  /// Builds domain [GrammarFeedback] from its DTO, returning `null` when the
  /// DTO is structurally unusable (e.g. an unsupported translation language),
  /// so callers surface a reply without feedback rather than a broken card.
  static GrammarFeedback? fromDto(GrammarFeedbackDto dto) {
    final translation = FeedbackTranslation.fromDto(dto.translation);
    if (translation == null) return null;
    return GrammarFeedback(
      hasMistake: dto.hasMistake,
      // Ignore a span when there is no mistake, matching the schema.
      mistakeSpan: dto.hasMistake && dto.mistakeSpan != null
          ? MistakeSpan.fromDto(dto.mistakeSpan!)
          : null,
      correctedSentence: dto.correctedSentence,
      tip: dto.tip,
      translation: translation,
    );
  }

  /// Whether the learner's message contained a flagged mistake.
  final bool hasMistake;

  /// The flagged span, present only when [hasMistake] is true.
  final MistakeSpan? mistakeSpan;

  /// The corrected sentence, rendered in green.
  final String correctedSentence;

  /// A short coaching tip.
  final String tip;

  /// The native-language explanation.
  final FeedbackTranslation translation;

  @override
  bool operator ==(Object other) =>
      other is GrammarFeedback &&
      other.hasMistake == hasMistake &&
      other.mistakeSpan == mistakeSpan &&
      other.correctedSentence == correctedSentence &&
      other.tip == tip &&
      other.translation == translation;

  @override
  int get hashCode => Object.hash(
        hasMistake,
        mistakeSpan,
        correctedSentence,
        tip,
        translation,
      );

  @override
  String toString() =>
      'GrammarFeedback(hasMistake: $hasMistake, corrected: "$correctedSentence")';
}

/// A single message in a chat session: either the learner's text or a teacher
/// reply (which may carry [grammarFeedback]).
///
/// Mirrors `users/{uid}/chatSessions/{sessionId}/messages/{messageId}`:
/// `role, text, grammarFeedback|null, createdAt`. A learner message carries no
/// feedback; a reply carries feedback when the AI returned it.
@immutable
class ChatMessage {
  const ChatMessage({
    this.id,
    required this.role,
    required this.text,
    this.grammarFeedback,
    this.createdAt,
  });

  /// Builds a [ChatMessage] from its DTO and optional document [id].
  factory ChatMessage.fromDto(ChatMessageDto dto, {String? id}) {
    final feedbackDto = dto.grammarFeedback;
    return ChatMessage(
      id: id,
      role: ChatRole.fromWire(dto.role),
      text: dto.text,
      grammarFeedback:
          feedbackDto == null ? null : GrammarFeedback.fromDto(feedbackDto),
      createdAt: dto.createdAt,
    );
  }

  /// Convenience constructor for a learner message.
  const ChatMessage.user(this.text, {this.id, this.createdAt})
      : role = ChatRole.user,
        grammarFeedback = null;

  /// The Firestore document id, when the message has been persisted.
  final String? id;

  /// Who authored the message.
  final ChatRole role;

  /// The message body.
  final String text;

  /// Structured feedback on the preceding learner message; only ever present
  /// on an [ChatRole.assistant] reply.
  final GrammarFeedback? grammarFeedback;

  /// When the message was created, when known.
  final DateTime? createdAt;

  /// Returns a copy with the given fields replaced.
  ChatMessage copyWith({
    String? id,
    String? text,
    GrammarFeedback? grammarFeedback,
    DateTime? createdAt,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        role: role,
        text: text ?? this.text,
        grammarFeedback: grammarFeedback ?? this.grammarFeedback,
        createdAt: createdAt ?? this.createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is ChatMessage &&
      other.id == id &&
      other.role == role &&
      other.text == text &&
      other.grammarFeedback == grammarFeedback &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, role, text, grammarFeedback, createdAt);

  @override
  String toString() =>
      'ChatMessage(id: $id, role: ${role.wireValue}, text: "$text")';
}

/// A learner-filed report of a wrong correction, capturing the full context
/// of the flagged feedback for later review. (Requirements 5.3, 5.4)
///
/// Mirrors `users/{uid}/reports/{reportId}`: `sessionId, messageId,
/// originalText, grammarFeedback, reason, status, createdAt`. [status] starts
/// as [ReportStatus.open] and is advanced to [ReportStatus.reviewed] by the
/// moderation review flow (server-side).
@immutable
class Report {
  const Report({
    this.id,
    required this.sessionId,
    required this.messageId,
    required this.originalText,
    this.grammarFeedback,
    this.reason,
    this.status = ReportStatus.open,
    this.createdAt,
  });

  /// Builds a [Report] from its DTO and optional document [id].
  factory Report.fromDto(ReportDto dto, {String? id}) {
    final feedbackDto = dto.grammarFeedback;
    return Report(
      id: id,
      sessionId: dto.sessionId,
      messageId: dto.messageId,
      originalText: dto.originalText,
      grammarFeedback:
          feedbackDto == null ? null : GrammarFeedback.fromDto(feedbackDto),
      reason: dto.reason,
      status: ReportStatus.fromWire(dto.status),
      createdAt: dto.createdAt,
    );
  }

  /// The Firestore document id, when the report has been persisted.
  final String? id;

  /// The chat session the reported message belongs to.
  final String sessionId;

  /// The reported message's id.
  final String messageId;

  /// The learner's original text that was corrected.
  final String originalText;

  /// A snapshot of the feedback being reported.
  final GrammarFeedback? grammarFeedback;

  /// An optional free-text reason the learner supplied.
  final String? reason;

  /// The review lifecycle state of the report.
  final ReportStatus status;

  /// When the report was filed, when known.
  final DateTime? createdAt;

  @override
  bool operator ==(Object other) =>
      other is Report &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.messageId == messageId &&
      other.originalText == originalText &&
      other.grammarFeedback == grammarFeedback &&
      other.reason == reason &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        sessionId,
        messageId,
        originalText,
        grammarFeedback,
        reason,
        status,
        createdAt,
      );

  @override
  String toString() =>
      'Report(id: $id, sessionId: $sessionId, status: ${status.wireValue})';
}

/// The review lifecycle state of a [Report].
enum ReportStatus {
  /// Filed and awaiting review.
  open('open'),

  /// Reviewed by moderation.
  reviewed('reviewed');

  const ReportStatus(this.wireValue);

  /// The Firestore/wire representation of this status.
  final String wireValue;

  /// Parses a stored [value] into a [ReportStatus], defaulting to [open] when
  /// the value is missing or unrecognized.
  static ReportStatus fromWire(String? value) {
    for (final status in ReportStatus.values) {
      if (status.wireValue == value) return status;
    }
    return ReportStatus.open;
  }
}
