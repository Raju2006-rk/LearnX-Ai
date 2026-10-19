import 'package:flutter/foundation.dart';

import 'placement_engine.dart';

/// A client-facing placement question returned by the server-side
/// `generatePlacementQuestion` callable. (Requirement 2.4)
///
/// Deliberately carries no answer key: the difficulty ladder and the correct
/// answers stay on the server so the placement result can't be gamed. The
/// learner's answers are graded server-side and surfaced back as a
/// [PlacementGrade]. The [questionId] is echoed back when submitting the
/// learner's selected option so the server can grade it.
@immutable
class PlacementQuestion {
  const PlacementQuestion({
    required this.questionId,
    required this.band,
    required this.prompt,
    required this.options,
  });

  /// Builds a question from the callable's `question` payload, returning `null`
  /// when a required field is missing or malformed so the caller can surface a
  /// clean failure instead of rendering a broken question.
  static PlacementQuestion? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final questionId = map['questionId'];
    final band = CefrLevel.fromWire(map['band'] as String?);
    final prompt = map['prompt'];
    final rawOptions = map['options'];
    if (questionId is! String ||
        questionId.isEmpty ||
        band == null ||
        prompt is! String ||
        prompt.isEmpty ||
        rawOptions is! List) {
      return null;
    }
    final options = <String>[
      for (final option in rawOptions)
        if (option is String) option,
    ];
    if (options.length < 2) return null;
    return PlacementQuestion(
      questionId: questionId,
      band: band,
      prompt: prompt,
      options: List.unmodifiable(options),
    );
  }

  /// Server-issued id used to grade the learner's answer on the next call.
  final String questionId;

  /// The CEFR band this question targets.
  final CefrLevel band;

  /// The question prompt shown to the learner.
  final String prompt;

  /// The answer options, in display order. The correct index is never sent.
  final List<String> options;

  @override
  bool operator ==(Object other) =>
      other is PlacementQuestion &&
      other.questionId == questionId &&
      other.band == band &&
      other.prompt == prompt &&
      listEquals(other.options, options);

  @override
  int get hashCode =>
      Object.hash(questionId, band, prompt, Object.hashAll(options));

  @override
  String toString() =>
      'PlacementQuestion(questionId: $questionId, band: $band, '
      'prompt: $prompt, options: $options)';
}

/// The server's grading of a previously-served answer: correctness only, never
/// the correct option itself. (Requirement 2.4)
@immutable
class PlacementGrade {
  const PlacementGrade({required this.questionId, required this.correct});

  /// The question this grade is for.
  final String questionId;

  /// Whether the learner's submitted answer was correct.
  final bool correct;

  @override
  bool operator ==(Object other) =>
      other is PlacementGrade &&
      other.questionId == questionId &&
      other.correct == correct;

  @override
  int get hashCode => Object.hash(questionId, correct);

  @override
  String toString() =>
      'PlacementGrade(questionId: $questionId, correct: $correct)';
}

/// An answer the client submits for grading: the [questionId] it answers and
/// the [selectedIndex] the learner chose among that question's options.
@immutable
class PlacementAnswer {
  const PlacementAnswer({
    required this.questionId,
    required this.selectedIndex,
  });

  /// The server-issued id of the question being answered.
  final String questionId;

  /// The index the learner selected among the question's options.
  final int selectedIndex;

  /// The wire shape the callable expects for a prior answer.
  Map<String, dynamic> toMap() => <String, dynamic>{
        'questionId': questionId,
        'selectedIndex': selectedIndex,
      };

  @override
  bool operator ==(Object other) =>
      other is PlacementAnswer &&
      other.questionId == questionId &&
      other.selectedIndex == selectedIndex;

  @override
  int get hashCode => Object.hash(questionId, selectedIndex);
}

/// The combined result of one `generatePlacementQuestion` call: the next
/// [question] to present and the [gradedAnswers] for any prior answers
/// submitted alongside it. (Requirement 2.4)
@immutable
class PlacementQuestionResult {
  const PlacementQuestionResult({
    required this.question,
    required this.gradedAnswers,
  });

  /// The next question to present.
  final PlacementQuestion question;

  /// Grading of the prior answers submitted with this call.
  final List<PlacementGrade> gradedAnswers;

  @override
  bool operator ==(Object other) =>
      other is PlacementQuestionResult &&
      other.question == question &&
      listEquals(other.gradedAnswers, gradedAnswers);

  @override
  int get hashCode => Object.hash(question, Object.hashAll(gradedAnswers));
}
