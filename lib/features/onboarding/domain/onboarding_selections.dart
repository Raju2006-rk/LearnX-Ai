import 'package:flutter/foundation.dart';

/// The learner's self-selected current English level, expressed as a
/// CEFR-like band. (Requirement 2.1)
///
/// The [wireValue] matches the raw strings stored in `englishLevel` on the
/// `users/{uid}/profile/main` document ("A1".."C1"), which the Firestore
/// security rules validate against this exact set. Keeping the enum ⇄ string
/// contract in the domain layer mirrors [AuthMethod] and means presentation
/// and data layers never hand-write these literals.
enum EnglishLevel {
  /// A1 — beginner.
  a1('A1', 'A1 · Beginner'),

  /// A2 — elementary.
  a2('A2', 'A2 · Elementary'),

  /// B1 — intermediate.
  b1('B1', 'B1 · Intermediate'),

  /// B2 — upper intermediate.
  b2('B2', 'B2 · Upper intermediate'),

  /// C1 — advanced.
  c1('C1', 'C1 · Advanced');

  const EnglishLevel(this.wireValue, this.label);

  /// The Firestore/wire representation of this level ("A1".."C1").
  final String wireValue;

  /// A human-readable label for the selection UI.
  final String label;

  /// Parses a stored [wireValue] back into an [EnglishLevel], returning `null`
  /// when the value is unknown (so callers can drop malformed entries).
  static EnglishLevel? fromWire(String? value) {
    if (value == null) return null;
    for (final level in EnglishLevel.values) {
      if (level.wireValue == value) return level;
    }
    return null;
  }
}

/// The learner's learning goal. (Requirement 2.2)
///
/// The [wireValue] matches the `goal` field on the profile document
/// ("speaking" | "job" | "both"), validated by the security rules.
enum LearningGoal {
  /// Improve spoken English.
  speaking('speaking', 'Speaking'),

  /// Prepare for a job / workplace English.
  job('job', 'Job'),

  /// Both speaking and job goals.
  both('both', 'Both');

  const LearningGoal(this.wireValue, this.label);

  /// The Firestore/wire representation of this goal.
  final String wireValue;

  /// A human-readable label for the selection UI.
  final String label;

  /// Parses a stored [wireValue] back into a [LearningGoal], returning `null`
  /// when the value is unknown.
  static LearningGoal? fromWire(String? value) {
    if (value == null) return null;
    for (final goal in LearningGoal.values) {
      if (goal.wireValue == value) return goal;
    }
    return null;
  }
}

/// The learner's native (first) language. (Requirement 2.3)
///
/// The [wireValue] matches the `nativeLanguage` field on the profile document
/// ("hi" | "ta" | "te" | "bn" | "mr"), validated by the security rules — so a
/// draft can only ever carry a value from this allowed set. The set is
/// intentionally closed for the MVP but extensible later (see requirements'
/// out-of-scope notes).
enum NativeLanguage {
  /// Hindi.
  hindi('hi', 'Hindi', 'हिन्दी'),

  /// Tamil.
  tamil('ta', 'Tamil', 'தமிழ்'),

  /// Telugu.
  telugu('te', 'Telugu', 'తెలుగు'),

  /// Bengali.
  bengali('bn', 'Bengali', 'বাংলা'),

  /// Marathi.
  marathi('mr', 'Marathi', 'मराठी');

  const NativeLanguage(this.wireValue, this.label, this.nativeName);

  /// The Firestore/wire representation of this language.
  final String wireValue;

  /// The English name of the language, for the selection UI.
  final String label;

  /// The language's own endonym, shown alongside the English label.
  final String nativeName;

  /// Parses a stored [wireValue] back into a [NativeLanguage], returning
  /// `null` when the value is unknown.
  static NativeLanguage? fromWire(String? value) {
    if (value == null) return null;
    for (final language in NativeLanguage.values) {
      if (language.wireValue == value) return language;
    }
    return null;
  }
}

/// The learner's onboarding selections as they are gathered across the
/// stepped flow.
///
/// Every field is nullable because the learner fills them in one step at a
/// time; the flow persists a profile draft (via `OnboardingRepository`) once
/// all three are chosen. Placement (task 5.6) refines `englishLevel` into a
/// stored `placementLevel` and marks the profile onboarded — this value
/// object deliberately stops at the three self-selected fields.
@immutable
class OnboardingSelections {
  const OnboardingSelections({
    this.englishLevel,
    this.goal,
    this.nativeLanguage,
  });

  /// The self-selected current English level. (Requirement 2.1)
  final EnglishLevel? englishLevel;

  /// The chosen learning goal. (Requirement 2.2)
  final LearningGoal? goal;

  /// The chosen native language. (Requirement 2.3)
  final NativeLanguage? nativeLanguage;

  /// Whether all three selections have been made and the draft is ready to
  /// persist.
  bool get isComplete =>
      englishLevel != null && goal != null && nativeLanguage != null;

  /// Returns a copy with the given fields replaced.
  OnboardingSelections copyWith({
    EnglishLevel? englishLevel,
    LearningGoal? goal,
    NativeLanguage? nativeLanguage,
  }) {
    return OnboardingSelections(
      englishLevel: englishLevel ?? this.englishLevel,
      goal: goal ?? this.goal,
      nativeLanguage: nativeLanguage ?? this.nativeLanguage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnboardingSelections &&
      other.englishLevel == englishLevel &&
      other.goal == goal &&
      other.nativeLanguage == nativeLanguage;

  @override
  int get hashCode => Object.hash(englishLevel, goal, nativeLanguage);

  @override
  String toString() => 'OnboardingSelections(englishLevel: $englishLevel, '
      'goal: $goal, nativeLanguage: $nativeLanguage)';
}
