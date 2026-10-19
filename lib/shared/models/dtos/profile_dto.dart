import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for the singleton profile document `users/{uid}/profile/main`.
///
/// Mirrors: `englishLevel ("A1".."C1"), goal ("speaking"|"job"|"both"),
/// nativeLanguage ("hi"|"ta"|"te"|"bn"|"mr"), placementLevel ("A1".."C1"),
/// onboarded, updatedAt`.
///
/// Enum-valued fields are carried as raw strings so this layer stays a pure
/// serialization mapping; feature domain types validate/parse them later.
@immutable
class ProfileDto {
  const ProfileDto({
    this.englishLevel,
    this.goal,
    this.nativeLanguage,
    this.placementLevel,
    this.onboarded = false,
    this.updatedAt,
  });

  factory ProfileDto.fromMap(Map<String, dynamic> map) {
    return ProfileDto(
      englishLevel: stringOrNull(map['englishLevel']),
      goal: stringOrNull(map['goal']),
      nativeLanguage: stringOrNull(map['nativeLanguage']),
      placementLevel: stringOrNull(map['placementLevel']),
      onboarded: boolOr(map['onboarded']),
      updatedAt: dateTimeFromFirestore(map['updatedAt']),
    );
  }

  /// Self-selected CEFR level, `"A1".."C1"`.
  final String? englishLevel;

  /// `"speaking" | "job" | "both"`.
  final String? goal;

  /// `"hi" | "ta" | "te" | "bn" | "mr"`.
  final String? nativeLanguage;

  /// Placement-assigned CEFR level, `"A1".."C1"`.
  final String? placementLevel;

  final bool onboarded;
  final DateTime? updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'englishLevel': englishLevel,
      'goal': goal,
      'nativeLanguage': nativeLanguage,
      'placementLevel': placementLevel,
      'onboarded': onboarded,
      'updatedAt': timestampFromDateTime(updatedAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ProfileDto &&
      other.englishLevel == englishLevel &&
      other.goal == goal &&
      other.nativeLanguage == nativeLanguage &&
      other.placementLevel == placementLevel &&
      other.onboarded == onboarded &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        englishLevel,
        goal,
        nativeLanguage,
        placementLevel,
        onboarded,
        updatedAt,
      );
}
