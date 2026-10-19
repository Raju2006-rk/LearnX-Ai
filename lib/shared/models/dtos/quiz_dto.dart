import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for the global quiz-item bank `quizItems/{itemId}`:
/// `type ("fill_blank"|"choose_word"), prompt, options[], answer, tags[]`.
///
/// `type` is carried as a raw string; the quiz domain validates it.
@immutable
class QuizItemDto {
  const QuizItemDto({
    required this.type,
    required this.prompt,
    this.options = const [],
    required this.answer,
    this.tags = const [],
  });

  factory QuizItemDto.fromMap(Map<String, dynamic> map) {
    return QuizItemDto(
      type: stringOr(map['type']),
      prompt: stringOr(map['prompt']),
      options: stringListFrom(map['options']),
      answer: stringOr(map['answer']),
      tags: stringListFrom(map['tags']),
    );
  }

  /// `"fill_blank" | "choose_word"`.
  final String type;
  final String prompt;
  final List<String> options;
  final String answer;
  final List<String> tags;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type,
      'prompt': prompt,
      'options': options,
      'answer': answer,
      'tags': tags,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is QuizItemDto &&
      other.type == type &&
      other.prompt == prompt &&
      listEquals(other.options, options) &&
      other.answer == answer &&
      listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
    type,
    prompt,
    Object.hashAll(options),
    answer,
    Object.hashAll(tags),
  );
}

/// DTO for `users/{uid}/reviewQueue/{itemId}`:
/// `itemId, intervalIndex, dueDate, lastResult ("correct"|"wrong"),
/// updatedAt`.
///
/// `intervalIndex` indexes the design's Leitner interval ladder
/// (`INTERVALS_DAYS`). `lastResult` is carried as a raw string.
@immutable
class ReviewQueueItemDto {
  const ReviewQueueItemDto({
    required this.itemId,
    this.intervalIndex = 0,
    this.dueDate,
    this.lastResult,
    this.updatedAt,
  });

  factory ReviewQueueItemDto.fromMap(Map<String, dynamic> map) {
    return ReviewQueueItemDto(
      itemId: stringOr(map['itemId']),
      intervalIndex: intOr(map['intervalIndex']),
      dueDate: dateTimeFromFirestore(map['dueDate']),
      lastResult: stringOrNull(map['lastResult']),
      updatedAt: dateTimeFromFirestore(map['updatedAt']),
    );
  }

  final String itemId;
  final int intervalIndex;
  final DateTime? dueDate;

  /// `"correct" | "wrong"`.
  final String? lastResult;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'itemId': itemId,
      'intervalIndex': intervalIndex,
      'dueDate': timestampFromDateTime(dueDate),
      'lastResult': lastResult,
      'updatedAt': timestampFromDateTime(updatedAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ReviewQueueItemDto &&
      other.itemId == itemId &&
      other.intervalIndex == intervalIndex &&
      other.dueDate == dueDate &&
      other.lastResult == lastResult &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(itemId, intervalIndex, dueDate, lastResult, updatedAt);
}

/// DTO for `users/{uid}/quizSessions/{sessionId}`:
/// `startedAt, completedAt, correctCount, wrongCount, updatedAt`.
///
/// `updatedAt` carries the last-write-wins sync timestamp so a quiz result
/// earned offline — queued by Firestore offline persistence and replayed on
/// reconnect — resolves against server state by the server clock rather than
/// blindly overwriting it. (Requirement 8.2)
@immutable
class QuizSessionDto {
  const QuizSessionDto({
    this.startedAt,
    this.completedAt,
    this.correctCount = 0,
    this.wrongCount = 0,
    this.updatedAt,
  });

  factory QuizSessionDto.fromMap(Map<String, dynamic> map) {
    return QuizSessionDto(
      startedAt: dateTimeFromFirestore(map['startedAt']),
      completedAt: dateTimeFromFirestore(map['completedAt']),
      correctCount: intOr(map['correctCount']),
      wrongCount: intOr(map['wrongCount']),
      updatedAt: dateTimeFromFirestore(map['updatedAt']),
    );
  }

  final DateTime? startedAt;
  final DateTime? completedAt;
  final int correctCount;
  final int wrongCount;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'startedAt': timestampFromDateTime(startedAt),
      'completedAt': timestampFromDateTime(completedAt),
      'correctCount': correctCount,
      'wrongCount': wrongCount,
      'updatedAt': timestampFromDateTime(updatedAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is QuizSessionDto &&
      other.startedAt == startedAt &&
      other.completedAt == completedAt &&
      other.correctCount == correctCount &&
      other.wrongCount == wrongCount &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(startedAt, completedAt, correctCount, wrongCount, updatedAt);
}
