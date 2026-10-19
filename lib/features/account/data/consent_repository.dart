import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';

/// Records and reads the learner's DPDP consent on the user root document
/// `users/{uid}`. (Requirement 10.3)
///
/// The client is permitted to record only its *acceptance* of DPDP
/// personal-data processing — `consent.dpdpAccepted` and `consent.acceptedAt`.
/// It deliberately does **not** write `consent.policyVersion`: the Firestore
/// security rules make that field read-only to clients (server-stamped via a
/// trusted path), so writing it would cause the whole consent write to be
/// rejected. The acknowledged policy version is surfaced in the UI (see
/// `ConsentPolicy`) and reconciled server-side.
///
/// The write is a **merge** so it never clobbers the sibling user fields the
/// auth repository created (`createdAt`, `accountTier`, `authMethods`) nor a
/// server-stamped `consent.policyVersion` — merge recursively combines the
/// nested `consent` map. This consent MUST be captured before any onboarding
/// profile write, because the rules gate every feature/profile write on
/// `consent.dpdpAccepted == true`.
class ConsentRepository {
  ConsentRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Records the learner's DPDP acceptance on `users/[uid]`, returning a typed
  /// [Result].
  ///
  /// Writes `consent.dpdpAccepted = true` and `consent.acceptedAt` (server
  /// timestamp) via a merge write. Does not write `consent.policyVersion`
  /// (server-owned / read-only to clients). (Requirement 10.3)
  Future<Result<void>> acceptDpdp({required String uid}) async {
    try {
      await _firestore.doc(FirestorePaths.userDoc(uid)).set(
        <String, dynamic>{
          'consent': <String, dynamic>{
            'dpdpAccepted': true,
            'acceptedAt': FieldValue.serverTimestamp(),
          },
        },
        SetOptions(merge: true),
      );
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Reads the current consent block from `users/[uid]`, if any.
  ///
  /// Returns a `null` [ConsentDto] when the user document or its `consent`
  /// block does not exist yet, so callers can treat "no record" as
  /// not-consented. Lets the UI display the recorded acceptance / policy
  /// version.
  Future<Result<ConsentDto?>> loadConsent(String uid) async {
    try {
      final snapshot = await _firestore.doc(FirestorePaths.userDoc(uid)).get();
      if (!snapshot.exists) return const Result.success(null);
      final user = UserDto.fromMap(snapshot.data() ?? const <String, dynamic>{});
      return Result.success(user.consent);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Streams whether the learner at `users/[uid]` has recorded DPDP consent.
  ///
  /// Emits `true` once `consent.dpdpAccepted == true` is persisted and `false`
  /// otherwise (including while the user document or its `consent` block does
  /// not exist yet). Backed by a Firestore document snapshot stream so the
  /// router's consent seam advances the learner the moment acceptance is
  /// recorded, and reflects already-recorded consent on a returning device
  /// (cross-device restore). (Requirement 10.3)
  Stream<bool> watchDpdpAccepted(String uid) {
    return _firestore.doc(FirestorePaths.userDoc(uid)).snapshots().map(
      (snapshot) {
        if (!snapshot.exists) return false;
        final user =
            UserDto.fromMap(snapshot.data() ?? const <String, dynamic>{});
        return user.consent?.dpdpAccepted ?? false;
      },
    );
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy.
  ///
  /// Connectivity failures map to [NetworkException]; every other write
  /// failure (including a rules rejection) maps to [AuthException] as a
  /// permission failure.
  AppException _mapError(Object error) {
    if (error is FirebaseException) {
      if (_isNetworkCode(error.code)) {
        return NetworkException(
          error.message ??
              'A network error occurred. Check your connection and try again.',
          error,
        );
      }
      return AuthException(
        error.message ?? 'Could not record your consent. Please try again.',
        error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return NetworkException(
        'A network error occurred. Check your connection and try again.',
        error,
      );
    }
    return AuthException(
      'Could not record your consent. Please try again.',
      error,
    );
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
