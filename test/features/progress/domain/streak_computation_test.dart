// Unit tests for the pure streak rule StreakComputation.onQualifyingActivity:
// same-day no-op, consecutive-day increment, gap reset, and the longest =
// max(longest, current) invariant. (Requirements 3.7, 7.1, 7.5)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/progress/domain/streak.dart';

void main() {
  group('StreakComputation.onQualifyingActivity', () {
    test('first-ever activity starts the current streak at 1', () {
      final next = StreakComputation.onQualifyingActivity(
        StreakState.initial,
        '2024-03-10',
      );

      expect(next.current, 1);
      expect(next.longest, 1);
      expect(next.lastActivityDate, '2024-03-10');
    });

    test('same-day activity is a no-op (state unchanged)', () {
      const state = StreakState(
        current: 4,
        longest: 9,
        lastActivityDate: '2024-03-10',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-03-10');

      expect(next, state);
    });

    test('consecutive-day activity increments the current streak', () {
      const state = StreakState(
        current: 4,
        longest: 9,
        lastActivityDate: '2024-03-10',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-03-11');

      expect(next.current, 5);
      expect(next.longest, 9);
      expect(next.lastActivityDate, '2024-03-11');
    });

    test('new current streak that exceeds longest lifts longest', () {
      const state = StreakState(
        current: 9,
        longest: 9,
        lastActivityDate: '2024-03-10',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-03-11');

      expect(next.current, 10);
      expect(next.longest, 10);
    });

    test('a multi-day gap resets the current streak to 1', () {
      const state = StreakState(
        current: 7,
        longest: 12,
        lastActivityDate: '2024-03-10',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-03-14');

      expect(next.current, 1);
      // Longest is preserved across the reset.
      expect(next.longest, 12);
      expect(next.lastActivityDate, '2024-03-14');
    });

    test('a gap reset never lowers the longest streak', () {
      const state = StreakState(
        current: 3,
        longest: 20,
        lastActivityDate: '2024-03-10',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-04-01');

      expect(next.current, 1);
      expect(next.longest, 20);
    });

    test('crossing a month boundary counts as consecutive', () {
      const state = StreakState(
        current: 2,
        longest: 2,
        lastActivityDate: '2024-01-31',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-02-01');

      expect(next.current, 3);
      expect(next.longest, 3);
    });

    test('crossing a year boundary counts as consecutive', () {
      const state = StreakState(
        current: 5,
        longest: 5,
        lastActivityDate: '2023-12-31',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-01-01');

      expect(next.current, 6);
      expect(next.longest, 6);
    });

    test('a date before the last activity is treated as a gap reset', () {
      const state = StreakState(
        current: 5,
        longest: 5,
        lastActivityDate: '2024-03-10',
      );

      final next = StreakComputation.onQualifyingActivity(state, '2024-03-09');

      expect(next.current, 1);
      expect(next.longest, 5);
      expect(next.lastActivityDate, '2024-03-09');
    });

    test('longest always dominates current across a mixed sequence', () {
      var state = StreakState.initial;
      // Three consecutive days, a gap, then two consecutive days.
      for (final date in <String>[
        '2024-05-01',
        '2024-05-02',
        '2024-05-03',
        '2024-05-07',
        '2024-05-08',
      ]) {
        state = StreakComputation.onQualifyingActivity(state, date);
        expect(state.longest >= state.current, isTrue);
      }

      expect(state.current, 2); // the final 2-day run
      expect(state.longest, 3); // the earlier 3-day run
    });
  });
}
