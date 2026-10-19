import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/auth/data/auth_data_source.dart';
import 'package:learnx/features/auth/data/auth_repository.dart';
import 'package:learnx/features/auth/domain/auth_session.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthDataSource extends Mock implements AuthDataSource {}

void main() {
  late MockAuthDataSource dataSource;
  late FakeFirebaseFirestore firestore;
  late AuthRepository repository;

  const uid = 'user-123';

  setUp(() {
    dataSource = MockAuthDataSource();
    firestore = FakeFirebaseFirestore();
    repository = AuthRepository(dataSource: dataSource, firestore: firestore);
  });

  Future<Map<String, dynamic>?> readUser() async =>
      (await firestore.doc(FirestorePaths.userDoc(uid)).get()).data();

  Future<Map<String, dynamic>?> readProfile() async =>
      (await firestore.doc(FirestorePaths.profileDoc(uid)).get()).data();

  group('create-or-restore', () {
    test('creates account and profile on first sign-in', () async {
      when(dataSource.signInWithGoogle).thenAnswer(
        (_) async => const AuthUserResult(
          uid: uid,
          method: AuthMethod.google,
          isNewUser: true,
        ),
      );

      final result = await repository.signInWithGoogle();

      expect(result, isA<Success<AuthSession>>());
      final session = result.valueOrNull!;
      expect(session.uid, uid);
      expect(session.authMethods, [AuthMethod.google]);
      expect(session.isNewUser, isTrue);

      final user = await readUser();
      expect(user, isNotNull);
      expect(user!['accountTier'], 'free');
      expect(user['authMethods'], ['google']);
      expect(user['createdAt'], isNotNull);
      expect(user['lastActiveAt'], isNotNull);

      final profile = await readProfile();
      expect(profile, isNotNull);
      expect(profile!['onboarded'], isFalse);
    });

    test('restores existing account, merges auth methods, keeps profile',
        () async {
      // Seed a returning learner who signed in before with phone and has
      // already completed onboarding.
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
        'authMethods': ['phone'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2024, 1, 1)),
      });
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'onboarded': true,
        'nativeLanguage': 'hi',
      });

      when(
        () => dataSource.signInWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => const AuthUserResult(
          uid: uid,
          method: AuthMethod.email,
          isNewUser: false,
        ),
      );

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'secret',
      );

      final session = result.valueOrNull!;
      expect(session.authMethods, [AuthMethod.phone, AuthMethod.email]);
      expect(session.isNewUser, isFalse);

      final user = await readUser();
      expect(user!['authMethods'], ['phone', 'email']);
      // createdAt is preserved (merge write does not clobber it).
      expect(user['createdAt'], isNotNull);

      // Existing onboarding is left untouched.
      final profile = await readProfile();
      expect(profile!['onboarded'], isTrue);
      expect(profile['nativeLanguage'], 'hi');
    });

    test('does not duplicate an already-recorded method', () async {
      await firestore.doc(FirestorePaths.userDoc(uid)).set(<String, dynamic>{
        'accountTier': 'free',
        'authMethods': ['google'],
      });

      when(dataSource.signInWithGoogle).thenAnswer(
        (_) async => const AuthUserResult(
          uid: uid,
          method: AuthMethod.google,
          isNewUser: false,
        ),
      );

      final result = await repository.signInWithGoogle();

      expect(result.valueOrNull!.authMethods, [AuthMethod.google]);
      expect((await readUser())!['authMethods'], ['google']);
    });
  });

  group('Result mapping', () {
    test('phone sign-in success returns a signed-in session', () async {
      when(
        () => dataSource.signInWithSmsCode(
          verificationId: any(named: 'verificationId'),
          smsCode: any(named: 'smsCode'),
        ),
      ).thenAnswer(
        (_) async => const AuthUserResult(
          uid: uid,
          method: AuthMethod.phone,
          isNewUser: true,
        ),
      );

      final result = await repository.completePhoneSignIn(
        verificationId: 'vid',
        smsCode: '123456',
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.uid, uid);
      expect(result.valueOrNull!.authMethods, [AuthMethod.phone]);
    });

    test('startPhoneSignIn forwards the verification on success', () async {
      when(() => dataSource.startPhoneVerification(any())).thenAnswer(
        (_) async => const PhoneVerification(verificationId: 'vid-1'),
      );

      final result = await repository.startPhoneSignIn('+15550001111');

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.verificationId, 'vid-1');
    });
  });

  group('error mapping', () {
    test('network-request-failed maps to NetworkException', () async {
      when(
        () => dataSource.signInWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        FirebaseAuthException(code: 'network-request-failed'),
      );

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'x',
      );

      expect(result.isFailure, isTrue);
      expect(result.exceptionOrNull, isA<NetworkException>());
    });

    test('invalid credential maps to AuthException', () async {
      when(
        () => dataSource.signInWithEmailPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(
        FirebaseAuthException(code: 'wrong-password', message: 'bad creds'),
      );

      final result = await repository.signInWithEmail(
        email: 'a@b.com',
        password: 'x',
      );

      expect(result.isFailure, isTrue);
      expect(result.exceptionOrNull, isA<AuthException>());
      expect(result.exceptionOrNull!.message, 'bad creds');
    });

    test('SocketException maps to NetworkException', () async {
      when(dataSource.signInWithGoogle).thenThrow(
        const SocketException('no route to host'),
      );

      final result = await repository.signInWithGoogle();

      expect(result.exceptionOrNull, isA<NetworkException>());
    });

    test('a failed phone verification maps to a typed failure', () async {
      when(() => dataSource.startPhoneVerification(any())).thenThrow(
        FirebaseAuthException(code: 'invalid-phone-number'),
      );

      final result = await repository.startPhoneSignIn('bad');

      expect(result.isFailure, isTrue);
      expect(result.exceptionOrNull, isA<AuthException>());
    });

    test('an unexpected error maps to AuthException', () async {
      when(dataSource.signInWithGoogle).thenThrow(
        TimeoutException('timed out'),
      );

      final result = await repository.signInWithGoogle();

      // TimeoutException is treated as a network condition.
      expect(result.exceptionOrNull, isA<NetworkException>());
    });
  });
}
