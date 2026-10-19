// Tests for restoredStateProvider: it reads `users/{uid}/**` for a signed-in
// learner and resolves to RestoredState.none while signed out. (Requirement
// 8.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/sync/data/sync_providers.dart';
import 'package:learnx/features/sync/domain/restored_state.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  const uid = 'user-123';

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer makeContainer({String? signedInUid}) {
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

  test('resolves to RestoredState.none while signed out', () async {
    final container = makeContainer();

    final state = await container.read(restoredStateProvider.future);
    expect(state, RestoredState.none);
  });

  test('reads the user tree and rehydrates state for a signed-in learner',
      () async {
    await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
      'accountTier': 'free',
    });
    await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
      'onboarded': true,
    });
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 2,
      'longestStreak': 5,
    });
    await firestore
        .doc(FirestorePaths.pathProgressDoc(uid, 'step-1'))
        .set(<String, dynamic>{'state': 'completed'});

    final container = makeContainer(signedInUid: uid);

    final state = await container.read(restoredStateProvider.future);
    expect(state.accountExists, isTrue);
    expect(state.profile.onboarded, isTrue);
    expect(state.streak.current, 2);
    expect(state.streak.longest, 5);
    expect(state.completedStepIds, {'step-1'});
    expect(state.hasRestoredState, isTrue);
  });
}
