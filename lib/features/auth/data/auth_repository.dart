import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/auth_session.dart';
import 'auth_data_source.dart';

/// Orchestrates authentication: it drives [AuthDataSource] for the actual
/// sign-in, then creates-or-restores the learner's account (`users/{uid}`)
/// and profile (`users/{uid}/profile/main`) documents, and returns a typed
/// [Result] carrying an [AuthSession] on success or an [AppException] on
/// failure. (Requirements 1.1â€“1.4, 1.6)
///
/// All Firebase/SDK errors are normalized here into the app's exception
/// hierarchy: connectivity problems become [NetworkException]; every other
/// authentication failure becomes [AuthException]. Presentation and
/// application layers therefore branch on a small, known set of failures.
class AuthRepository {
  AuthRepository({
    required AuthDataSource dataSource,
    required FirebaseFirestore firestore,
  })  : _dataSource = dataSource,
        _firestore = firestore;

  final AuthDataSource _dataSource;
  final FirebaseFirestore _firestore;

  /// The currently signed-in learner's uid, or `null` when signed out.
  /// (Requirement 1.6)
  String? get currentUid => _dataSource.currentUid;

  /// Starts phone-number verification, returning the [PhoneVerification]
  /// needed to complete sign-in, or a typed failure. (Requirement 1.1)
  Future<Result<PhoneVerification>> startPhoneSignIn(String phoneNumber) async {
    try {
      final verification = await _dataSource.startPhoneVerification(phoneNumber);
      return Result.success(verification);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Completes phone sign-in with the [verificationId] and the SMS [smsCode],
  /// creating-or-restoring the account on success. (Requirements 1.1, 1.4)
  Future<Result<AuthSession>> completePhoneSignIn({
    required String verificationId,
    required String smsCode,
  }) {
    return _authenticate(
      () => _dataSource.signInWithSmsCode(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
  }

  /// Signs in with Google, creating-or-restoring the account on success.
  /// (Requirements 1.2, 1.4)
  Future<Result<AuthSession>> signInWithGoogle() {
    return _authenticate(_dataSource.signInWithGoogle);
  }

  /// Signs in with an existing email/password credential, creating-or-
  /// restoring the account on success. (Requirements 1.3, 1.4)
  Future<Result<AuthSession>> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _authenticate(
      () => _dataSource.signInWithEmailPassword(
        email: email,
        password: password,
      ),
    );
  }

  /// Registers a new email/password account and signs in, creating the
  /// account on success. (Requirements 1.3, 1.4)
  Future<Result<AuthSession>> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _authenticate(
      () => _dataSource.registerWithEmailPassword(
        email: email,
        password: password,
      ),
    );
  }

  /// Signs the current learner out.
  Future<Result<void>> signOut() async {
    try {
      await _dataSource.signOut();
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Runs a sign-in [action], then create-or-restore, normalizing all errors.
  Future<Result<AuthSession>> _authenticate(
    Future<AuthUserResult> Function() action,
  ) async {
    try {
      final result = await action();
      final session = await _createOrRestore(result);
      return Result.success(session);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Creates the account and profile documents on first sign-in, or restores
  /// (and refreshes) them for a returning learner, then returns the resulting
  /// [AuthSession]. (Requirement 1.4)
  ///
  /// - `users/{uid}`: created with `accountTier: free` and the sign-in method
  ///   when absent; otherwise `lastActiveAt` is refreshed and the method is
  ///   merged into `authMethods` (union, preserving existing order).
  /// - `users/{uid}/profile/main`: created (un-onboarded) when absent; left
  ///   untouched when it already exists so a returning learner's onboarding
  ///   is preserved.
  Future<AuthSession> _createOrRestore(AuthUserResult result) async {
    final uid = result.uid;
    final userRef = _firestore.doc(FirestorePaths.userDoc(uid));
    final profileRef = _firestore.doc(FirestorePaths.profileDoc(uid));

    // The user and profile documents are independent, so read them concurrently
    // rather than serially: on web/remote Firestore each round-trip costs real
    // latency, and the previous serial read -> write -> read -> write chain
    // stacked four trips into the post-sign-in "saving" delay. Running the two
    // reads together (then the two writes together) roughly halves the wait.
    final reads = await Future.wait(<Future<DocumentSnapshot<Map<String, dynamic>>>>[
      userRef.get(),
      profileRef.get(),
    ]);
    final snapshot = reads[0];
    final profileSnapshot = reads[1];

    final List<AuthMethod> methods;
    final Future<void> userWrite;
    if (!snapshot.exists) {
      methods = <AuthMethod>[result.method];
      userWrite = userRef.set(<String, dynamic>{
        'createdAt': FieldValue.serverTimestamp(),
        'lastActiveAt': FieldValue.serverTimestamp(),
        'accountTier': 'free',
        'authMethods': methods.map((m) => m.wireValue).toList(),
      });
    } else {
      methods = _mergeMethods(
        UserDto.fromMap(snapshot.data() ?? const <String, dynamic>{})
            .authMethods,
        result.method,
      );
      userWrite = userRef.set(
        <String, dynamic>{
          'lastActiveAt': FieldValue.serverTimestamp(),
          'authMethods': methods.map((m) => m.wireValue).toList(),
        },
        SetOptions(merge: true),
      );
    }

    // Only write the profile when it does not exist yet, so a returning
    // learner's onboarding is preserved. Run it alongside the user write.
    final Future<void> profileWrite = profileSnapshot.exists
        ? Future<void>.value()
        : profileRef.set(<String, dynamic>{
            ...const ProfileDto(onboarded: false).toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

    await Future.wait(<Future<void>>[userWrite, profileWrite]);

    return AuthSession(
      uid: uid,
      authMethods: methods,
      isNewUser: result.isNewUser,
    );
  }

  /// Returns the union of the [existing] recorded methods (parsed from their
  /// wire values, dropping unknowns) and the just-used [method], preserving
  /// the existing order and appending [method] only when new.
  List<AuthMethod> _mergeMethods(
    List<String> existing,
    AuthMethod method,
  ) {
    final merged = <AuthMethod>[];
    for (final raw in existing) {
      final parsed = AuthMethod.fromWire(raw);
      if (parsed != null && !merged.contains(parsed)) merged.add(parsed);
    }
    if (!merged.contains(method)) merged.add(method);
    return merged;
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy.
  ///
  /// Connectivity failures map to [NetworkException]; all other
  /// authentication errors map to [AuthException].
  AppException _mapError(Object error) {
    if (error is FirebaseAuthException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return AuthException(
        error.message ?? 'Authentication failed. Please try again.',
        error,
      );
    }
    if (error is FirebaseException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(error.message ?? 'A network error occurred.',
            error);
      }
      return AuthException(error.message ?? 'Authentication failed.', error);
    }
    if (error is SocketException || error is TimeoutException) {
      return NetworkException(
        'A network error occurred. Check your connection and try again.',
        error,
      );
    }
    return AuthException('Authentication failed. Please try again.', error);
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}

