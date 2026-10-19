import 'package:flutter/foundation.dart';

import '../../../shared/models/dtos/dtos.dart';

/// The learner's daily-goal tracker position, mirroring the `dailyGoal` block
/// on `users/{uid}/progress/main`: `{ day, targetPerDay }`. (Requirement 7.2)
///
/// [day] is the learner's position on the goal calendar — Day 1 on the first
/// day they complete a qualifying activity, advancing by one each new calendar
/// day they return. The tracker spans Day 1 through Day 15 and keeps counting
/// beyond Day 15 (the design calls for a Day 1–15-and-beyond tracker), so [day]
/// is never capped. [targetPerDay] is the number of qualifying activities that
/// count as "goal met" for a day; it defaults to one so a brand-new learner has
/// a sensible goal before any configuration lands.
///
/// This is a pure value: the advancement rule lives in [DailyGoalRule] so it
/// stays independent of Firestore, mirroring how [StreakComputation] is split
/// out from the repository.
@immutable
class DailyGoal {
  const DailyGoal({this.day = 0, this.targetPerDay = defaultTargetPerDay})
    : assert(day >= 0, 'day cannot be negative'),
      assert(targetPerDay >= 1, 'targetPerDay must be at least one');

  /// The default per-day activity target before any configuration overrides it.
  static const int defaultTargetPerDay = 1;

  /// The first milestone day the tracker always renders through. The tracker
  /// shows Day 1 through this day explicitly and then continues beyond it.
  static const int trackerSpanDays = 15;

  /// The starting goal for a learner with no recorded activity: Day 0 (not yet
  /// started) with the default target.
  static const DailyGoal initial = DailyGoal();

  /// Builds a [DailyGoal] from its DTO, flooring [day] at zero and lifting
  /// [targetPerDay] to at least one so a malformed stored value can never
  /// produce an invalid goal.
  factory DailyGoal.fromDto(DailyGoalDto dto) => DailyGoal(
    day: dto.day < 0 ? 0 : dto.day,
    targetPerDay: dto.targetPerDay < 1 ? defaultTargetPerDay : dto.targetPerDay,
  );

  /// The learner's current day on the goal calendar (0 before they start).
  final int day;

  /// The number of qualifying activities that count as the goal for one day.
  final int targetPerDay;

  /// Whether the learner has started the tracker (completed at least one day).
  bool get hasStarted => day > 0;

  /// Serializes this goal back to its DTO for persistence.
  DailyGoalDto toDto() => DailyGoalDto(day: day, targetPerDay: targetPerDay);

  DailyGoal copyWith({int? day, int? targetPerDay}) => DailyGoal(
    day: day ?? this.day,
    targetPerDay: targetPerDay ?? this.targetPerDay,
  );

  @override
  bool operator ==(Object other) =>
      other is DailyGoal &&
      other.day == day &&
      other.targetPerDay == targetPerDay;

  @override
  int get hashCode => Object.hash(day, targetPerDay);

  @override
  String toString() => 'DailyGoal(day: $day, targetPerDay: $targetPerDay)';
}

/// The pure daily-goal advancement rule, with no I/O so the same-day /
/// new-day transitions are trivially testable. (Requirements 7.2, 7.5)
///
/// The tracker advances in lockstep with the streak's calendar-day logic: the
/// first qualifying activity on a brand-new calendar day moves the learner to
/// the next day on the tracker; further activities on the same day leave the
/// day position unchanged (the day is already counted). Unlike the streak the
/// goal day never resets on a gap — it is a lifetime count of active days, so
/// it only ever advances or holds.
abstract final class DailyGoalRule {
  const DailyGoalRule._();

  /// Advances [goal] for a qualifying activity on calendar day [date], given
  /// the [lastActivityDate] recorded before this activity (both `"YYYY-MM-DD"`
  /// strings, [lastActivityDate] `null` when the learner has never been
  /// active).
  ///
  /// - When [date] equals [lastActivityDate] the day is already counted today,
  ///   so the goal is returned unchanged (same-day no-op).
  /// - Otherwise this is the first qualifying activity of a new calendar day,
  ///   so the goal day advances by one (Day 0 → Day 1 on the very first day).
  ///
  /// [targetPerDay] is preserved across the advance.
  static DailyGoal onQualifyingActivity(
    DailyGoal goal,
    String? lastActivityDate,
    String date,
  ) {
    if (lastActivityDate == date) return goal;
    return goal.copyWith(day: goal.day + 1);
  }
}
