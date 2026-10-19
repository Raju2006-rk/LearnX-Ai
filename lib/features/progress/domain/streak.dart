import 'package:flutter/foundation.dart';

/// The learner's streak: the count of consecutive calendar days on which they
/// completed at least one qualifying activity, alongside the longest such run
/// they have ever achieved. (Requirements 3.7, 7.1, 7.5)
///
/// The full transactional streak computation (same-day no-op, consecutive-day
/// increment, gap reset, with `longestStreak = max(longest, current)`) lives
/// in the Progress feature (tasks 9/10). This type is the read model the home
/// learning-path screen uses to render the streak flame indicator: it carries
/// the already-computed [current] and [longest] counts persisted on
/// `users/{uid}/progress/main`.
@immutable
class Streak {
  const Streak({required this.current, required this.longest})
    : assert(current >= 0, 'current streak cannot be negative'),
      assert(longest >= 0, 'longest streak cannot be negative'),
      assert(longest >= current, 'longest streak must dominate current streak');

  /// A zeroed streak: no current run and no history. Used as the safe default
  /// before any progress exists (a brand-new learner, a signed-out session,
  /// or while the first snapshot is still loading).
  static const Streak none = Streak(current: 0, longest: 0);

  /// The length of the current consecutive-day run of qualifying activity.
  final int current;

  /// The longest consecutive-day run ever achieved; always `>= current`.
  final int longest;

  /// Whether the learner has an active streak worth celebrating — i.e. the
  /// flame is "lit" because at least one day is in the current run.
  bool get isActive => current > 0;

  @override
  bool operator ==(Object other) =>
      other is Streak && other.current == current && other.longest == longest;

  @override
  int get hashCode => Object.hash(current, longest);

  @override
  String toString() => 'Streak(current: $current, longest: $longest)';
}

/// The persisted streak state carried on `users/{uid}/progress/main`: the
/// current/longest counts plus the `"YYYY-MM-DD"` date of the last qualifying
/// activity, which the streak rule needs to decide same-day / consecutive /
/// gap transitions.
///
/// This is the read-modify-write unit the transactional update operates on.
/// It is a plain value so [StreakComputation.onQualifyingActivity] stays pure
/// and the repository can map it to/from the stored document fields without
/// pulling Firestore into the rule.
@immutable
class StreakState {
  const StreakState({
    required this.current,
    required this.longest,
    this.lastActivityDate,
  }) : assert(current >= 0, 'current streak cannot be negative'),
       assert(longest >= current, 'longest streak must dominate current');

  /// The zeroed starting state for a learner with no recorded activity.
  static const StreakState initial = StreakState(current: 0, longest: 0);

  /// Length of the current consecutive-day run.
  final int current;

  /// Longest consecutive-day run ever achieved; always `>= current`.
  final int longest;

  /// The `"YYYY-MM-DD"` date of the last qualifying activity, or `null` when
  /// the learner has never completed one.
  final String? lastActivityDate;

  /// The read-model view of this state (current/longest only).
  Streak get streak => Streak(current: current, longest: longest);

  @override
  bool operator ==(Object other) =>
      other is StreakState &&
      other.current == current &&
      other.longest == longest &&
      other.lastActivityDate == lastActivityDate;

  @override
  int get hashCode => Object.hash(current, longest, lastActivityDate);

  @override
  String toString() =>
      'StreakState(current: $current, longest: $longest, '
      'lastActivityDate: $lastActivityDate)';
}

/// The pure streak rule, with no I/O so the same-day / consecutive-day / gap
/// transitions are trivially testable. Mirrors the design's `onQualifyingActivity`
/// pseudocode. (Requirements 3.7, 7.1, 7.5)
///
/// ```
/// onQualifyingActivity(date):
///   if lastActivityDate == date:        no-op (already counted today)
///   elif lastActivityDate == date - 1:  currentStreak += 1
///   else:                               currentStreak = 1   # gap resets
///   longestStreak = max(longestStreak, currentStreak)
///   lastActivityDate = date
/// ```
///
/// The transactional read-modify-write in [StreakRepository] reads the current
/// [StreakState], runs this rule, and writes the result back; this keeps the
/// arithmetic independent of Firestore.
abstract final class StreakComputation {
  const StreakComputation._();

  /// Applies a qualifying activity on calendar day [date] (a `"YYYY-MM-DD"`
  /// string) to [state], returning the next [StreakState].
  ///
  /// - If [date] equals the stored `lastActivityDate`, the activity is already
  ///   counted today and the state is returned unchanged (same-day no-op).
  /// - If [date] is the calendar day immediately after `lastActivityDate`, the
  ///   current streak increments by one (consecutive day).
  /// - Otherwise — a gap of more than one day, or no prior activity — the
  ///   current streak resets to one.
  ///
  /// In the incrementing and resetting cases the longest streak is lifted to
  /// `max(longest, current)` and `lastActivityDate` advances to [date], so the
  /// invariant `longest >= current` always holds.
  static StreakState onQualifyingActivity(StreakState state, String date) {
    if (state.lastActivityDate == date) {
      // Already counted a qualifying activity today: nothing changes.
      return state;
    }

    final int nextCurrent;
    if (state.lastActivityDate != null &&
        _isDayBefore(state.lastActivityDate!, date)) {
      nextCurrent = state.current + 1;
    } else {
      nextCurrent = 1;
    }

    final nextLongest = state.longest >= nextCurrent
        ? state.longest
        : nextCurrent;

    return StreakState(
      current: nextCurrent,
      longest: nextLongest,
      lastActivityDate: date,
    );
  }

  /// Whether [earlier] is the calendar day immediately before [later], where
  /// both are `"YYYY-MM-DD"` strings. Returns `false` when either string is
  /// not a valid date so a malformed stored value degrades to a gap reset
  /// rather than throwing.
  static bool _isDayBefore(String earlier, String later) {
    final earlierDate = DateTime.tryParse(earlier);
    final laterDate = DateTime.tryParse(later);
    if (earlierDate == null || laterDate == null) return false;
    final earlierDay = DateTime.utc(
      earlierDate.year,
      earlierDate.month,
      earlierDate.day,
    );
    final laterDay = DateTime.utc(
      laterDate.year,
      laterDate.month,
      laterDate.day,
    );
    return laterDay.difference(earlierDay).inDays == 1;
  }
}
