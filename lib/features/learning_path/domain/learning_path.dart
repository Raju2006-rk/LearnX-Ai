import 'package:flutter/foundation.dart';

/// The id of the single authored learning path shipped with the MVP.
///
/// The MVP has one curated path for every learner; the id identifies its
/// authored skeleton under `content/{kDefaultPathId}` and keys the learner's
/// per-step progress. A later milestone that offers multiple paths would
/// replace this constant with a per-learner selection.
const String kDefaultPathId = 'mvp';

/// The lifecycle state of a single learning-path [Step] for a given learner.
///
/// A step is exactly one of these at any time. The rule the whole feature
/// hangs on (design's "Path unlock invariant", Property 6):
///
/// - the **first** step of the path is [available] from the start;
/// - any later step is [available] *iff* its immediately preceding step is
///   [completed], otherwise it stays [locked];
/// - a step the learner has finished is [completed] (as recorded in
///   `users/{uid}/pathProgress/{stepId}`).
///
/// The [wireValue] matches the raw `state` string stored on the
/// `pathProgress` document ("locked" | "available" | "completed").
/// (Requirements 3.2, 3.3, 3.4)
enum StepState {
  /// The step cannot be started yet because a preceding step is unfinished.
  locked('locked'),

  /// The step can be started now.
  available('available'),

  /// The learner has finished the step.
  completed('completed');

  const StepState(this.wireValue);

  /// The Firestore/wire representation of this state.
  final String wireValue;

  /// Whether the learner is allowed to start a step in this state.
  ///
  /// Only an [available] step is startable; [locked] and [completed] steps
  /// are not "started" (a locked step is gated, a completed step is done).
  bool get isStartable => this == StepState.available;

  /// Parses a stored [wireValue] back into a [StepState], returning `null`
  /// when the value is missing or unrecognized so callers can fall back to
  /// a derived state.
  static StepState? fromWire(String? value) {
    if (value == null) return null;
    for (final state in StepState.values) {
      if (state.wireValue == value) return state;
    }
    return null;
  }
}

/// A single learning unit shown as a circle on the path, combined with the
/// learner's resolved [state] for it.
///
/// [id], [title], [order], and [type] come from the authored skeleton
/// (`.../steps/{stepId}`); [state] is derived from the learner's progress
/// and the step's position in the ordered path (see [StepProgress]). The
/// authored personalization skeleton (objectives/examples/practice) is left
/// to the step-detail flow (task 6.4) and is not carried here.
@immutable
class Step {
  const Step({
    required this.id,
    required this.title,
    required this.order,
    required this.type,
    required this.state,
  });

  /// The authored step id (the `pathProgress` document key).
  final String id;

  final String title;

  /// Authoring order within the containing [Week].
  final int order;

  /// Authored step type (a rendering hint), carried as a raw string.
  final String type;

  /// The learner's resolved state for this step.
  final StepState state;

  /// Returns a copy with [state] replaced.
  Step copyWith({StepState? state}) => Step(
    id: id,
    title: title,
    order: order,
    type: type,
    state: state ?? this.state,
  );

  @override
  bool operator ==(Object other) =>
      other is Step &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      other.type == type &&
      other.state == state;

  @override
  int get hashCode => Object.hash(id, title, order, type, state);

  @override
  String toString() =>
      'Step(id: $id, order: $order, state: ${state.wireValue})';
}

/// An authored week grouping an ordered list of [steps].
@immutable
class Week {
  const Week({
    required this.id,
    required this.title,
    required this.order,
    required this.steps,
  });

  final String id;
  final String title;

  /// Authoring order within the containing [Section].
  final int order;

  /// The week's steps in authoring order.
  final List<Step> steps;

  @override
  bool operator ==(Object other) =>
      other is Week &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      listEquals(other.steps, steps);

  @override
  int get hashCode => Object.hash(id, title, order, Object.hashAll(steps));

  @override
  String toString() => 'Week(id: $id, order: $order, steps: ${steps.length})';
}

/// An authored section grouping an ordered list of [weeks].
@immutable
class Section {
  const Section({
    required this.id,
    required this.title,
    required this.order,
    required this.weeks,
  });

  final String id;
  final String title;

  /// Authoring order within the path.
  final int order;

  /// The section's weeks in authoring order.
  final List<Week> weeks;

  @override
  bool operator ==(Object other) =>
      other is Section &&
      other.id == id &&
      other.title == title &&
      other.order == order &&
      listEquals(other.weeks, weeks);

  @override
  int get hashCode => Object.hash(id, title, order, Object.hashAll(weeks));

  @override
  String toString() =>
      'Section(id: $id, order: $order, weeks: ${weeks.length})';
}

/// The learner's resolved view of a whole authored path: the ordered
/// [sections] with every [Step] carrying its derived [StepState].
///
/// Construct it with [StepProgress.resolve], which flattens the authored
/// skeleton into a single ordered step sequence, applies the unlock
/// invariant, and rebuilds the section/week/step tree with resolved states.
@immutable
class StepProgress {
  const StepProgress({required this.pathId, required this.sections});

  /// The authored path id these sections belong to.
  final String pathId;

  /// The resolved sections in authoring order.
  final List<Section> sections;

  /// Every step across all sections and weeks, in the single global
  /// authoring order the unlock rule walks.
  List<Step> get orderedSteps => <Step>[
    for (final section in sections)
      for (final week in section.weeks)
        for (final step in week.steps) step,
  ];

  /// Resolves the learner's [StepState] for every step in an authored path.
  ///
  /// [sections] is the authored skeleton (already sorted into authoring
  /// order by the caller, or sorted here defensively). [completedStepIds]
  /// is the set of step ids the learner has finished, taken from stored
  /// `pathProgress` documents whose `state == "completed"`.
  ///
  /// The derivation walks the single flattened step sequence and applies the
  /// unlock invariant (Requirements 3.2, 3.3, 3.4; design Property 6):
  ///
  /// - a step is [StepState.completed] when its id is in [completedStepIds];
  /// - otherwise the **first** step is [StepState.available];
  /// - otherwise a step is [StepState.available] iff its immediately
  ///   preceding step is [StepState.completed];
  /// - otherwise the step is [StepState.locked].
  ///
  /// "Preceding" means the previous step in the flattened order, so unlocking
  /// flows across week and section boundaries. The stored per-step `state` is
  /// intentionally *not* trusted for locked/available: those are always
  /// derived from completion so the path can never present a stale or
  /// inconsistent lock state.
  static StepProgress resolve({
    required String pathId,
    required List<Section> sections,
    required Set<String> completedStepIds,
  }) {
    final sortedSections = _sortedSections(sections);

    // Walk the flattened step order, tracking whether the previous step
    // resolved to completed, and rebuild the tree with resolved states.
    var previousCompleted = true; // the first step is treated as "unlocked"
    final resolvedSections = <Section>[];

    for (final section in sortedSections) {
      final resolvedWeeks = <Week>[];
      for (final week in section.weeks) {
        final resolvedSteps = <Step>[];
        for (final step in week.steps) {
          final StepState state;
          if (completedStepIds.contains(step.id)) {
            state = StepState.completed;
          } else if (previousCompleted) {
            state = StepState.available;
          } else {
            state = StepState.locked;
          }
          resolvedSteps.add(step.copyWith(state: state));
          previousCompleted = state == StepState.completed;
        }
        resolvedWeeks.add(
          Week(
            id: week.id,
            title: week.title,
            order: week.order,
            steps: resolvedSteps,
          ),
        );
      }
      resolvedSections.add(
        Section(
          id: section.id,
          title: section.title,
          order: section.order,
          weeks: resolvedWeeks,
        ),
      );
    }

    return StepProgress(pathId: pathId, sections: resolvedSections);
  }

  /// Returns [sections] sorted by authoring [Section.order], with each
  /// section's weeks and each week's steps also sorted by their `order`,
  /// so the flattened step sequence is deterministic regardless of the order
  /// Firestore returned documents in.
  static List<Section> _sortedSections(List<Section> sections) {
    final sorted = [...sections]..sort((a, b) => a.order.compareTo(b.order));
    return sorted
        .map(
          (section) => Section(
            id: section.id,
            title: section.title,
            order: section.order,
            weeks:
                ([...section.weeks]..sort((a, b) => a.order.compareTo(b.order)))
                    .map(
                      (week) => Week(
                        id: week.id,
                        title: week.title,
                        order: week.order,
                        steps: [...week.steps]
                          ..sort((a, b) => a.order.compareTo(b.order)),
                      ),
                    )
                    .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  @override
  bool operator ==(Object other) =>
      other is StepProgress &&
      other.pathId == pathId &&
      listEquals(other.sections, sections);

  @override
  int get hashCode => Object.hash(pathId, Object.hashAll(sections));

  @override
  String toString() =>
      'StepProgress(pathId: $pathId, sections: ${sections.length})';
}
