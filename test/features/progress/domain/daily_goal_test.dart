// Unit tests for the DailyGoal value and the pure DailyGoalRule advancement:
// the tracker advances once per new calendar day, is a same-day no-op, never
// resets on a gap, and defensively clamps malformed stored values.
// (Requirements 7.2, 7.5)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/progress/domain/daily_goal.dart';
import 'package:learnx/shared/models/dtos/progress_dto.dart';

void main() {
  group('DailyGoal', () {
    test('initial is Day 0 with the default target', () {
      expect(DailyGoal.initial.day, 0);
      expect(DailyGoal.initial.targetPerDay, DailyGoal.defaultTargetPerDay);
      expect(DailyGoal.initial.hasStarted, isFalse);
    });

    test('hasStarted is true once the learner reaches Day 1', () {
      expect(const DailyGoal(day: 1).hasStarted, isTrue);
    });

    test('fromDto floors a negative day and lifts a bad target to one', () {
      final goal = DailyGoal.fromDto(
        const DailyGoalDto(day: -5, targetPerDay: 0),
      );
      expect(goal.day, 0);
      expect(goal.targetPerDay, DailyGoal.defaultTargetPerDay);
    });

    test('fromDto preserves a valid stored goal', () {
      final goal = DailyGoal.fromDto(
        const DailyGoalDto(day: 7, targetPerDay: 3),
      );
      expect(goal.day, 7);
      expect(goal.targetPerDay, 3);
    });

    test('toDto round-trips the fields', () {
      const goal = DailyGoal(day: 4, targetPerDay: 2);
      final dto = goal.toDto();
      expect(dto.day, 4);
      expect(dto.targetPerDay, 2);
    });

    test('equality is by value', () {
      expect(const DailyGoal(day: 3), const DailyGoal(day: 3));
      expect(
        const DailyGoal(day: 3),
        isNot(const DailyGoal(day: 4)),
      );
    });
  });

  group('DailyGoalRule.onQualifyingActivity', () {
    test('first-ever activity advances Day 0 to Day 1', () {
      final next = DailyGoalRule.onQualifyingActivity(
        DailyGoal.initial,
        null,
        '2024-03-10',
      );
      expect(next.day, 1);
      expect(next.targetPerDay, DailyGoal.initial.targetPerDay);
    });

    test('a new calendar day advances the day by one', () {
      final next = DailyGoalRule.onQualifyingActivity(
        const DailyGoal(day: 4, targetPerDay: 2),
        '2024-03-10',
        '2024-03-11',
      );
      expect(next.day, 5);
      expect(next.targetPerDay, 2);
    });

    test('same-day activity is a no-op', () {
      const goal = DailyGoal(day: 4, targetPerDay: 2);
      final next = DailyGoalRule.onQualifyingActivity(
        goal,
        '2024-03-10',
        '2024-03-10',
      );
      expect(next, goal);
    });

    test('a multi-day gap still only advances by one (never resets)', () {
      final next = DailyGoalRule.onQualifyingActivity(
        const DailyGoal(day: 9),
        '2024-03-10',
        '2024-03-25',
      );
      expect(next.day, 10);
    });

    test('keeps counting beyond Day 15', () {
      final next = DailyGoalRule.onQualifyingActivity(
        const DailyGoal(day: DailyGoal.trackerSpanDays),
        '2024-03-10',
        '2024-03-11',
      );
      expect(next.day, DailyGoal.trackerSpanDays + 1);
    });
  });
}
