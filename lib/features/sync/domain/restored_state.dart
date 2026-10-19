import 'package:flutter/foundation.dart';

import '../../onboarding/domain/learner_profile.dart';
import '../../progress/domain/streak.dart';

/// The learner's account-and-progress state rehydrated from `users/{uid}/**`
/// in a single read when they sign in on a new device. (Requirement 8.3)
///
/// Cross-device restore is otherwise served reactively: the router's
/// `onboardedProvider`/`consentProvider` seams and the `streakProvider`,
/// `currentWeekSummaryProvider`, and learning-path reads each watch their own
/// `users/{uid}/**` document and so already reflect a returning learner's
/// state the moment the first snapshot arrives. This type is the *one-shot*
/// counterpart: when a learner first signs in on a new device, the app reads
/// the whole user tree up front and surfaces a single, consistent snapshot —
/// so features that need the restored values immediately (not via a stream)
/// have them without stitching several reads together.
///
/// Every field has a safe default so a brand-new learner — or a learner whose
/// documents do not exist yet — restores to an empty-but-valid state rather
/// than null: [profile] falls back to [LearnerProfile.none], [streak] to
/// [Streak.none], and [completedStepIds] to the empty set.
@immutable
class RestoredState {
  const RestoredState({
    this.accountExists = false,
    this.profile = LearnerProfile.none,
    this.streak = Streak.none,
    this.lastActivityDate,
    this.completedStepIds = const <String>{},
  });

  /// The signed-out / nothing-restored state: no account, an empty profile,
  /// a zeroed streak, and no completed steps. Used as a safe default before a
  /// restore runs or when no learner is signed in.
  static const RestoredState none = RestoredState();

  /// Whether the learner's root document `users/{uid}` existed — i.e. this is
  /// a returning account rather than a brand-new sign-in whose documents have
  /// not been written yet.
  final bool accountExists;

  /// The restored profile from `users/{uid}/profile/main` — self-selected
  /// level/goal/native language, the placement-assigned level, and the
  /// onboarded flag. [LearnerProfile.none] when no profile document exists.
  final LearnerProfile profile;

  /// The restored streak (current/longest) from `users/{uid}/progress/main`.
  /// [Streak.none] when no progress document exists. Counts are defensively
  /// clamped so a malformed stored document never yields an invalid streak.
  final Streak streak;

  /// The `"YYYY-MM-DD"` date of the last qualifying activity recorded on
  /// `progress/main`, or `null` when the learner has never completed one.
  final String? lastActivityDate;

  /// The set of step ids the learner has completed, read from their
  /// `users/{uid}/pathProgress` documents whose stored `state == "completed"`.
  /// The learning path derives each step's locked/available/completed state
  /// from this set, so restoring it rehydrates the learner's path position.
  final Set<String> completedStepIds;

  /// Whether this restore recovered any learner state worth rehydrating —
  /// a returning account, a completed onboarding, an active streak, or any
  /// completed step. `false` for a brand-new learner with nothing persisted.
  bool get hasRestoredState =>
      accountExists ||
      profile.onboarded ||
      streak.longest > 0 ||
      completedStepIds.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is RestoredState &&
      other.accountExists == accountExists &&
      other.profile == profile &&
      other.streak == streak &&
      other.lastActivityDate == lastActivityDate &&
      setEquals(other.completedStepIds, completedStepIds);

  @override
  int get hashCode => Object.hash(
        accountExists,
        profile,
        streak,
        lastActivityDate,
        Object.hashAll(completedStepIds),
      );

  @override
  String toString() =>
      'RestoredState(accountExists: $accountExists, profile: $profile, '
      'streak: $streak, lastActivityDate: $lastActivityDate, '
      'completedStepIds: $completedStepIds)';
}
