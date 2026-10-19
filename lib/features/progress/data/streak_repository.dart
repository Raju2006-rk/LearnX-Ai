import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../core/firebase/firestore_paths.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/daily_goal.dart';
import '../domain/streak.dart';

/// The metrics a single qualifying activity contributes to the learner's
/// daily-activity roll-up, which the weekly summary aggregates. (Requirement
/// 7.5)
///
/// Each field is an increment applied to today's `dailyActivity/{date}`
/// document: [timeSpentSec] of learning time, [wordsLearned] new words, and
/// [mistakesFixed] grammar mistakes corrected. `activities` is always
/// incremented by one per recorded activity. All values are non-negative.
@immutable
class ActivityMetrics {
  const ActivityMetrics({
    this.timeSpentSec = 0,
    this.wordsLearned = 0,
    this.mistakesFixed = 0,
  }) : assert(timeSpentSec >= 0, 'timeSpentSec cannot be negative'),
       assert(wordsLearned >= 0, 'wordsLearned cannot be negative'),
       assert(mistakesFixed >= 0, 'mistakesFixed cannot be negative');

  /// A zero-metric activity: counts as one activity but contributes nothing to
  /// the weekly totals (used when a caller only needs to tick the streak/goal).
  static const ActivityMetrics none = ActivityMetrics();

  /// Seconds of learning time this activity contributed.
  final int timeSpentSec;

  /// New words learned in this activity.
  final int wordsLearned;

  /// Grammar mistakes corrected in this activity.
  final int mistakesFixed;

  @override
  bool operator ==(Object other) =>
      other is ActivityMetrics &&
      other.timeSpentSec == timeSpentSec &&
      other.wordsLearned == wordsLearned &&
      other.mistakesFixed == mistakesFixed;

  @override
  int get hashCode => Object.hash(timeSpentSec, wordsLearned, mistakesFixed);
}

/// Reads and updates the learner's persisted [Streak] on
/// `users/{uid}/progress/main`.
///
/// [watchStreak] exposes the already-computed streak so the home screen (task
/// 6.8) can render the streak flame indicator. [recordQualifyingActivity]
/// applies the transactional streak update on a qualifying activity (same-day
/// no-op, consecutive-day increment, gap reset, with `longestStreak =
/// max(longest, current)`), reconciling against server state via a Firestore
/// transaction so offline replays and concurrent devices stay consistent. The
/// arithmetic itself lives in the pure [StreakComputation] rule. (Requirements
/// 3.7, 7.1, 7.5)
class StreakRepository {
  StreakRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Streams the learner's current/longest streak from their progress
  /// document, emitting [Streak.none] while the document does not exist yet
  /// (a brand-new learner, or before the first qualifying activity).
  ///
  /// Reads are defensively clamped so a malformed or inconsistent stored
  /// document (e.g. a longest streak below the current one) can never produce
  /// an invalid [Streak]: counts are floored at zero and `longest` is lifted
  /// to at least `current`.
  Stream<Streak> watchStreak(String uid) {
    return _firestore
        .doc(FirestorePaths.progressDoc(uid))
        .snapshots()
        .map(_streakFromSnapshot);
  }

  /// Records a qualifying activity on calendar day [date] (a `"YYYY-MM-DD"`
  /// string) for the learner [uid], updating their persisted streak.
  ///
  /// Runs the update inside a Firestore **transaction** (read-modify-write) so
  /// a replayed offline write or a concurrent device reconciles against the
  /// server state rather than blindly overwriting it: it reads the current
  /// `progress/main` streak fields, applies the pure
  /// [StreakComputation.onQualifyingActivity] rule (same-day no-op,
  /// consecutive-day increment, gap reset, `longestStreak = max(longest,
  /// current)`), and writes the result back. (Requirements 3.7, 7.1, 7.5)
  ///
  /// Only the three streak fields (`currentStreak`, `longestStreak`,
  /// `lastActivityDate`) are written — via `update` when the document already
  /// exists so sibling fields on `progress/main` (`dailyGoal`, `badges`) are
  /// left intact, or `set` to create the document on the first activity. On a
  /// same-day no-op the document is left untouched. Returns the resulting
  /// [Streak].
  Future<Streak> recordQualifyingActivity(String uid, String date) {
    final ref = _firestore.doc(FirestorePaths.progressDoc(uid));
    return _firestore.runTransaction<Streak>((transaction) async {
      final snapshot = await transaction.get(ref);
      final current = _stateFromSnapshot(snapshot);
      final next = StreakComputation.onQualifyingActivity(current, date);

      // Same-day activity: the rule is a no-op, so skip the write entirely.
      if (next == current) return next.streak;

      final fields = <String, dynamic>{
        'currentStreak': next.current,
        'longestStreak': next.longest,
        'lastActivityDate': next.lastActivityDate,
        // Stamp updatedAt for last-write-wins sync so a replayed offline write
        // or a concurrent device resolves against the server clock. (Req 8.2)
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (snapshot.exists) {
        // Update only the streak fields so sibling fields on progress/main
        // (dailyGoal, badges) are left intact.
        transaction.update(ref, fields);
      } else {
        // The document does not exist yet: create it with the streak fields.
        transaction.set(ref, fields);
      }
      return next.streak;
    });
  }

  /// Streams the learner's daily-goal tracker position from their progress
  /// document, emitting [DailyGoal.initial] while the document does not exist
  /// yet (a brand-new learner, or before the first qualifying activity).
  ///
  /// Reads are defensively clamped (via [DailyGoal.fromDto]) so a malformed
  /// stored value can never surface an invalid goal. (Requirement 7.2)
  Stream<DailyGoal> watchDailyGoal(String uid) {
    return _firestore
        .doc(FirestorePaths.progressDoc(uid))
        .snapshots()
        .map(_dailyGoalFromSnapshot);
  }

  /// Records a qualifying activity on calendar day [date] (a `"YYYY-MM-DD"`
  /// string) for the learner [uid], advancing the daily-goal tracker and
  /// rolling the activity's [metrics] into today's `dailyActivity/{date}`
  /// document. (Requirements 7.2, 7.5)
  ///
  /// The streak itself is advanced separately via [recordQualifyingActivity];
  /// this method handles the goal tracker and the weekly-summary source
  /// metrics so the two concerns stay independently testable and callers can
  /// compose them (the controller calls both on one activity).
  ///
  /// The goal-tracker advance runs inside a Firestore **transaction** on
  /// `progress/main`: it reads the stored `dailyGoal` and the recorded
  /// `lastActivityDate`, applies the pure [DailyGoalRule.onQualifyingActivity]
  /// rule (advance once per new calendar day, same-day no-op), and writes only
  /// the `dailyGoal` field back so sibling fields (streak, badges) are left
  /// intact. The `dailyActivity/{date}` counters are incremented atomically
  /// with [FieldValue.increment] — which always applies, including on a
  /// same-day repeat, because every qualifying activity counts toward the
  /// day's totals even when the goal day does not advance. Returns the
  /// resulting [DailyGoal].
  Future<DailyGoal> recordGoalAndActivity(
    String uid,
    String date, {
    ActivityMetrics metrics = ActivityMetrics.none,
  }) {
    final progressRef = _firestore.doc(FirestorePaths.progressDoc(uid));
    final activityRef = _firestore.doc(
      FirestorePaths.dailyActivityDoc(uid, date),
    );
    return _firestore.runTransaction<DailyGoal>((transaction) async {
      // Firestore requires every read in a transaction to precede every write,
      // so read both documents up front.
      final snapshot = await transaction.get(progressRef);
      final activitySnapshot = await transaction.get(activityRef);

      final dto = snapshot.exists
          ? ProgressDto.fromMap(snapshot.data() ?? const <String, dynamic>{})
          : const ProgressDto();
      final goal = DailyGoal.fromDto(dto.dailyGoal);
      final nextGoal = DailyGoalRule.onQualifyingActivity(
        goal,
        dto.lastActivityDate,
        date,
      );

      // Advance the goal day only when it actually changes, writing just the
      // dailyGoal field so streak/badges on progress/main are left intact.
      if (nextGoal != goal) {
        final goalFields = <String, dynamic>{
          'dailyGoal': nextGoal.toDto().toMap(),
          // Carry updatedAt for last-write-wins sync. (Req 8.2)
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (snapshot.exists) {
          transaction.update(progressRef, goalFields);
        } else {
          transaction.set(progressRef, goalFields, SetOptions(merge: true));
        }
      }

      // Every qualifying activity ticks today's activity counters, which the
      // scheduled weekly-summary function aggregates. Use a transactional
      // read-modify-write (rather than FieldValue.increment) so a replayed
      // offline write or a concurrent device accumulates against the value
      // read in this transaction, and the per-day document is created on the
      // first activity. (Requirements 7.5, 8.2)
      final prior = activitySnapshot.exists
          ? DailyActivityDto.fromMap(
              activitySnapshot.data() ?? const <String, dynamic>{},
            )
          : const DailyActivityDto();
      final nextActivity = DailyActivityDto(
        activities: prior.activities + 1,
        timeSpentSec: prior.timeSpentSec + metrics.timeSpentSec,
        wordsLearned: prior.wordsLearned + metrics.wordsLearned,
        mistakesFixed: prior.mistakesFixed + metrics.mistakesFixed,
      );
      transaction.set(activityRef, <String, dynamic>{
        ...nextActivity.toMap(),
        // Carry updatedAt for last-write-wins sync. (Req 8.2)
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      return nextGoal;
    });
  }

  Streak _streakFromSnapshot(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    return _stateFromSnapshot(snapshot).streak;
  }

  DailyGoal _dailyGoalFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return DailyGoal.initial;
    final dto = ProgressDto.fromMap(
      snapshot.data() ?? const <String, dynamic>{},
    );
    return DailyGoal.fromDto(dto.dailyGoal);
  }

  /// Reads the stored streak fields into a defensively-clamped [StreakState]:
  /// counts are floored at zero and `longest` is lifted to at least `current`,
  /// so an inconsistent stored document can never produce an invalid state
  /// (mirrors the clamping [watchStreak] applies to its read model).
  StreakState _stateFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return StreakState.initial;
    final dto = ProgressDto.fromMap(
      snapshot.data() ?? const <String, dynamic>{},
    );
    final current = dto.currentStreak < 0 ? 0 : dto.currentStreak;
    final longest = dto.longestStreak < current ? current : dto.longestStreak;
    return StreakState(
      current: current,
      longest: longest,
      lastActivityDate: dto.lastActivityDate,
    );
  }
}
