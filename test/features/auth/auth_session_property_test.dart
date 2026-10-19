// Property-based test for the authentication contract.
//
// Property 1: Successful authentication yields a signed-in session with a
// profile. For any successful authentication result — any sign-in method,
// whether Firebase reports a new or returning user, and whether the account
// and profile documents already exist or not — the repository produces a
// signed-in session (a `Success<AuthSession>` carrying the learner's uid) and
// a learner profile document exists afterward, whether newly created or
// restored. (Validates: Requirements 1.4)
//
// The project has no dedicated property-testing package, so this test follows
// the convention of driving many randomly generated inputs (100+ iterations)
// through the real collaborators: the actual `AuthRepository` running against
// an in-memory `FakeFirebaseFirestore`, with only the `AuthDataSource` (the
// Firebase SDK seam) mocked to stand in for a successful sign-in. A fixed seed
// keeps failures reproducible; a failing case prints the generated scenario.

import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/auth/data/auth_data_source.dart';
import 'package:learnx/features/auth/data/auth_repository.dart';
import 'package:learnx/features/auth/domain/auth_session.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthDataSource extends Mock implements AuthDataSource {}

/// One randomly generated authentication scenario.
class _Scenario {
  const _Scenario({
    required this.uid,
    required this.method,
    required this.isNewUser,
    required this.seedAccount,
    required this.seedProfile,
    required this.existingMethods,
    required this.existingOnboarded,
  });

  /// The signed-in learner's uid.
  final String uid;

  /// Which method produced the (successful) sign-in.
  final AuthMethod method;

  /// What Firebase reported for `isNewUser` (including the unknown `null`).
  final bool? isNewUser;

  /// Whether a `users/{uid}` document already exists (returning learner).
  final bool seedAccount;

  /// Whether a `users/{uid}/profile/main` document already exists.
  final bool seedProfile;

  /// Auth methods already recorded on a pre-existing account.
  final List<AuthMethod> existingMethods;

  /// Onboarding flag on a pre-existing profile (must be preserved).
  final bool existingOnboarded;

  @override
  String toString() => '_Scenario(uid: $uid, method: $method, '
      'isNewUser: $isNewUser, seedAccount: $seedAccount, '
      'seedProfile: $seedProfile, existingMethods: $existingMethods, '
      'existingOnboarded: $existingOnboarded)';
}

/// Builds a varied scenario from [random], covering new/returning accounts,
/// present/absent profiles, and every sign-in method.
_Scenario _generateScenario(Random random) {
  final methods = AuthMethod.values;
  final method = methods[random.nextInt(methods.length)];

  final seedAccount = random.nextBool();
  // A profile can only pre-exist when the account does.
  final seedProfile = seedAccount && random.nextBool();

  // A random, possibly-empty subset of previously-recorded methods.
  final existingMethods = seedAccount
      ? (methods.where((_) => random.nextBool()).toList())
      : const <AuthMethod>[];

  final isNewUserChoice = random.nextInt(3);
  return _Scenario(
    uid: 'user-${random.nextInt(1 << 32)}',
    method: method,
    isNewUser: switch (isNewUserChoice) {
      0 => true,
      1 => false,
      _ => null,
    },
    seedAccount: seedAccount,
    seedProfile: seedProfile,
    existingMethods: existingMethods,
    existingOnboarded: random.nextBool(),
  );
}

void main() {
  const iterations = 200;

  test(
    'Property 1: successful authentication yields a signed-in session with '
    'a profile',
    () async {
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(1374);

      for (var i = 0; i < iterations; i++) {
        final scenario = _generateScenario(random);
        final reason = 'iteration $i, $scenario';

        final dataSource = MockAuthDataSource();
        final firestore = FakeFirebaseFirestore();
        final repository = AuthRepository(
          dataSource: dataSource,
          firestore: firestore,
        );

        // Seed any pre-existing documents for a returning learner.
        if (scenario.seedAccount) {
          await firestore
              .doc(FirestorePaths.userDoc(scenario.uid))
              .set(<String, dynamic>{
            'accountTier': 'free',
            'authMethods':
                scenario.existingMethods.map((m) => m.wireValue).toList(),
            'createdAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
          });
        }
        if (scenario.seedProfile) {
          await firestore
              .doc(FirestorePaths.profileDoc(scenario.uid))
              .set(<String, dynamic>{'onboarded': scenario.existingOnboarded});
        }

        // Stand in for a successful Firebase sign-in via the mocked data
        // source, routed by the generated method.
        final authResult = AuthUserResult(
          uid: scenario.uid,
          method: scenario.method,
          isNewUser: scenario.isNewUser,
        );
        final Future<Result<AuthSession>> invocation;
        switch (scenario.method) {
          case AuthMethod.phone:
            when(
              () => dataSource.signInWithSmsCode(
                verificationId: any(named: 'verificationId'),
                smsCode: any(named: 'smsCode'),
              ),
            ).thenAnswer((_) async => authResult);
            invocation = repository.completePhoneSignIn(
              verificationId: 'vid',
              smsCode: '123456',
            );
          case AuthMethod.google:
            when(dataSource.signInWithGoogle)
                .thenAnswer((_) async => authResult);
            invocation = repository.signInWithGoogle();
          case AuthMethod.email:
            when(
              () => dataSource.signInWithEmailPassword(
                email: any(named: 'email'),
                password: any(named: 'password'),
              ),
            ).thenAnswer((_) async => authResult);
            invocation = repository.signInWithEmail(
              email: 'learner@example.com',
              password: 'secret',
            );
        }

        final result = await invocation;

        // The session state is signed-in: a success carrying the learner uid.
        expect(result, isA<Success<AuthSession>>(), reason: reason);
        final session = result.valueOrNull;
        expect(session, isNotNull, reason: reason);
        expect(session!.uid, scenario.uid, reason: reason);
        // The just-used method is always recorded on the session.
        expect(session.authMethods, contains(scenario.method), reason: reason);

        // A learner profile exists afterward, whether created or restored.
        final profileSnapshot = await firestore
            .doc(FirestorePaths.profileDoc(scenario.uid))
            .get();
        expect(profileSnapshot.exists, isTrue, reason: reason);

        // A pre-existing profile is restored untouched (onboarding preserved);
        // a freshly created one starts un-onboarded.
        final onboarded = (profileSnapshot.data() ?? const {})['onboarded'];
        if (scenario.seedProfile) {
          expect(onboarded, scenario.existingOnboarded, reason: reason);
        } else {
          expect(onboarded, isFalse, reason: reason);
        }

        // The account document also exists (created or restored).
        final userSnapshot =
            await firestore.doc(FirestorePaths.userDoc(scenario.uid)).get();
        expect(userSnapshot.exists, isTrue, reason: reason);
      }
    },
  );
}
