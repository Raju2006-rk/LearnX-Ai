// Widget tests for the router's DPDP consent seam (task 5.4).
//
// Verifies that `consentProvider` reflects *recorded* consent — both the
// persisted `users/{uid}.consent.dpdpAccepted` flag (via the repository
// stream, backing cross-device restore) and in-session acceptance recorded
// through the ConsentController — so a signed-in learner is held on the
// consent screen until consent exists and then advances. (Requirement 10.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/app.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/account/application/consent_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

void main() {
  const uid = 'user-123';

  FirebaseAuth buildAuth() {
    final auth = _MockFirebaseAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    return auth;
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeFirebaseFirestore firestore,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWithValue(const AuthState(uid: uid)),
          firebaseFirestoreProvider.overrideWithValue(firestore),
          // Keep the learner off onboarding so the only gate under test is
          // consent.
          onboardedProvider.overrideWithValue(true),
        ],
        child: const LearnXApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a signed-in learner with no recorded consent is held on the consent '
    'screen',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      // User doc exists (created at sign-in) but without a consent block.
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
      });

      await pumpApp(tester, firestore: firestore);

      expect(find.text('How LearnX uses your data'), findsOneWidget);
      expect(find.text('Agree and continue'), findsOneWidget);
    },
  );

  testWidgets(
    'persisted consent advances a signed-in, onboarded learner to the home '
    'shell (cross-device restore)',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
        'consent': {'dpdpAccepted': true, 'policyVersion': 'v1'},
      });

      await pumpApp(tester, firestore: firestore);

      // Past the consent gate and onto the home shell.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('How LearnX uses your data'), findsNothing);
    },
  );

  testWidgets(
    'recording consent in-session advances the learner off the consent screen',
    (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
      });

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWithValue(const AuthState(uid: uid)),
            firebaseAuthProvider.overrideWithValue(buildAuth()),
            firebaseFirestoreProvider.overrideWithValue(firestore),
            onboardedProvider.overrideWithValue(true),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const LearnXApp();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts on the consent screen.
      expect(find.text('How LearnX uses your data'), findsOneWidget);

      // Record consent via the controller (as the Agree action does).
      await capturedRef.read(consentControllerProvider.notifier).accept();
      await tester.pumpAndSettle();

      // The in-session acceptance flips the seam and the router advances to
      // the home shell.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('How LearnX uses your data'), findsNothing);
    },
  );
}
