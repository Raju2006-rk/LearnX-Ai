import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/config/remote_config.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/streak.dart';
import '../domain/weekly_summary.dart';
import 'badge_repository.dart';
import 'streak_repository.dart';
import 'weekly_summary_repository.dart';

/// Riverpod provider wiring the [StreakRepository] to the shared Firestore
/// client. Tests override [firebaseFirestoreProvider] (or this provider
/// directly) with a fake.
final streakRepositoryProvider = Provider<StreakRepository>(
  (ref) => StreakRepository(firestore: ref.watch(firebaseFirestoreProvider)),
  name: 'streakRepositoryProvider',
);

/// The signed-in learner's current [Streak], streamed from their persisted
/// `progress/main` document.
///
/// Emits [Streak.none] when no learner is signed in, so consumers (such as the
/// home learning-path screen's streak flame indicator) always have a safe,
/// non-null value to render without special-casing the signed-out state.
/// The streak flame reads *this* provider; the Progress feature (tasks 9/10)
/// writes the underlying document on each qualifying activity, which flows
/// back here automatically. (Requirement 3.7)
final streakProvider = StreamProvider<Streak>((ref) {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return Stream<Streak>.value(Streak.none);
  return ref.watch(streakRepositoryProvider).watchStreak(uid);
}, name: 'streakProvider');

/// Riverpod provider wiring the [WeeklySummaryRepository] to the shared
/// Firestore client. Tests override [firebaseFirestoreProvider] (or this
/// provider directly) with a fake.
final weeklySummaryRepositoryProvider = Provider<WeeklySummaryRepository>(
  (ref) =>
      WeeklySummaryRepository(firestore: ref.watch(firebaseFirestoreProvider)),
  name: 'weeklySummaryRepositoryProvider',
);

/// The signed-in learner's current-week [WeeklySummary], streamed from their
/// persisted `weeklySummaries/{isoWeek}` document with a live current-week
/// fallback aggregated from `dailyActivity`.
///
/// Emits [WeeklySummary.empty] when no learner is signed in so the weekly
/// summary view (task 10.4) always has a safe, non-null value to render
/// without special-casing the signed-out state. (Requirement 7.4)
final currentWeekSummaryProvider = StreamProvider<WeeklySummary>((ref) {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return Stream<WeeklySummary>.value(WeeklySummary.empty);
  return ref.watch(weeklySummaryRepositoryProvider).watchCurrentWeek(uid);
}, name: 'currentWeekSummaryProvider');

/// Riverpod provider wiring the [BadgeRepository] to the shared Firestore
/// client and the [RemoteConfigService] that supplies milestone thresholds.
/// Tests override [firebaseFirestoreProvider] / [remoteConfigServiceProvider]
/// (or this provider directly) with fakes. (Requirement 7.3)
final badgeRepositoryProvider = Provider<BadgeRepository>(
  (ref) => BadgeRepository.fromRemoteConfig(
    firestore: ref.watch(firebaseFirestoreProvider),
    remoteConfig: ref.watch(remoteConfigServiceProvider),
  ),
  name: 'badgeRepositoryProvider',
);
