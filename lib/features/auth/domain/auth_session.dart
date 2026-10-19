import 'package:flutter/foundation.dart';

/// The authentication method a learner used to sign in.
///
/// The [wireValue] matches the raw strings stored in the `authMethods`
/// array on the `users/{uid}` document (see the design's data model and
/// [UserDto]). Keeping the mapping here means the domain layer owns the
/// enum ⇄ string contract instead of scattering literals across the app.
enum AuthMethod {
  /// Phone-number one-time-code sign-in. (Requirement 1.1)
  phone('phone'),

  /// Google account sign-in. (Requirement 1.2)
  google('google'),

  /// Email-and-password sign-in. (Requirement 1.3)
  email('email');

  const AuthMethod(this.wireValue);

  /// The Firestore/wire representation of this method.
  final String wireValue;

  /// Parses a stored [wireValue] back into an [AuthMethod], returning `null`
  /// when the value is unknown (so callers can drop malformed entries).
  static AuthMethod? fromWire(String value) {
    for (final method in AuthMethod.values) {
      if (method.wireValue == value) return method;
    }
    return null;
  }
}

/// A signed-in learner's authentication session.
///
/// Produced by the auth repository after a successful sign-in and after the
/// account and profile documents have been created-or-restored. Carries the
/// learner's [uid], the set of [authMethods] recorded on the account, and
/// whether this sign-in created a brand-new account ([isNewUser]) so the
/// caller can route first-time learners into onboarding. (Requirements 1.4,
/// 1.6)
@immutable
class AuthSession {
  const AuthSession({
    required this.uid,
    required this.authMethods,
    this.isNewUser,
  });

  /// The signed-in learner's Firebase uid.
  final String uid;

  /// The authentication methods recorded on the account, in a stable order
  /// (existing methods first, newly added ones appended).
  final List<AuthMethod> authMethods;

  /// Whether this sign-in created a new account, when known. `null` when the
  /// underlying provider did not report it.
  final bool? isNewUser;

  @override
  bool operator ==(Object other) =>
      other is AuthSession &&
      other.uid == uid &&
      listEquals(other.authMethods, authMethods) &&
      other.isNewUser == isNewUser;

  @override
  int get hashCode => Object.hash(uid, Object.hashAll(authMethods), isNewUser);

  @override
  String toString() =>
      'AuthSession(uid: $uid, authMethods: $authMethods, isNewUser: $isNewUser)';
}
