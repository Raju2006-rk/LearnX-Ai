import 'package:flutter/foundation.dart';

/// The authored, pre-written content for a single step, loaded read-only from
/// `content/.../steps/{stepId}`'s `skeleton` block.
///
/// This is the content a learner always sees for a step regardless of whether
/// AI personalization succeeds, fails, or is withheld by moderation. It is the
/// stable fallback the step-detail flow renders first; AI content (see
/// [StepPersonalization]) is layered on top, never in place of it.
/// (Requirement 3.6)
@immutable
class StepSkeleton {
  const StepSkeleton({
    this.objectives = const [],
    this.examples = const [],
    this.practice = const [],
  });

  /// The learning objectives for the step.
  final List<String> objectives;

  /// Authored worked examples.
  final List<String> examples;

  /// Authored practice prompts.
  final List<String> practice;

  @override
  bool operator ==(Object other) =>
      other is StepSkeleton &&
      listEquals(other.objectives, objectives) &&
      listEquals(other.examples, examples) &&
      listEquals(other.practice, practice);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(objectives),
    Object.hashAll(examples),
    Object.hashAll(practice),
  );

  @override
  String toString() =>
      'StepSkeleton(objectives: ${objectives.length}, '
      'examples: ${examples.length}, practice: ${practice.length})';
}

/// AI-personalized additions for a step returned by the `personalizeLesson`
/// callable, tagged by the learner's CEFR level and goal.
///
/// Personalization is **strictly additive**: these examples and practice items
/// supplement the authored [StepSkeleton] and never replace it. The callable
/// returns an empty/`null` personalization on any failure or moderation
/// refusal; [StepPersonalization.empty] models that absence, and the step
/// detail then shows the skeleton alone. (Requirements 3.5, 3.6)
@immutable
class StepPersonalization {
  const StepPersonalization({
    this.examples = const [],
    this.practice = const [],
  });

  /// The absent personalization: no AI examples or practice. Used when the
  /// callable returns empty/`null` or the request fails, so the step renders
  /// the authored skeleton only.
  static const StepPersonalization empty = StepPersonalization();

  /// AI-generated examples to append after the authored examples.
  final List<String> examples;

  /// AI-generated practice prompts to append after the authored practice.
  final List<String> practice;

  /// Whether this personalization adds anything to render. `false` is the
  /// skeleton-only case.
  bool get isEmpty => examples.isEmpty && practice.isEmpty;

  /// Whether this personalization contributes any AI content.
  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) =>
      other is StepPersonalization &&
      listEquals(other.examples, examples) &&
      listEquals(other.practice, practice);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(examples), Object.hashAll(practice));

  @override
  String toString() =>
      'StepPersonalization(examples: ${examples.length}, '
      'practice: ${practice.length})';
}

/// The resolved content a learner sees when they open a step: the authored
/// [skeleton] combined with any AI [personalization].
///
/// The invariant the whole step-detail flow hangs on (design's "Skeleton
/// content is always present", Property 7): the authored skeleton is always
/// part of the rendered content, and AI personalization is strictly additive —
/// its absence can never remove skeleton content. The combined
/// [examples]/[practice] getters therefore always start with the full skeleton
/// list and only *append* AI items, so [containsSkeleton] is `true` for every
/// possible personalization, including [StepPersonalization.empty].
/// (Requirements 3.5, 3.6)
@immutable
class StepContent {
  const StepContent({
    required this.stepId,
    required this.title,
    required this.skeleton,
    this.personalization = StepPersonalization.empty,
  });

  /// The authored step id this content belongs to.
  final String stepId;

  /// The authored step title.
  final String title;

  /// The always-rendered authored content.
  final StepSkeleton skeleton;

  /// The additive AI content; [StepPersonalization.empty] when absent.
  final StepPersonalization personalization;

  /// The authored objectives (never personalized — objectives are skeleton
  /// only).
  List<String> get objectives => skeleton.objectives;

  /// The examples to render: every authored example first, then any AI
  /// examples appended. The skeleton examples always appear.
  List<String> get examples => <String>[
    ...skeleton.examples,
    ...personalization.examples,
  ];

  /// The practice prompts to render: every authored prompt first, then any AI
  /// prompts appended. The skeleton practice always appears.
  List<String> get practice => <String>[
    ...skeleton.practice,
    ...personalization.practice,
  ];

  /// Whether AI personalization contributed anything to this content.
  bool get hasPersonalization => personalization.isNotEmpty;

  /// Whether every authored skeleton item is present in the combined content.
  ///
  /// This is the testable form of the skeleton-always-present invariant: for
  /// any personalization the combined [examples]/[practice] contain the full
  /// skeleton lists (as a prefix), and [objectives] is exactly the skeleton's.
  bool get containsSkeleton =>
      _startsWith(objectives, skeleton.objectives) &&
      _startsWith(examples, skeleton.examples) &&
      _startsWith(practice, skeleton.practice);

  /// Returns a copy with [personalization] replaced.
  StepContent withPersonalization(StepPersonalization personalization) =>
      StepContent(
        stepId: stepId,
        title: title,
        skeleton: skeleton,
        personalization: personalization,
      );

  static bool _startsWith(List<String> whole, List<String> prefix) {
    if (prefix.length > whole.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (whole[i] != prefix[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is StepContent &&
      other.stepId == stepId &&
      other.title == title &&
      other.skeleton == skeleton &&
      other.personalization == personalization;

  @override
  int get hashCode => Object.hash(stepId, title, skeleton, personalization);

  @override
  String toString() =>
      'StepContent(stepId: $stepId, hasPersonalization: $hasPersonalization)';
}
