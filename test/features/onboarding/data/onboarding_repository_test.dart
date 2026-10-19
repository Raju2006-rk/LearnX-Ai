// Unit tests for OnboardingRepository: the profile-draft merge write and the
// draft rehydration read. (Requirements 2.1, 2.2, 2.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/onboarding/data/onboarding_repository.dart';
import 'package:learnx/features/onboarding/domain/learner_profile.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late OnboardingRepository repository;

  const uid = 'user-123';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = OnboardingRepository(firestore: firestore);
  });

  Future<Map<String, dynamic>?> readProfile() async =>
      (await firestore.doc(FirestorePaths.profileDoc(uid)).get()).data();

  test('saveDraft writes allowed enum wire values to profile/main', () async {
    final result = await repository.saveDraft(
      uid: uid,
      selections: const OnboardingSelections(
        englishLevel: EnglishLevel.b1,
        goal: LearningGoal.both,
        nativeLanguage: NativeLanguage.telugu,
      ),
    );

    expect(result, isA<Success<void>>());
    final profile = await readProfile();
    expect(profile, isNotNull);
    expect(profile!['englishLevel'], 'B1');
    expect(profile['goal'], 'both');
    expect(profile['nativeLanguage'], 'te');
    expect(profile['updatedAt'], isNotNull);
  });

  test('saveDraft merges without clobbering existing profile fields', () async {
    // A returning learner already has an onboarded profile.
    await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
      'onboarded': true,
      'placementLevel': 'B2',
    });

    await repository.saveDraft(
      uid: uid,
      selections: const OnboardingSelections(
        englishLevel: EnglishLevel.a1,
        goal: LearningGoal.speaking,
        nativeLanguage: NativeLanguage.hindi,
      ),
    );

    final profile = await readProfile();
    // New draft fields written.
    expect(profile!['englishLevel'], 'A1');
    expect(profile['goal'], 'speaking');
    expect(profile['nativeLanguage'], 'hi');
    // Pre-existing fields preserved by the merge write.
    expect(profile['onboarded'], isTrue);
    expect(profile['placementLevel'], 'B2');
  });

  test(
    'saveDraft omits unset fields so a partial draft keeps prior values',
    () async {
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'nativeLanguage': 'mr',
      });

      // Only the level is chosen so far.
      await repository.saveDraft(
        uid: uid,
        selections: const OnboardingSelections(englishLevel: EnglishLevel.c1),
      );

      final profile = await readProfile();
      expect(profile!['englishLevel'], 'C1');
      // nativeLanguage is untouched, not overwritten with null.
      expect(profile['nativeLanguage'], 'mr');
    },
  );

  group('watchOnboarded', () {
    test('emits false when no profile exists', () async {
      expect(repository.watchOnboarded(uid), emits(false));
    });

    test('emits true once the profile is marked onboarded', () async {
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'onboarded': true,
        'placementLevel': 'B1',
      });
      expect(repository.watchOnboarded(uid), emits(true));
    });

    test(
      'emits false for a profile that exists but is not onboarded',
      () async {
        await firestore.doc(FirestorePaths.profileDoc(uid)).set(
          <String, dynamic>{'englishLevel': 'A2'},
        );
        expect(repository.watchOnboarded(uid), emits(false));
      },
    );
  });

  group('watchProfile (cross-device restore read)', () {
    test('emits LearnerProfile.none when no profile exists', () {
      expect(repository.watchProfile(uid), emits(LearnerProfile.none));
    });

    test('rehydrates the full persisted profile into domain enums', () async {
      // Simulate a returning, already-onboarded learner's profile persisted on
      // a previous device.
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'englishLevel': 'B1',
        'goal': 'both',
        'nativeLanguage': 'te',
        'placementLevel': 'B2',
        'onboarded': true,
      });

      expect(
        repository.watchProfile(uid),
        emits(
          const LearnerProfile(
            englishLevel: EnglishLevel.b1,
            goal: LearningGoal.both,
            nativeLanguage: NativeLanguage.telugu,
            placementLevel: CefrLevel.b2,
            onboarded: true,
          ),
        ),
      );
    });

    test('drops unknown stored enum values during restore', () async {
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'englishLevel': 'Z9',
        'nativeLanguage': 'fr',
        'goal': 'both',
        'onboarded': true,
      });

      expect(
        repository.watchProfile(uid),
        emits(const LearnerProfile(goal: LearningGoal.both, onboarded: true)),
      );
    });

    test('falls back to self-selected level when placement is unset', () async {
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'englishLevel': 'A2',
        'goal': 'speaking',
        'nativeLanguage': 'hi',
        'onboarded': false,
      });

      final profile = await repository.watchProfile(uid).first;
      expect(profile.placementLevel, isNull);
      expect(profile.effectiveLevel, CefrLevel.a2);
    });
  });

  group('loadDraft', () {
    test('returns empty selections when no profile exists', () async {
      final result = await repository.loadDraft(uid);
      expect(result.valueOrNull, const OnboardingSelections());
    });

    test('maps stored strings back into domain enums', () async {
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'englishLevel': 'A2',
        'goal': 'job',
        'nativeLanguage': 'bn',
      });

      final result = await repository.loadDraft(uid);
      expect(
        result.valueOrNull,
        const OnboardingSelections(
          englishLevel: EnglishLevel.a2,
          goal: LearningGoal.job,
          nativeLanguage: NativeLanguage.bengali,
        ),
      );
    });

    test('drops unknown stored values', () async {
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'englishLevel': 'Z9',
        'nativeLanguage': 'fr',
      });

      final result = await repository.loadDraft(uid);
      expect(result.valueOrNull, const OnboardingSelections());
    });
  });
}
