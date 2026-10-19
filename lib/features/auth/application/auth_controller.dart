import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/result.dart';
import '../data/auth_providers.dart';
import '../data/auth_repository.dart';
import '../domain/auth_session.dart';

/// The view state the sign-in UI renders, produced by [AuthController].
///
/// A small, closed set of states so the presentation layer branches
/// exhaustively instead of juggling loose booleans: the learner is either
/// idle (choosing a method or filling a form), a request is in flight
/// ([AuthInProgress]), a phone code has been sent and the learner must enter
/// it ([AuthCodeSent]), a request failed ([AuthFailure]) with a message to
/// show while keeping the learner on the sign-in screen (Requirement 1.5),
/// or a session was established ([AuthSignedIn]) which the router observes to
/// redirect. (Requirements 1.1–1.5)
@immutable
sealed class AuthViewState {
  const AuthViewState();
}

/// No request in flight; the learner is choosing a method or filling a form.
@immutable
final class AuthIdle extends AuthViewState {
  const AuthIdle();
}

/// A sign-in request is in flight; the UI shows progress and disables inputs.
@immutable
final class AuthInProgress extends AuthViewState {
  const AuthInProgress();
}

/// A phone verification code was sent; the learner must submit the SMS code
/// to complete phone sign-in. Carries the [verificationId] the controller
/// needs to build the credential. (Requirement 1.1)
@immutable
final class AuthCodeSent extends AuthViewState {
  const AuthCodeSent({required this.verificationId});

  /// The opaque id Firebase issued when the code was sent.
  final String verificationId;

  @override
  bool operator ==(Object other) =>
      other is AuthCodeSent && other.verificationId == verificationId;

  @override
  int get hashCode => verificationId.hashCode;
}

/// A request failed; [message] is a human-readable error to display while the
/// learner stays on the sign-in screen. (Requirement 1.5)
@immutable
final class AuthFailure extends AuthViewState {
  const AuthFailure(this.message);

  /// The error text to surface to the learner.
  final String message;

  @override
  bool operator ==(Object other) =>
      other is AuthFailure && other.message == message;

  @override
  int get hashCode => message.hashCode;
}

/// Authentication succeeded and a [session] was established. (Requirement 1.4)
@immutable
final class AuthSignedIn extends AuthViewState {
  const AuthSignedIn(this.session);

  /// The signed-in learner's session.
  final AuthSession session;

  @override
  bool operator ==(Object other) =>
      other is AuthSignedIn && other.session == session;

  @override
  int get hashCode => session.hashCode;
}

/// Drives the sign-in flows (phone OTP, Google, email sign-in/register) by
/// calling [AuthRepository] and mapping its [Result]/`AppException` outcomes
/// to an [AuthViewState] the UI renders.
///
/// On failure the controller stores an [AuthFailure] with the exception's
/// message and does not sign the learner in, so the router keeps them on the
/// sign-in screen. (Requirement 1.5) On success it stores [AuthSignedIn];
/// the real auth state the router redirects on is driven by FirebaseAuth's
/// own auth-state stream (see `authStateProvider`).
class AuthController extends Notifier<AuthViewState> {
  @override
  AuthViewState build() => const AuthIdle();

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  /// Starts phone verification for [phoneNumber]. On success transitions to
  /// [AuthCodeSent] so the learner can enter the SMS code. (Requirement 1.1)
  Future<void> startPhoneSignIn(String phoneNumber) async {
    state = const AuthInProgress();
    final result = await _repository.startPhoneSignIn(phoneNumber);
    state = result.fold(
      (verification) =>
          AuthCodeSent(verificationId: verification.verificationId),
      (exception) => AuthFailure(exception.message),
    );
  }

  /// Completes phone sign-in with the [smsCode] the learner entered, using
  /// the [verificationId] from the preceding [AuthCodeSent] state.
  /// (Requirements 1.1, 1.4)
  Future<void> confirmPhoneCode({
    required String verificationId,
    required String smsCode,
  }) async {
    await _run(
      () => _repository.completePhoneSignIn(
        verificationId: verificationId,
        smsCode: smsCode,
      ),
    );
  }

  /// Signs in with Google. (Requirements 1.2, 1.4)
  Future<void> signInWithGoogle() => _run(_repository.signInWithGoogle);

  /// Signs in with an existing email/password credential.
  /// (Requirements 1.3, 1.4)
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _run(
      () => _repository.signInWithEmail(email: email, password: password),
    );
  }

  /// Registers a new email/password account and signs in.
  /// (Requirements 1.3, 1.4)
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) {
    return _run(
      () => _repository.registerWithEmail(email: email, password: password),
    );
  }

  /// Clears a failure back to idle so the learner can retry or switch methods.
  void reset() => state = const AuthIdle();

  /// Runs a sign-in [action] that yields a session, mapping the outcome to a
  /// view state: [AuthInProgress] while awaiting, [AuthSignedIn] on success,
  /// or [AuthFailure] carrying the error message on failure. (Requirement 1.5)
  Future<void> _run(Future<Result<AuthSession>> Function() action) async {
    state = const AuthInProgress();
    final result = await action();
    state = result.fold(
      (session) => AuthSignedIn(session),
      (exception) => AuthFailure(exception.message),
    );
  }
}

/// Exposes the [AuthController] and its [AuthViewState] to the sign-in UI.
final authControllerProvider =
    NotifierProvider<AuthController, AuthViewState>(
  AuthController.new,
  name: 'authControllerProvider',
);
