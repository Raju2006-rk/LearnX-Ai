import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../../learning_path/domain/learning_path.dart';
import '../../onboarding/domain/learner_profile.dart';
import '../../onboarding/domain/onboarding_selections.dart';
import '../../progress/domain/streak.dart';
import '../domain/restored_state.dart';

/// Reads the whole `users/{uid}/**` tree in one pass so a learner signing in
/// on a new device has their account and progress rehydrated locally.
/// (Requirement 8.3)
///
/// This is the read half of cross-device restore. The individual
/// `users/{uid}/**` documents are also watched reactively elsewhere (the
/// router's onboarding/consent seams, the streak and weekly-summary
/// providers, and the learning-path read), so a returning learner's state
/// surfaces as snapshots arrive. [restore] complements those streams with a
/// single, consistent snapshot taken at sign-in: it fetches the user root
/// document, the singleton `profile/main` and `progress/main` documents, and
/// the `pathProgress` collection concurrently, then maps them into one
/// [RestoredState].
///
/// Reads are defensive: enum-valued fields are parsed from their stored wire
/// strings, dropping unknowns; streak counts are clamped (floored at zero,
/// `longest` lifted to at least `current`) so a malformed stored document can
/// never yield an invalid [Streak]; and missing documents degrade to the
/// safe defaults on [RestoredState] rather than failing. Connectivity
/// failures map to [NetworkException] and every other read failure (including
/// a rules rejection) to [AuthException], matching the other repositories.
class RestoreRepository {
  RestoreRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Reads `users/[uid]/**` and returns the rehydrated [RestoredState], or a
  /// typed failure.
  ///
  /// The four reads (user root, `profile/main`, `progress/main`, and the
  /// `pathProgress` collection) run concurrently; a single failure among them
  /// fails the whole restore so the caller never acts on a partially-read
  /// snapshot.
  Future<Result<RestoredState>> restore(String uid) async {
    try {
      final results = await Future.wait(<Future<Object?>>[
        _firestore.doc(FirestorePaths.userDoc(uid)).get(),
        _firestore.doc(FirestorePaths.profileDoc(uid)).get(),
        _firestore.doc(FirestorePaths.progressDoc(uid)).get(),
        _firestore
            .collection(FirestorePaths.pathProgressCollection(uid))
            .get(),
      ]);

      final userSnapshot =
          results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final profileSnapshot =
          results[1] as DocumentSnapshot<Map<String, dynamic>>;
      final progressSnapshot =
          results[2] as DocumentSnapshot<Map<String, dynamic>>;
      final pathProgressSnapshot =
          results[3] as QuerySnapshot<Map<String, dynamic>>;

      return Result.success(
        RestoredState(
          accountExists: userSnapshot.exists,
          profile: _profileFrom(profileSnapshot),
          streak: _streakFrom(progressSnapshot),
          lastActivityDate: _lastActivityDateFrom(progressSnapshot),
          completedStepIds: _completedStepIdsFrom(pathProgressSnapshot),
        ),
      );
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Maps the `profile/main` snapshot into a [LearnerProfile], dropping
  /// unknown stored enum values. Returns [LearnerProfile.none] when absent.
  LearnerProfile _profileFrom(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return LearnerProfile.none;
    final dto = ProfileDto.fromMap(snapshot.data() ?? const <String, dynamic>{});
    return LearnerProfile(
      englishLevel: EnglishLevel.fromWire(dto.englishLevel),
      goal: LearningGoal.fromWire(dto.goal),
      nativeLanguage: NativeLanguage.fromWire(dto.nativeLanguage),
      placementLevel: CefrLevel.fromWire(dto.placementLevel),
      onboarded: dto.onboarded,
    );
  }

  /// Maps the `progress/main` snapshot into a clamped [Streak]: counts are
  /// floored at zero and `longest` lifted to at least `current`, so an
  /// inconsistent stored document can never produce an invalid read model.
  /// Returns [Streak.none] when absent.
  Streak _streakFrom(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists) return Streak.none;
    final dto =
        ProgressDto.fromMap(snapshot.data() ?? const <String, dynamic>{});
    final current = dto.currentStreak < 0 ? 0 : dto.currentStreak;
    final longest = dto.longestStreak < current ? current : dto.longestStreak;
    return Streak(current: current, longest: longest);
  }

  /// Reads the `"YYYY-MM-DD"` last-activity date off `progress/main`, or
  /// `null` when the document is absent or the field is unset.
  String? _lastActivityDateFrom(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    if (!snapshot.exists) return null;
    return ProgressDto.fromMap(snapshot.data() ?? const <String, dynamic>{})
        .lastActivityDate;
  }

  /// Collects the step ids from `pathProgress` documents whose stored
  /// `state == "completed"`, mirroring how the learning-path read derives the
  /// completed set it hands to the unlock rule.
  Set<String> _completedStepIdsFrom(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final completed = <String>{};
    for (final doc in snapshot.docs) {
      final dto = PathProgressDto.fromMap(doc.data());
      if (StepState.fromWire(dto.state) == StepState.completed) {
        completed.add(doc.id);
      }
    }
    return completed;
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy.
  ///
  /// Connectivity failures map to [NetworkException]; every other read
  /// failure (including a rules rejection) maps to [AuthException].
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
        error.message ?? 'Could not restore your account on this device.',
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
      'Could not restore your account on this device.',
      error,
    );
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
