// Unit tests for RestoreRepository: the one-shot cross-device restore read of
// `users/{uid}/**` (user root, profile/main, progress/main, pathProgress).
// (Requirement 8.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/onboarding/domain/learner_profile.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';
import 'package:learnx/features/progress/domain/streak.dart';
import 'package:learnx/features/sync/data/restore_repository.dart';
import 'package:learnx/features/sync/domain/restored_state.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late RestoreRepository repository;

  const uid = 'user-123';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = RestoreRepository(firestore: firestore);
  });

  Future<void> seedUser() =>
      firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
        'authMethods': ['google'],
      });

  Future<void> seedProfile(Map<String, dynamic> data) =>
      firestore.doc(FirestorePaths.profileDoc(uid)).set(data);

  Future<void> seedProgress(Map<String, dynamic> data) =>
      firestore.doc(FirestorePaths.progressDoc(uid)).set(data);

  Future<void> seedStep(String stepId, String state) => firestore
      .doc(FirestorePaths.pathProgressDoc(uid, stepId))
      .set(<String, dynamic>{'state': state});

  test('restores RestoredState.none for a brand-new learner', () async {
    final result = await repository.restore(uid);

    expect(result, isA<Success<RestoredState>>());
    final state = result.valueOrNull!;
    expect(state, RestoredState.none);
    expect(state.accountExists, isFalse);
    expect(state.hasRestoredState, isFalse);
  });

  test(
    'rehydrates the full account, profile, streak, and path progress',
    () async {
      // A returning, already-onboarded learner whose state was persisted on a
      // previous device.
      await seedUser();
      await seedProfile(<String, dynamic>{
        'englishLevel': 'B1',
        'goal': 'both',
        'nativeLanguage': 'te',
        'placementLevel': 'B2',
        'onboarded': true,
      });
      await seedProgress(<String, dynamic>{
        'currentStreak': 4,
        'longestStreak': 9,
        'lastActivityDate': '2024-05-10',
      });
      await seedStep('step-1', 'completed');
      await seedStep('step-2', 'completed');
      await seedStep('step-3', 'available');

      final result = await repository.restore(uid);

      expect(result, isA<Success<RestoredState>>());
      final state = result.valueOrNull!;
      expect(state.accountExists, isTrue);
      expect(
        state.profile,
        const LearnerProfile(
          englishLevel: EnglishLevel.b1,
          goal: LearningGoal.both,
          nativeLanguage: NativeLanguage.telugu,
          placementLevel: CefrLevel.b2,
          onboarded: true,
        ),
      );
      expect(state.streak, const Streak(current: 4, longest: 9));
      expect(state.lastActivityDate, '2024-05-10');
      // Only completed steps are collected; available/locked steps are excluded.
      expect(state.completedStepIds, {'step-1', 'step-2'});
      expect(state.hasRestoredState, isTrue);
    },
  );

  test('drops unknown stored profile enum values during restore', () async {
    await seedUser();
    await seedProfile(<String, dynamic>{
      'englishLevel': 'Z9',
      'nativeLanguage': 'fr',
      'goal': 'both',
      'onboarded': true,
    });

    final state = (await repository.restore(uid)).valueOrNull!;
    expect(
      state.profile,
      const LearnerProfile(goal: LearningGoal.both, onboarded: true),
    );
  });

  test(
    'clamps an inconsistent stored streak so longest dominates current',
    () async {
      await seedUser();
      // A malformed document where longest < current and current is negative.
      await seedProgress(<String, dynamic>{
        'currentStreak': -3,
        'longestStreak': 1,
      });

      final state = (await repository.restore(uid)).valueOrNull!;
      // current floored at 0; longest lifted to at least current (0).
      expect(state.streak, const Streak(current: 0, longest: 1));
    },
  );

  test(
    'restores an account with no progress or profile documents yet',
    () async {
      // The root doc exists (account created) but feature docs were never
      // written — restore degrades each piece to its safe default.
      await seedUser();

      final state = (await repository.restore(uid)).valueOrNull!;
      expect(state.accountExists, isTrue);
      expect(state.profile, LearnerProfile.none);
      expect(state.streak, Streak.none);
      expect(state.lastActivityDate, isNull);
      expect(state.completedStepIds, isEmpty);
      // A returning account counts as restored state.
      expect(state.hasRestoredState, isTrue);
    },
  );

  test('ignores path progress documents in non-completed states', () async {
    await seedUser();
    await seedStep('locked-step', 'locked');
    await seedStep('available-step', 'available');
    await seedStep('bogus-step', 'not-a-state');

    final state = (await repository.restore(uid)).valueOrNull!;
    expect(state.completedStepIds, isEmpty);
  });

  test(
    'falls back to the self-selected level when placement is unset',
    () async {
      await seedUser();
      await seedProfile(<String, dynamic>{
        'englishLevel': 'A2',
        'goal': 'speaking',
        'nativeLanguage': 'hi',
        'onboarded': false,
      });

      final state = (await repository.restore(uid)).valueOrNull!;
      expect(state.profile.placementLevel, isNull);
      expect(state.profile.effectiveLevel, CefrLevel.a2);
    },
  );
}
