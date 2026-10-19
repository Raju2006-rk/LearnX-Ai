import 'package:flutter/foundation.dart';

import 'daily_goal.dart';
import 'streak.dart';

/// The learner's progress read model the Progress screen renders: the
/// current/longest [streak] (Requirement 7.1) and the [dailyGoal] tracker
/// position (Requirement 7.2).
///
/// This composes the two pieces persisted on `users/{uid}/progress/main` that
/// the Progress screen shows, so the screen reads a single value rather than
/// juggling two async sources. The weekly-summary view is a separate concern
/// (task 10.4) and is deliberately not part of this overview. It is a pure
/// value with a safe [empty] default used before any progress exists (a
/// brand-new learner or a signed-out session).
@immutable
class ProgressOverview {
  const ProgressOverview({
    this.streak = Streak.none,
    this.dailyGoal = DailyGoal.initial,
  });

  /// The safe default before any progress exists.
  static const ProgressOverview empty = ProgressOverview();

  /// Current and longest streak. (Requirement 7.1)
  final Streak streak;

  /// The daily-goal tracker position. (Requirement 7.2)
  final DailyGoal dailyGoal;

  ProgressOverview copyWith({Streak? streak, DailyGoal? dailyGoal}) =>
      ProgressOverview(
        streak: streak ?? this.streak,
        dailyGoal: dailyGoal ?? this.dailyGoal,
      );

  @override
  bool operator ==(Object other) =>
      other is ProgressOverview &&
      other.streak == streak &&
      other.dailyGoal == dailyGoal;

  @override
  int get hashCode => Object.hash(streak, dailyGoal);

  @override
  String toString() =>
      'ProgressOverview(streak: $streak, dailyGoal: $dailyGoal)';
}
