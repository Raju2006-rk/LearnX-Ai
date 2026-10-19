// Property-based test for the learning-path unlock invariant.
//
// Property 6: Path unlock invariant. For any authored path and any set of
// completed steps, a step is startable if and only if it is the first step or
// its immediately preceding step is completed, and completing a step makes the
// immediately next step available. Locked steps can never be started.
// (Validates: Requirements 3.2, 3.3, 3.4)
//
// The project has no dedicated property-testing package, so this test follows
// the convention of `placement_property_test.dart`: drive many (200+) randomly
// generated inputs through the real `StepProgress.resolve` and assert the
// invariant over the flattened step order. A fixed seed keeps iterations
// reproducible; a failing case prints the generated scenario.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';

/// A randomly generated path shape plus the subset of step ids the learner has
/// completed, carried together so a failing iteration can print the scenario.
class _Scenario {
  const _Scenario({required this.sections, required this.completedStepIds});

  final List<Section> sections;
  final Set<String> completedStepIds;

  /// Every step id in global authoring order (sections → weeks → steps),
  /// already sorted by the generator so it matches resolve's flattening.
  List<String> get orderedStepIds => <String>[
        for (final section in sections)
          for (final week in section.weeks)
            for (final step in week.steps) step.id,
      ];

  @override
  String toString() {
    final shape = sections
        .map((s) => s.weeks.map((w) => w.steps.length).toList())
        .toList();
    return '_Scenario(shape: $shape, ordered: $orderedStepIds, '
        'completed: $completedStepIds)';
  }
}

/// Builds a varied path: 0..3 sections, each with 0..3 weeks, each with 0..4
/// steps, with monotonically increasing step ids (s1, s2, ...) in authoring
/// order. `order` fields are already authored in sequence so the generated
/// `orderedStepIds` matches what `resolve` produces after its own sort.
///
/// A random subset of the generated step ids is marked completed, and the
/// generator occasionally injects an id that is *not* in the path to confirm
/// unknown completions are ignored.
_Scenario _generateScenario(Random random) {
  var stepCounter = 0;
  final allStepIds = <String>[];

  final sectionCount = random.nextInt(4); // 0..3
  final sections = <Section>[
    for (var si = 0; si < sectionCount; si++)
      () {
        final weekCount = random.nextInt(4); // 0..3
        return Section(
          id: 'sec$si',
          title: 'Section $si',
          order: si,
          weeks: <Week>[
            for (var wi = 0; wi < weekCount; wi++)
              () {
                final stepCount = random.nextInt(5); // 0..4
                return Week(
                  id: 'sec${si}_wk$wi',
                  title: 'Week $wi',
                  order: wi,
                  steps: <Step>[
                    for (var sti = 0; sti < stepCount; sti++)
                      () {
                        final id = 's${stepCounter++}';
                        allStepIds.add(id);
                        return Step(
                          id: id,
                          title: id,
                          order: sti,
                          type: 'lesson',
                          // Seed with an arbitrary stored state to prove the
                          // resolver derives (never trusts) locked/available.
                          state: StepState
                              .values[random.nextInt(StepState.values.length)],
                        );
                      }(),
                  ],
                );
              }(),
          ],
        );
      }(),
  ];

  // Mark a random subset of real steps completed.
  final completed = <String>{
    for (final id in allStepIds)
      if (random.nextBool()) id,
  };
  // Occasionally add an id that is not part of the path; it must be ignored.
  if (random.nextBool()) {
    completed.add('ghost-${random.nextInt(1 << 20)}');
  }

  return _Scenario(sections: sections, completedStepIds: completed);
}

void main() {
  const iterations = 300;

  test(
    'Property 6: a step is available iff first-or-after-completed, completing '
    'unlocks the next, and locked steps are never startable',
    () {
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(3604);

      for (var i = 0; i < iterations; i++) {
        final scenario = _generateScenario(random);
        final reason = 'iteration $i, $scenario';

        final progress = StepProgress.resolve(
          pathId: kDefaultPathId,
          sections: scenario.sections,
          completedStepIds: scenario.completedStepIds,
        );

        final steps = progress.orderedSteps;

        // resolve must preserve the global authoring order.
        expect(
          steps.map((s) => s.id).toList(),
          scenario.orderedStepIds,
          reason: reason,
        );

        for (var j = 0; j < steps.length; j++) {
          final step = steps[j];
          final isCompleted =
              scenario.completedStepIds.contains(step.id);

          if (isCompleted) {
            // A completed step id always resolves to completed.
            expect(step.state, StepState.completed, reason: reason);
            continue;
          }

          // For a non-completed step, "unlocked" means first-or-predecessor-
          // completed; otherwise it is locked. This is the iff the invariant
          // asserts (Requirements 3.2, 3.3).
          final predecessorCompleted =
              j > 0 && steps[j - 1].state == StepState.completed;
          final shouldBeAvailable = j == 0 || predecessorCompleted;

          expect(
            step.state,
            shouldBeAvailable ? StepState.available : StepState.locked,
            reason: reason,
          );

          // Locked steps can never be started (Requirement 3.3); available
          // ones can. Completion-startability is covered by the branch above.
          expect(
            step.state.isStartable,
            shouldBeAvailable,
            reason: reason,
          );
        }

        // Completing a step makes the immediately next step available, unless
        // that next step is itself already completed (Requirement 3.4). Verify
        // directly by walking adjacent pairs in the resolved sequence.
        for (var j = 0; j < steps.length - 1; j++) {
          if (steps[j].state == StepState.completed) {
            final next = steps[j + 1];
            expect(
              next.state == StepState.available ||
                  next.state == StepState.completed,
              isTrue,
              reason: '$reason — step after completed s[$j] must be '
                  'available or completed, was ${next.state}',
            );
          }
        }

        // The first step (when the path is non-empty) is never locked: it is
        // always at least available (Requirement 3.2).
        if (steps.isNotEmpty) {
          expect(steps.first.state, isNot(StepState.locked), reason: reason);
          expect(steps.first.state.isStartable || steps.first.state == StepState.completed,
              isTrue, reason: reason);
        }
      }
    },
  );
}
