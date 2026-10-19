import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for `users/{uid}/chatSessions/{sessionId}`:
/// `createdAt, lastMessageAt, title`.
@immutable
class ChatSessionDto {
  const ChatSessionDto({this.createdAt, this.lastMessageAt, this.title});

  factory ChatSessionDto.fromMap(Map<String, dynamic> map) {
    return ChatSessionDto(
      createdAt: dateTimeFromFirestore(map['createdAt']),
      lastMessageAt: dateTimeFromFirestore(map['lastMessageAt']),
      title: stringOrNull(map['title']),
    );
  }

  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final String? title;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'createdAt': timestampFromDateTime(createdAt),
      'lastMessageAt': timestampFromDateTime(lastMessageAt),
      'title': title,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ChatSessionDto &&
      other.createdAt == createdAt &&
      other.lastMessageAt == lastMessageAt &&
      other.title == title;

  @override
  int get hashCode => Object.hash(createdAt, lastMessageAt, title);
}

/// DTO for a `Grammar_Feedback.mistakeSpan`: `{ start, end, text }`.
///
/// Omitted from the parent map when the feedback has no mistake, matching the
/// design's Grammar_Feedback schema.
@immutable
class MistakeSpanDto {
  const MistakeSpanDto({
    required this.start,
    required this.end,
    required this.text,
  });

  factory MistakeSpanDto.fromMap(Map<String, dynamic> map) {
    return MistakeSpanDto(
      start: intOr(map['start']),
      end: intOr(map['end']),
      text: stringOr(map['text']),
    );
  }

  final int start;
  final int end;
  final String text;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'start': start, 'end': end, 'text': text};

  @override
  bool operator ==(Object other) =>
      other is MistakeSpanDto &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}

/// DTO for a `Grammar_Feedback.translation`: `{ language, text }`.
///
/// `language` is one of the supported native languages (`hi|ta|te|bn|mr`),
/// carried as a raw string.
@immutable
class TranslationDto {
  const TranslationDto({required this.language, required this.text});

  factory TranslationDto.fromMap(Map<String, dynamic> map) {
    return TranslationDto(
      language: stringOr(map['language']),
      text: stringOr(map['text']),
    );
  }

  final String language;
  final String text;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'language': language, 'text': text};

  @override
  bool operator ==(Object other) =>
      other is TranslationDto &&
      other.language == language &&
      other.text == text;

  @override
  int get hashCode => Object.hash(language, text);
}

/// DTO for a `Grammar_Feedback` object.
///
/// Mirrors the design's response schema:
/// `hasMistake, mistakeSpan?, correctedSentence, tip, translation`.
/// `mistakeSpan` is present only when [hasMistake] is true and is omitted
/// from [toMap] otherwise.
@immutable
class GrammarFeedbackDto {
  const GrammarFeedbackDto({
    required this.hasMistake,
    this.mistakeSpan,
    required this.correctedSentence,
    required this.tip,
    required this.translation,
  });

  factory GrammarFeedbackDto.fromMap(Map<String, dynamic> map) {
    final spanMap = mapOrNull(map['mistakeSpan']);
    return GrammarFeedbackDto(
      hasMistake: boolOr(map['hasMistake']),
      mistakeSpan: spanMap == null ? null : MistakeSpanDto.fromMap(spanMap),
      correctedSentence: stringOr(map['correctedSentence']),
      tip: stringOr(map['tip']),
      translation: TranslationDto.fromMap(mapOrNull(map['translation']) ?? const {}),
    );
  }

  final bool hasMistake;
  final MistakeSpanDto? mistakeSpan;
  final String correctedSentence;
  final String tip;
  final TranslationDto translation;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'hasMistake': hasMistake,
      // Omit mistakeSpan entirely when there is no mistake.
      if (hasMistake && mistakeSpan != null) 'mistakeSpan': mistakeSpan!.toMap(),
      'correctedSentence': correctedSentence,
      'tip': tip,
      'translation': translation.toMap(),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is GrammarFeedbackDto &&
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
}

/// DTO for `users/{uid}/chatSessions/{sessionId}/messages/{messageId}`:
/// `role ("user"|"assistant"), text, grammarFeedback|null, createdAt`.
@immutable
class ChatMessageDto {
  const ChatMessageDto({
    required this.role,
    required this.text,
    this.grammarFeedback,
    this.createdAt,
  });

  factory ChatMessageDto.fromMap(Map<String, dynamic> map) {
    final feedbackMap = mapOrNull(map['grammarFeedback']);
    return ChatMessageDto(
      role: stringOr(map['role']),
      text: stringOr(map['text']),
      grammarFeedback:
          feedbackMap == null ? null : GrammarFeedbackDto.fromMap(feedbackMap),
      createdAt: dateTimeFromFirestore(map['createdAt']),
    );
  }

  /// `"user" | "assistant"`.
  final String role;
  final String text;
  final GrammarFeedbackDto? grammarFeedback;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'role': role,
      'text': text,
      'grammarFeedback': grammarFeedback?.toMap(),
      'createdAt': timestampFromDateTime(createdAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ChatMessageDto &&
      other.role == role &&
      other.text == text &&
      other.grammarFeedback == grammarFeedback &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(role, text, grammarFeedback, createdAt);
}
