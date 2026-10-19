// Cross-device restore (task 11.3 / Requirement 8.3): when a returning learner
// signs in on a new device, establishing the authenticated uid rehydrates both
// their profile and their progress from `users/{uid}/**`.
//
// These tests seed a fake Firestore as if the documents were written on a
// previous device, then stand up a fresh ProviderContainer (standing in for a
// new device whose only local state is the established auth session) and assert
// that the profile and progress providers read the persisted state back.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderListenable is exported from riverpod's misc library, not from the
// flutter_riverpod barrel, under Riverpod 3.x.
import 'package:riverpod/misc.dart' show ProviderListenable;
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/onboarding/data/onboarding_providers.dart';
import 'package:learnx/features/onboarding/domain/learner_profile.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';
import 'package:learnx/features/progress/data/progress_providers.dart';
import 'package:learnx/features/progress/domain/streak.dart';

void main() {
  const uid = 'returning-learner';
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  /// Seeds the backend with a returning learner's profile + progress, as if
  /// written on their previous device.
  Future<void> seedPreviousDevice() async {
    await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
      'englishLevel': 'B1',
      'goal': 'both',
      'nativeLanguage': 'ta',
      'placementLevel': 'B2',
      'onboarded': true,
    });
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 5,
      'longestStreak': 12,
    });
  }

  /// A fresh container standing in for a new device signed in as [signedInUid].
  ProviderContainer newDevice({String? signedInUid = uid}) {
    final container = ProviderContainer(
      overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        authStateProvider.overrideWithValue(
          signedInUid == null
              ? const AuthState.signedOut()
              : AuthState(uid: signedInUid),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Reads the first value a [StreamProvider] emits, keeping it subscribed via
  /// a listener for the duration so the underlying Firestore snapshot stream is
  /// activated and stays alive until it emits.
  Future<T> firstValue<T>(
    ProviderContainer container,
    ProviderListenable<AsyncValue<T>> provider,
  ) async {
    final completer = Completer<T>();
    final sub = container.listen<AsyncValue<T>>(provider, (_, next) {
      if (next is AsyncData<T> && !completer.isCompleted) {
        completer.complete(next.value);
      }
    }, fireImmediately: true);
    // Cover the case where the value is already available synchronously.
    final current = container.read(provider);
    if (current is AsyncData<T> && !completer.isCompleted) {
      completer.complete(current.value);
    }
    final value = await completer.future;
    sub.close();
    return value;
  }

  test('profile rehydrates on a new device once signed in', () async {
    await seedPreviousDevice();
    final container = newDevice();

    final profile = await firstValue(container, learnerProfileProvider);

    expect(
      profile,
      const LearnerProfile(
        englishLevel: EnglishLevel.b1,
        goal: LearningGoal.both,
        nativeLanguage: NativeLanguage.tamil,
        placementLevel: CefrLevel.b2,
        onboarded: true,
      ),
    );
  });

  test('progress (streak) rehydrates on a new device once signed in', () async {
    await seedPreviousDevice();
    final container = newDevice();

    final streak = await firstValue(container, streakProvider);

    expect(streak, const Streak(current: 5, longest: 12));
  });

  test('router onboarded seam reflects the restored profile', () async {
    await seedPreviousDevice();
    final container = newDevice();

    // recordedOnboardedProvider streams from the same profile document the
    // router's redirect guard reads, so a returning onboarded learner skips
    // onboarding on the new device.
    final onboarded = await firstValue(container, recordedOnboardedProvider);
    expect(onboarded, isTrue);
  });

  test('signed-out device restores nothing', () async {
    await seedPreviousDevice();
    final container = newDevice(signedInUid: null);

    final profile = await firstValue(container, learnerProfileProvider);
    final streak = await firstValue(container, streakProvider);

    expect(profile, LearnerProfile.none);
    expect(streak, Streak.none);
  });

  test(
    'brand-new learner with no persisted state restores safe defaults',
    () async {
      // No seeding: nothing was written on any device yet.
      final container = newDevice();

      final profile = await firstValue(container, learnerProfileProvider);
      final streak = await firstValue(container, streakProvider);

      expect(profile, LearnerProfile.none);
      expect(profile.onboarded, isFalse);
      expect(streak, Streak.none);
    },
  );
}
