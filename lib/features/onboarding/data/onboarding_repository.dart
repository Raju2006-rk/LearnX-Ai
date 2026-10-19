import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/firebase/firestore_paths.dart';
import '../../../core/result.dart';
import '../../../shared/models/dtos/dtos.dart';
import '../domain/learner_profile.dart';
import '../domain/onboarding_selections.dart';

/// Persists the learner's onboarding selections as a profile draft.
///
/// Writes the three self-selected fields (`englishLevel`, `goal`,
/// `nativeLanguage`) to the singleton profile document
/// `users/{uid}/profile/main` with a **merge** write, so it never clobbers
/// other profile fields (e.g. a returning learner's `placementLevel` or
/// `onboarded` flag). (Requirements 2.1, 2.2, 2.3)
///
/// The draft values come from the domain enums, which map to exactly the
/// strings the Firestore security rules validate against — so a persisted
/// draft can only ever carry an allowed enum value. The rules additionally
/// require `consent.dpdpAccepted == true` on the parent user doc before any
/// profile write succeeds; a rejected write is normalized here into an
/// [AuthException] (a permission failure) rather than surfacing a raw SDK
/// error. Marking the profile `onboarded` and storing the placement level is
/// deliberately left to task 5.6.
class OnboardingRepository {
  OnboardingRepository({required FirebaseFirestore firestore})
    : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Merges the [selections] into `users/[uid]/profile/main`, returning a
  /// typed [Result].
  ///
  /// Only the fields present in [selections] are written; `null` fields are
  /// omitted so a partial draft (mid-flow) never overwrites an existing value
  /// with `null`. `updatedAt` is set to the server timestamp for sync
  /// last-write-wins resolution.
  Future<Result<void>> saveDraft({
    required String uid,
    required OnboardingSelections selections,
  }) async {
    try {
      final draft = <String, dynamic>{
        if (selections.englishLevel != null)
          'englishLevel': selections.englishLevel!.wireValue,
        if (selections.goal != null) 'goal': selections.goal!.wireValue,
        if (selections.nativeLanguage != null)
          'nativeLanguage': selections.nativeLanguage!.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _firestore
          .doc(FirestorePaths.profileDoc(uid))
          .set(draft, SetOptions(merge: true));
      return const Result.success(null);
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Reads the current profile draft, if any, mapping stored strings back into
  /// domain enums (dropping any unknown values). Returns empty selections when
  /// the profile document does not exist yet.
  ///
  /// Lets the flow rehydrate a learner's earlier choices when they return to
  /// onboarding before completing it.
  Future<Result<OnboardingSelections>> loadDraft(String uid) async {
    try {
      final snapshot = await _firestore
          .doc(FirestorePaths.profileDoc(uid))
          .get();
      if (!snapshot.exists) {
        return const Result.success(OnboardingSelections());
      }
      final dto = ProfileDto.fromMap(snapshot.data() ?? const {});
      return Result.success(
        OnboardingSelections(
          englishLevel: EnglishLevel.fromWire(dto.englishLevel),
          goal: LearningGoal.fromWire(dto.goal),
          nativeLanguage: NativeLanguage.fromWire(dto.nativeLanguage),
        ),
      );
    } catch (error) {
      return Result.failure(_mapError(error));
    }
  }

  /// Streams the persisted `onboarded` flag from `users/[uid]/profile/main`.
  ///
  /// Emits `true` once placement has marked the profile onboarded and `false`
  /// otherwise (including while the profile document does not exist yet).
  /// Backed by a document-snapshot stream so the router's `onboardedProvider`
  /// seam advances the learner to home the moment the flag is persisted, and
  /// reflects an already-onboarded profile on a returning device. (Requirement
  /// 2.6)
  Stream<bool> watchOnboarded(String uid) {
    return _firestore.doc(FirestorePaths.profileDoc(uid)).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return false;
      final dto = ProfileDto.fromMap(
        snapshot.data() ?? const <String, dynamic>{},
      );
      return dto.onboarded;
    });
  }

  /// Streams the learner's fully-restored [LearnerProfile] from
  /// `users/[uid]/profile/main`, for cross-device restore. (Requirement 8.3)
  ///
  /// This is the read half of cross-device restore: when a returning learner
  /// signs in on a new device, watching this document rehydrates their
  /// complete profile — self-selected level/goal/native language, the
  /// placement-assigned level, and the onboarded flag — the moment the first
  /// snapshot arrives, and keeps it live as it changes. Stored enum strings
  /// are parsed back into domain enums, dropping unknown values; a missing
  /// document (brand-new learner) emits [LearnerProfile.none] so consumers
  /// always have a safe, non-null value.
  ///
  /// Unlike [loadDraft] (a one-shot read scoped to the onboarding flow's three
  /// self-selected fields), this exposes the whole persisted profile
  /// reactively for app-wide consumers — e.g. the AI Teacher's native-language
  /// translation (Requirement 4.3) — so an already-onboarded learner on a new
  /// device never has to re-run onboarding to recover those values.
  Stream<LearnerProfile> watchProfile(String uid) {
    return _firestore.doc(FirestorePaths.profileDoc(uid)).snapshots().map((
      snapshot,
    ) {
      if (!snapshot.exists) return LearnerProfile.none;
      final dto = ProfileDto.fromMap(
        snapshot.data() ?? const <String, dynamic>{},
      );
      return LearnerProfile(
        englishLevel: EnglishLevel.fromWire(dto.englishLevel),
        goal: LearningGoal.fromWire(dto.goal),
        nativeLanguage: NativeLanguage.fromWire(dto.nativeLanguage),
        placementLevel: CefrLevel.fromWire(dto.placementLevel),
        onboarded: dto.onboarded,
      );
    });
  }

  /// Maps a raw SDK error into the app's typed exception hierarchy.
  ///
  /// Connectivity failures map to [NetworkException]; every other write
  /// failure (including a rules rejection such as a missing consent gate) maps
  /// to [AuthException] as a permission failure.
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
        error.message ?? 'Could not save your onboarding selections.',
        error,
      );
    }
    if (error is SocketException || error is TimeoutException) {
      return NetworkException(
        'A network error occurred. Check your connection and try again.',
        error,
      );
    }
    return AuthException('Could not save your onboarding selections.', error);
  }

  static bool _isNetworkCode(String code) {
    return code == 'network-request-failed' ||
        code == 'unavailable' ||
        code == 'deadline-exceeded';
  }
}
