import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_session.dart';

/// The outcome of a completed Firebase sign-in, reduced to the fields the
/// repository needs.
///
/// The data source hands back this thin value instead of a raw
/// [UserCredential] so the repository stays decoupled from the Firebase SDK
/// surface and is easy to drive in tests.
class AuthUserResult {
  const AuthUserResult({
    required this.uid,
    required this.method,
    this.isNewUser,
  });

  /// The signed-in learner's Firebase uid.
  final String uid;

  /// Which method produced this sign-in.
  final AuthMethod method;

  /// Whether Firebase reported this as a brand-new account, when available.
  final bool? isNewUser;
}

/// A pending phone-number verification produced by [AuthDataSource].
///
/// The phone flow is two-step: the learner requests a code (yielding this
/// [verificationId]) and then submits the SMS code, which is combined with
/// the id to sign in. (Requirement 1.1)
class PhoneVerification {
  const PhoneVerification({
    required this.verificationId,
    this.resendToken,
  });

  /// The opaque id Firebase issues when a code is sent; required to build the
  /// phone credential.
  final String verificationId;

  /// Optional token used to resend the code on the same session.
  final int? resendToken;
}

/// A thin wrapper over [FirebaseAuth] exposing the sign-in flows LearnX
/// supports: phone OTP, Google, and email/password. (Requirements 1.1–1.3)
///
/// This layer performs no error normalization — it lets Firebase exceptions
/// (e.g. [FirebaseAuthException]) propagate so the [AuthRepository] can map
/// them into the app's [AppException] hierarchy. It also does not touch
/// Firestore; account/profile create-or-restore lives in the repository.
class AuthDataSource {
  AuthDataSource(this._auth);

  final FirebaseAuth _auth;

  /// The default timeout applied when waiting for the SMS auto-retrieval
  /// window before falling back to manual code entry.
  static const Duration _defaultPhoneTimeout = Duration(seconds: 60);

  /// The currently signed-in learner's uid, or `null` when signed out.
  ///
  /// Available synchronously once Firebase is initialized, which the router
  /// uses for instant launch routing. (Requirement 1.6)
  String? get currentUid => _auth.currentUser?.uid;

  /// Starts phone-number verification, resolving once Firebase has sent the
  /// SMS code (or the auto-retrieval window times out) with the
  /// [PhoneVerification] needed to complete sign-in. (Requirement 1.1)
  ///
  /// Rejects with a [FirebaseAuthException] when verification fails (e.g. an
  /// invalid number), which the repository maps to a typed failure.
  Future<PhoneVerification> startPhoneVerification(
    String phoneNumber, {
    Duration timeout = _defaultPhoneTimeout,
  }) {
    final completer = Completer<PhoneVerification>();

    // ignore: discarded_futures — verifyPhoneNumber drives the completer via
    // its callbacks; awaiting it would not surface codeSent.
    _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: timeout,
      // Auto-retrieval (Android) may complete verification without the
      // learner typing a code. We still resolve via codeSent so the UI can
      // present the code-entry step uniformly across platforms.
      verificationCompleted: (_) {},
      verificationFailed: (error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      codeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneVerification(
              verificationId: verificationId,
              resendToken: resendToken,
            ),
          );
        }
      },
      codeAutoRetrievalTimeout: (verificationId) {
        if (!completer.isCompleted) {
          completer.complete(
            PhoneVerification(verificationId: verificationId),
          );
        }
      },
    );

    return completer.future;
  }

  /// Completes phone sign-in by combining a [verificationId] with the SMS
  /// [smsCode] the learner entered. (Requirement 1.1)
  Future<AuthUserResult> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    final result = await _auth.signInWithCredential(credential);
    return _resultFrom(result, AuthMethod.phone);
  }

  /// Signs the learner in with their Google account. (Requirement 1.2)
  ///
  /// Uses the platform provider flow so no Google API keys or tokens are
  /// handled on the client beyond what the Firebase SDK manages.
  Future<AuthUserResult> signInWithGoogle() async {
    final result = await _auth.signInWithProvider(GoogleAuthProvider());
    return _resultFrom(result, AuthMethod.google);
  }

  /// Signs the learner in with an existing email/password credential.
  /// (Requirement 1.3)
  Future<AuthUserResult> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _resultFrom(result, AuthMethod.email);
  }

  /// Registers a new email/password account and signs the learner in.
  /// (Requirement 1.3)
  Future<AuthUserResult> registerWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _resultFrom(result, AuthMethod.email);
  }

  /// Signs the current learner out.
  Future<void> signOut() => _auth.signOut();

  AuthUserResult _resultFrom(UserCredential credential, AuthMethod method) {
    final user = credential.user;
    if (user == null) {
      // Firebase returns a credential without a user only in error states;
      // surface it as an auth failure the repository can map.
      throw FirebaseAuthException(
        code: 'user-not-found',
        message: 'Sign-in did not return an authenticated user.',
      );
    }
    return AuthUserResult(
      uid: user.uid,
      method: method,
      isNewUser: credential.additionalUserInfo?.isNewUser,
    );
  }
}
