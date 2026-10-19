import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../data/progress_providers.dart';
import '../data/streak_repository.dart';
import '../domain/daily_goal.dart';
import '../domain/progress_overview.dart';

/// Drives the Progress screen: exposes the learner's current/longest streak
/// and daily-goal tracker as a single [ProgressOverview], and records a
/// qualifying activity (advancing the streak, the goal tracker, and the
/// weekly-summary source metrics). (Requirements 7.1, 7.2, 7.5)
///
/// [build] composes the two live sources persisted on `progress/main` — the
/// streak ([streakProvider]) and the daily goal ([dailyGoalProvider]) — into
/// one read model so the screen watches a single value. Both sources emit a
/// safe default (zeroed streak / Day 0 goal) for a signed-out or brand-new
/// learner, so the overview is always renderable and never errors on an empty
/// document.
///
/// [recordQualifyingActivity] is the single write seam other features call
/// when the learner completes a qualifying activity (finishing a step, a
/// lesson, or a quiz): it delegates the streak write to the pre-existing
/// transactional [StreakRepository.recordQualifyingActivity] (task 10.1) and
/// the goal-tracker advance plus the `dailyActivity` metric increments — which
/// the scheduled weekly-summary function later aggregates — to
/// [StreakRepository.recordGoalAndActivity]. The persisted writes flow back
/// into the watched streams, so the on-screen streak and tracker update
/// without a manual refresh. (Requirement 7.5)
class ProgressController extends AsyncNotifier<ProgressOverview> {
  StreakRepository get _repository => ref.read(streakRepositoryProvider);

  String? get _uid => ref.read(authStateProvider).uid;

  @override
  Future<ProgressOverview> build() async {
    // Compose the two persisted sources. Watching both AsyncValues rebuilds
    // the overview whenever either stream emits (e.g. after a recorded
    // activity writes back), and surfaces a loading overview until the first
    // snapshots arrive. Each source already falls back to a safe default for
    // the signed-out / brand-new case, so there is no null handling here.
    final streak = await ref.watch(streakProvider.future);
    final goal = await ref.watch(dailyGoalProvider.future);
    return ProgressOverview(streak: streak, dailyGoal: goal);
  }

  /// Records a qualifying activity for the signed-in learner on calendar day
  /// [date] (`"YYYY-MM-DD"`; defaults to today in UTC so callers usually omit
  /// it), advancing the streak, the daily-goal tracker, and today's
  /// `dailyActivity` metrics the weekly summary aggregates. (Requirement 7.5)
  ///
  /// The streak and the goal/metrics are written through their own
  /// transactional repository methods; this method only orders and awaits
  /// them. It is a no-op when no learner is signed in. The persisted writes
  /// flow back through the watched streams and refresh [build], so the screen
  /// reflects the new streak and tracker position automatically — this method
  /// does not mutate [state] itself.
  Future<void> recordQualifyingActivity({
    String? date,
    ActivityMetrics metrics = ActivityMetrics.none,
  }) async {
    final uid = _uid;
    if (uid == null) return;
    final day = date ?? _todayUtc();
    // Order matters: both the goal and the streak decide "same day vs new day"
    // by reading the stored lastActivityDate, and the streak write *advances*
    // lastActivityDate to today. The goal/activity write must therefore run
    // first so it sees the pre-activity lastActivityDate; otherwise the streak
    // would move lastActivityDate to today and the goal would always read it
    // back as a same-day no-op and never advance. Both are same-day-idempotent
    // on the day position, so a repeated activity still ticks the day's
    // activity counters without double-advancing the streak or goal.
    await _repository.recordGoalAndActivity(uid, day, metrics: metrics);
    await _repository.recordQualifyingActivity(uid, day);
  }

  /// Today's calendar day as a `"YYYY-MM-DD"` string in UTC, matching the
  /// format the streak/goal rules and the `dailyActivity/{yyyy-mm-dd}` doc ids
  /// use so comparisons are timezone-independent.
  static String _todayUtc() {
    final now = DateTime.now().toUtc();
    final mm = now.month < 10 ? '0${now.month}' : '${now.month}';
    final dd = now.day < 10 ? '0${now.day}' : '${now.day}';
    return '${now.year}-$mm-$dd';
  }
}

/// The signed-in learner's daily-goal tracker position, streamed from their
/// persisted `progress/main` document.
///
/// Emits [DailyGoal.initial] (Day 0) when no learner is signed in so consumers
/// always have a safe, non-null value to render. (Requirement 7.2)
final dailyGoalProvider = StreamProvider<DailyGoal>((ref) {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return Stream<DailyGoal>.value(DailyGoal.initial);
  return ref.watch(streakRepositoryProvider).watchDailyGoal(uid);
}, name: 'dailyGoalProvider');

/// Exposes the [ProgressController] and its asynchronous [ProgressOverview] to
/// the Progress UI. (Requirements 7.1, 7.2, 7.5)
final progressControllerProvider =
    AsyncNotifierProvider<ProgressController, ProgressOverview>(
      ProgressController.new,
      name: 'progressControllerProvider',
    );
