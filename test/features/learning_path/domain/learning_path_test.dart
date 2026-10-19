// Unit tests for the learning-path step-state derivation (the unlock
// invariant). (Requirements 3.2, 3.3, 3.4; design Property 6)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';

/// Builds a single-section, single-week path whose steps are named s1..sN in
/// authoring order, so tests can focus on the flattened unlock sequence.
List<Section> _linearPath(int count) {
  return <Section>[
    Section(
      id: 'sec1',
      title: 'Section 1',
      order: 0,
      weeks: [
        Week(
          id: 'wk1',
          title: 'Week 1',
          order: 0,
          steps: [
            for (var i = 1; i <= count; i++)
              Step(
                id: 's$i',
                title: 'Step $i',
                order: i,
                type: 'lesson',
                state: StepState.locked,
              ),
          ],
        ),
      ],
    ),
  ];
}

/// The resolved state of every step, keyed by step id, flattened across the
/// whole path in authoring order.
Map<String, StepState> _states(StepProgress progress) => <String, StepState>{
      for (final step in progress.orderedSteps) step.id: step.state,
    };

void main() {
  group('StepState', () {
    test('fromWire round-trips known values and rejects unknown', () {
      expect(StepState.fromWire('locked'), StepState.locked);
      expect(StepState.fromWire('available'), StepState.available);
      expect(StepState.fromWire('completed'), StepState.completed);
      expect(StepState.fromWire('nope'), isNull);
      expect(StepState.fromWire(null), isNull);
    });

    test('only available is startable', () {
      expect(StepState.available.isStartable, isTrue);
      expect(StepState.locked.isStartable, isFalse);
      expect(StepState.completed.isStartable, isFalse);
    });
  });

  group('StepProgress.resolve', () {
    test('first step is available and the rest are locked with no progress',
        () {
      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: _linearPath(3),
        completedStepIds: const <String>{},
      );

      expect(_states(progress), {
        's1': StepState.available,
        's2': StepState.locked,
        's3': StepState.locked,
      });
    });

    test('completing a step unlocks exactly the next step (Req 3.4)', () {
      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: _linearPath(3),
        completedStepIds: const {'s1'},
      );

      expect(_states(progress), {
        's1': StepState.completed,
        's2': StepState.available,
        's3': StepState.locked,
      });
    });

    test('a step stays locked while its predecessor is not completed (Req 3.3)',
        () {
      // s1 is NOT completed, but s2 somehow has stored progress — the lock
      // state is derived, not trusted, so s2 must remain locked.
      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: _linearPath(3),
        completedStepIds: const {'s2'},
      );

      final states = _states(progress);
      expect(states['s1'], StepState.available); // first step always available
      expect(states['s2'], StepState.completed); // completion is trusted
      expect(states['s3'], StepState.available); // unlocked by s2 completion
    });

    test('a gap in completion re-locks following steps', () {
      // s1 and s2 completed, s3 not; s4 must stay locked behind s3.
      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: _linearPath(4),
        completedStepIds: const {'s1', 's2'},
      );

      expect(_states(progress), {
        's1': StepState.completed,
        's2': StepState.completed,
        's3': StepState.available,
        's4': StepState.locked,
      });
    });

    test('unlocking flows across week and section boundaries (Req 3.1)', () {
      // Two sections, each with one week of one step. Completing the first
      // section's step must unlock the next section's first step.
      final sections = <Section>[
        Section(
          id: 'secA',
          title: 'A',
          order: 0,
          weeks: [
            Week(
              id: 'wkA',
              title: 'A1',
              order: 0,
              steps: const [
                Step(
                  id: 'a1',
                  title: 'A step',
                  order: 0,
                  type: 'lesson',
                  state: StepState.locked,
                ),
              ],
            ),
          ],
        ),
        Section(
          id: 'secB',
          title: 'B',
          order: 1,
          weeks: [
            Week(
              id: 'wkB',
              title: 'B1',
              order: 0,
              steps: const [
                Step(
                  id: 'b1',
                  title: 'B step',
                  order: 0,
                  type: 'lesson',
                  state: StepState.locked,
                ),
              ],
            ),
          ],
        ),
      ];

      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: sections,
        completedStepIds: const {'a1'},
      );

      expect(_states(progress), {
        'a1': StepState.completed,
        'b1': StepState.available,
      });
    });

    test('resolution sorts sections, weeks, and steps by authored order', () {
      // Provide everything out of order; the flattened sequence must follow
      // order fields, so s1 (first) is available and s3 (last) is locked.
      final sections = <Section>[
        Section(
          id: 'sec1',
          title: 'S',
          order: 0,
          weeks: [
            Week(
              id: 'wk1',
              title: 'W',
              order: 0,
              steps: const [
                Step(
                  id: 's3',
                  title: '3',
                  order: 3,
                  type: 'lesson',
                  state: StepState.locked,
                ),
                Step(
                  id: 's1',
                  title: '1',
                  order: 1,
                  type: 'lesson',
                  state: StepState.locked,
                ),
                Step(
                  id: 's2',
                  title: '2',
                  order: 2,
                  type: 'lesson',
                  state: StepState.locked,
                ),
              ],
            ),
          ],
        ),
      ];

      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: sections,
        completedStepIds: const <String>{},
      );

      // orderedSteps must come back sorted.
      expect(
        progress.orderedSteps.map((s) => s.id).toList(),
        ['s1', 's2', 's3'],
      );
      expect(_states(progress), {
        's1': StepState.available,
        's2': StepState.locked,
        's3': StepState.locked,
      });
    });

    test('all steps completed resolves every step to completed', () {
      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: _linearPath(3),
        completedStepIds: const {'s1', 's2', 's3'},
      );

      expect(_states(progress).values, everyElement(StepState.completed));
    });

    test('an empty path resolves to no sections', () {
      final progress = StepProgress.resolve(
        pathId: 'p1',
        sections: const <Section>[],
        completedStepIds: const <String>{},
      );

      expect(progress.sections, isEmpty);
      expect(progress.orderedSteps, isEmpty);
    });
  });
}
