import 'package:flutter/foundation.dart';

import '../../../shared/models/dtos/dtos.dart';

/// The spaced-repetition interval ladder (Leitner-style), in days until the
/// next due date for each [ReviewItem.intervalIndex].
///
/// `intervalIndex` indexes into this list: a freshly-missed item starts at
/// index 0 (due in 1 day) and each correct review answer advances to a
/// strictly longer interval, clamped at the final index. Mirrors the design's
/// `INTERVALS_DAYS = [1, 3, 7, 16, 35]`. (Requirements 6.3, 6.4, 6.5)
// ignore: constant_identifier_names
const List<int> INTERVALS_DAYS = <int>[1, 3, 7, 16, 35];

/// The kind of quiz question, matching the authored `quizItems` bank.
///
/// The [wireValue] matches the raw `type` string stored on a `quizItems`
/// document (`"fill_blank" | "choose_word"`), so the feature never
/// hand-writes these literals. (Requirement 6.1)
enum QuestionType {
  /// Fill-in-the-blank: the learner types the missing word.
  fillBlank('fill_blank'),

  /// Choose-the-right-word: the learner picks from [Question.options].
  chooseWord('choose_word');

  const QuestionType(this.wireValue);

  /// The Firestore/wire representation of this type.
  final String wireValue;

  /// Parses a stored [value] into a [QuestionType], defaulting to
  /// [fillBlank] when the value is missing or unrecognized so an unknown
  /// authored type degrades to a free-text answer rather than crashing.
  static QuestionType fromWire(String? value) {
    for (final type in QuestionType.values) {
      if (type.wireValue == value) return type;
    }
    return QuestionType.fillBlank;
  }
}

/// A single authored quiz question from the global `quizItems/{itemId}` bank.
///
/// [id] is the `quizItems` document id (used to key a learner's
/// [ReviewItem]). [options] is empty for [QuestionType.fillBlank] questions
/// and carries the choices for [QuestionType.chooseWord]. [answer] is the
/// expected answer the quiz scores against; [tags] group questions by topic.
/// (Requirement 6.1)
@immutable
class Question {
  const Question({
    required this.id,
    required this.type,
    required this.prompt,
    required this.answer,
    this.options = const [],
    this.tags = const [],
  });

  /// Builds a [Question] from its authored DTO and the document [id].
  factory Question.fromDto(String id, QuizItemDto dto) => Question(
    id: id,
    type: QuestionType.fromWire(dto.type),
    prompt: dto.prompt,
    answer: dto.answer,
    options: dto.options,
    tags: dto.tags,
  );

  /// The `quizItems` document id.
  final String id;

  /// Whether this is a fill-in-the-blank or choose-the-word question.
  final QuestionType type;

  /// The question text shown to the learner.
  final String prompt;

  /// The expected answer used to score an [Answer].
  final String answer;

  /// The choices for a [QuestionType.chooseWord] question; empty otherwise.
  final List<String> options;

  /// Topic tags for this question.
  final List<String> tags;

  /// Whether [response] is the correct answer to this question.
  ///
  /// Comparison is case-insensitive and ignores surrounding whitespace so a
  /// learner is not penalized for capitalization or stray spaces.
  bool isCorrect(String response) =>
      response.trim().toLowerCase() == answer.trim().toLowerCase();

  @override
  bool operator ==(Object other) =>
      other is Question &&
      other.id == id &&
      other.type == type &&
      other.prompt == prompt &&
      other.answer == answer &&
      listEquals(other.options, options) &&
      listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
    id,
    type,
    prompt,
    answer,
    Object.hashAll(options),
    Object.hashAll(tags),
  );

  @override
  String toString() => 'Question(id: $id, type: ${type.wireValue})';
}

/// The result of scoring a learner's response to a [Question].
///
/// Carries the [questionId] it refers to, the learner's raw [response], and
/// whether it was [correct]. A wrong answer drives the question into the
/// spaced-repetition [ReviewItem] queue (Requirement 6.3); correct/wrong
/// counts aggregate into a session's score (Requirement 6.2).
@immutable
class Answer {
  const Answer({
    required this.questionId,
    required this.response,
    required this.correct,
  });

  /// Scores [response] against [question], producing an [Answer].
  factory Answer.score(Question question, String response) => Answer(
    questionId: question.id,
    response: response,
    correct: question.isCorrect(response),
  );

  /// The id of the [Question] this answers.
  final String questionId;

  /// The learner's raw response.
  final String response;

  /// Whether the response matched the question's expected answer.
  final bool correct;

  @override
  bool operator ==(Object other) =>
      other is Answer &&
      other.questionId == questionId &&
      other.response == response &&
      other.correct == correct;

  @override
  int get hashCode => Object.hash(questionId, response, correct);

  @override
  String toString() =>
      'Answer(questionId: $questionId, correct: $correct)';
}

/// The outcome of the most recent attempt at a [ReviewItem].
///
/// The [wireValue] matches the `lastResult` string stored on a
/// `reviewQueue` document (`"correct" | "wrong"`).
enum ReviewResult {
  /// The learner answered the item correctly on its last review.
  correct('correct'),

  /// The learner answered the item incorrectly on its last review.
  wrong('wrong');

  const ReviewResult(this.wireValue);

  /// The Firestore/wire representation of this result.
  final String wireValue;

  /// Parses a stored [value] into a [ReviewResult], returning `null` when the
  /// value is missing or unrecognized.
  static ReviewResult? fromWire(String? value) {
    if (value == null) return null;
    for (final result in ReviewResult.values) {
      if (result.wireValue == value) return result;
    }
    return null;
  }
}

/// A learner's spaced-repetition entry for one quiz [Question], mirroring a
/// `users/{uid}/reviewQueue/{itemId}` document.
///
/// [itemId] is the `quizItems` id the entry tracks. [intervalIndex] points
/// into [INTERVALS_DAYS]; [dueDate] is when the item next surfaces in a quiz;
/// [lastResult] records the most recent attempt; [updatedAt] stamps the last
/// write for last-write-wins sync. The scheduling transitions themselves live
/// in [SpacedRepetition]. (Requirements 6.3, 6.4, 6.5)
@immutable
class ReviewItem {
  const ReviewItem({
    required this.itemId,
    required this.intervalIndex,
    this.dueDate,
    this.lastResult,
    this.updatedAt,
  });

  /// Builds a [ReviewItem] from its DTO, clamping [intervalIndex] into the
  /// valid ladder range so a corrupt stored value can never index out of
  /// bounds.
  factory ReviewItem.fromDto(ReviewQueueItemDto dto) => ReviewItem(
    itemId: dto.itemId,
    intervalIndex: dto.intervalIndex.clamp(0, INTERVALS_DAYS.length - 1),
    dueDate: dto.dueDate,
    lastResult: ReviewResult.fromWire(dto.lastResult),
    updatedAt: dto.updatedAt,
  );

  /// The `quizItems` id this entry tracks (the `reviewQueue` document key).
  final String itemId;

  /// Index into [INTERVALS_DAYS] for the current review interval.
  final int intervalIndex;

  /// When this item is next due to be reviewed, or `null` if unscheduled.
  final DateTime? dueDate;

  /// The outcome of the most recent attempt, or `null` if never reviewed.
  final ReviewResult? lastResult;

  /// Last write time, used for last-write-wins sync.
  final DateTime? updatedAt;

  /// Whether this item is due for review at [now] (its [dueDate] has passed).
  ///
  /// An item with no [dueDate] is treated as due so a newly-queued item can
  /// surface rather than being stranded. (Requirement 6.4)
  bool isDueAt(DateTime now) => dueDate == null || !dueDate!.isAfter(now);

  /// Serializes this item back to its DTO for persistence.
  ReviewQueueItemDto toDto() => ReviewQueueItemDto(
    itemId: itemId,
    intervalIndex: intervalIndex,
    dueDate: dueDate,
    lastResult: lastResult?.wireValue,
    updatedAt: updatedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is ReviewItem &&
      other.itemId == itemId &&
      other.intervalIndex == intervalIndex &&
      other.dueDate == dueDate &&
      other.lastResult == lastResult &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      Object.hash(itemId, intervalIndex, dueDate, lastResult, updatedAt);

  @override
  String toString() =>
      'ReviewItem(itemId: $itemId, intervalIndex: $intervalIndex, '
      'dueDate: $dueDate)';
}

/// The pure spaced-repetition scheduling rules over the [INTERVALS_DAYS]
/// ladder, with no I/O so the transitions are trivially testable.
///
/// Mirrors the design's "Spaced-Repetition Scheduling" pseudocode: a wrong
/// answer (re)schedules an item at the shortest interval, a correct review
/// answer advances it to a strictly longer interval (clamped at the final
/// rung), and only items whose [ReviewItem.dueDate] has passed are surfaced
/// in a session. (Requirements 6.3, 6.4, 6.5)
abstract final class SpacedRepetition {
  const SpacedRepetition._();

  /// The largest valid [ReviewItem.intervalIndex].
  static int get lastIntervalIndex => INTERVALS_DAYS.length - 1;

  /// The number of days until the next review for [intervalIndex], clamped
  /// into the valid ladder range.
  static int daysForIndex(int intervalIndex) =>
      INTERVALS_DAYS[intervalIndex.clamp(0, lastIntervalIndex)];

  /// The due date for [intervalIndex] measured from [from] (defaults to the
  /// item's scheduling moment), advancing by [daysForIndex] days.
  static DateTime dueDateFor(int intervalIndex, DateTime from) =>
      from.add(Duration(days: daysForIndex(intervalIndex)));

  /// Schedules a freshly-missed [itemId] at the shortest interval
  /// (`intervalIndex 0`), due [INTERVALS_DAYS]`[0]` days after [now].
  ///
  /// Used when any quiz answer is wrong to (re)enter the review queue.
  /// (Requirement 6.3)
  static ReviewItem onWrongAnswer({
    required String itemId,
    required DateTime now,
  }) => ReviewItem(
    itemId: itemId,
    intervalIndex: 0,
    dueDate: dueDateFor(0, now),
    lastResult: ReviewResult.wrong,
    updatedAt: now,
  );

  /// Applies a review outcome to an existing [item] at [now].
  ///
  /// A [correct] answer advances [ReviewItem.intervalIndex] by one, clamped at
  /// [lastIntervalIndex], so the next interval is strictly longer until the
  /// ladder's final rung (Requirement 6.5). A wrong answer resets the item to
  /// the shortest interval. In both cases [ReviewItem.dueDate] and
  /// [ReviewItem.lastResult] are recomputed and [ReviewItem.updatedAt] is
  /// stamped.
  static ReviewItem onReviewAnswer({
    required ReviewItem item,
    required bool correct,
    required DateTime now,
  }) {
    final nextIndex = correct
        ? (item.intervalIndex + 1).clamp(0, lastIntervalIndex)
        : 0;
    return ReviewItem(
      itemId: item.itemId,
      intervalIndex: nextIndex,
      dueDate: dueDateFor(nextIndex, now),
      lastResult: correct ? ReviewResult.correct : ReviewResult.wrong,
      updatedAt: now,
    );
  }

  /// Returns the subset of [items] due at [now], ordered by [ReviewItem.dueDate]
  /// (earliest first; items with no due date sort first as they are treated as
  /// immediately due). Only these are presented at quiz start. (Requirement 6.4)
  static List<ReviewItem> dueItems(List<ReviewItem> items, DateTime now) {
    final due = items.where((item) => item.isDueAt(now)).toList();
    due.sort((a, b) {
      final ad = a.dueDate;
      final bd = b.dueDate;
      if (ad == null && bd == null) return 0;
      if (ad == null) return -1;
      if (bd == null) return 1;
      return ad.compareTo(bd);
    });
    return due;
  }
}
