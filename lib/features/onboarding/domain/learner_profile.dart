import 'package:flutter/foundation.dart';

import 'onboarding_selections.dart';

/// The learner's fully-restored profile, read back from
/// `users/{uid}/profile/main`.
///
/// This is the read-model counterpart to [OnboardingSelections]: where
/// [OnboardingSelections] carries the three self-selected fields *while the
/// learner is filling in onboarding*, [LearnerProfile] is the complete,
/// persisted profile rehydrated for a **signed-in** learner — including the
/// placement-assigned [placementLevel] and the [onboarded] flag that
/// [OnboardingSelections] deliberately omits.
///
/// It exists for cross-device restore (Requirement 8.3): when a returning,
/// already-onboarded learner signs in on a new device, the app reads their
/// `users/{uid}/**` profile and surfaces it here so features that depend on
/// the learner's profile — the AI Teacher's native-language translation
/// (Requirement 4.3), CEFR/goal-tagged personalization (Requirement 3.5) —
/// have the restored values without re-running onboarding.
///
/// Enum-valued fields are parsed from their stored wire strings, dropping any
/// unknown value (so a malformed stored document can never surface an invalid
/// enum). All fields are nullable because a brand-new or mid-onboarding
/// learner may not have set them yet.
@immutable
class LearnerProfile {
  const LearnerProfile({
    this.englishLevel,
    this.goal,
    this.nativeLanguage,
    this.placementLevel,
    this.onboarded = false,
  });

  /// The signed-out / not-yet-loaded profile: nothing restored, not onboarded.
  ///
  /// Consumers render this as a safe default while signed out or before the
  /// first snapshot arrives, exactly as the streak/summary providers emit
  /// their own "none"/"empty" value for the signed-out state.
  static const LearnerProfile none = LearnerProfile();

  /// The self-selected current English level. (Requirement 2.1)
  final EnglishLevel? englishLevel;

  /// The chosen learning goal. (Requirement 2.2)
  final LearningGoal? goal;

  /// The chosen native language, used for grammar-feedback translations.
  /// (Requirements 2.3, 4.3)
  final NativeLanguage? nativeLanguage;

  /// The placement-assigned CEFR level. (Requirement 2.5)
  final CefrLevel? placementLevel;

  /// Whether the learner has completed onboarding. (Requirement 2.6)
  final bool onboarded;

  /// The learner's effective working CEFR level: the placement result when
  /// available, otherwise their self-selected level. `null` when neither is
  /// set (a brand-new learner).
  CefrLevel? get effectiveLevel =>
      placementLevel ?? CefrLevel.fromEnglishLevel(englishLevel);

  @override
  bool operator ==(Object other) =>
      other is LearnerProfile &&
      other.englishLevel == englishLevel &&
      other.goal == goal &&
      other.nativeLanguage == nativeLanguage &&
      other.placementLevel == placementLevel &&
      other.onboarded == onboarded;

  @override
  int get hashCode => Object.hash(
        englishLevel,
        goal,
        nativeLanguage,
        placementLevel,
        onboarded,
      );

  @override
  String toString() => 'LearnerProfile(englishLevel: $englishLevel, '
      'goal: $goal, nativeLanguage: $nativeLanguage, '
      'placementLevel: $placementLevel, onboarded: $onboarded)';
}

/// A CEFR-like level ("A1".."C1") as stored in `placementLevel`.
///
/// Placement stores the same band set as [EnglishLevel]; this mirror type
/// keeps the restored `placementLevel` strongly typed on the read model
/// without coupling it to the onboarding-selection enum. [fromWire] drops
/// unknown stored values.
enum CefrLevel {
  a1('A1'),
  a2('A2'),
  b1('B1'),
  b2('B2'),
  c1('C1');

  const CefrLevel(this.wireValue);

  /// The Firestore/wire representation of this level ("A1".."C1").
  final String wireValue;

  /// Parses a stored [wireValue] into a [CefrLevel], returning `null` when the
  /// value is unknown.
  static CefrLevel? fromWire(String? value) {
    if (value == null) return null;
    for (final level in CefrLevel.values) {
      if (level.wireValue == value) return level;
    }
    return null;
  }

  /// Maps a self-selected [EnglishLevel] to its matching [CefrLevel], or
  /// `null` when none is set (they share the same "A1".."C1" band set).
  static CefrLevel? fromEnglishLevel(EnglishLevel? level) {
    if (level == null) return null;
    return fromWire(level.wireValue);
  }
}
