import 'package:flutter/foundation.dart';

import 'firestore_converters.dart';

/// DTO for the `dailyGoal` block on `progress/main`:
/// `{ day, targetPerDay }`.
@immutable
class DailyGoalDto {
  const DailyGoalDto({this.day = 0, this.targetPerDay = 0});

  factory DailyGoalDto.fromMap(Map<String, dynamic> map) {
    return DailyGoalDto(
      day: intOr(map['day']),
      targetPerDay: intOr(map['targetPerDay']),
    );
  }

  final int day;
  final int targetPerDay;

  Map<String, dynamic> toMap() =>
      <String, dynamic>{'day': day, 'targetPerDay': targetPerDay};

  @override
  bool operator ==(Object other) =>
      other is DailyGoalDto &&
      other.day == day &&
      other.targetPerDay == targetPerDay;

  @override
  int get hashCode => Object.hash(day, targetPerDay);
}

/// DTO for a badge entry on `progress/main.badges`:
/// `{ tier ("bronze"|"silver"|"gold"), awardedAt, milestone }`.
///
/// `tier` is carried as a raw string; the progress domain validates it.
@immutable
class BadgeDto {
  const BadgeDto({required this.tier, this.awardedAt, this.milestone});

  factory BadgeDto.fromMap(Map<String, dynamic> map) {
    return BadgeDto(
      tier: stringOr(map['tier']),
      awardedAt: dateTimeFromFirestore(map['awardedAt']),
      milestone: stringOrNull(map['milestone']),
    );
  }

  /// `"bronze" | "silver" | "gold"`.
  final String tier;
  final DateTime? awardedAt;

  /// Identifier of the crossed milestone (config-defined).
  final String? milestone;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'tier': tier,
      'awardedAt': timestampFromDateTime(awardedAt),
      'milestone': milestone,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is BadgeDto &&
      other.tier == tier &&
      other.awardedAt == awardedAt &&
      other.milestone == milestone;

  @override
  int get hashCode => Object.hash(tier, awardedAt, milestone);
}

/// DTO for the singleton `users/{uid}/progress/main` document:
/// `currentStreak, longestStreak, lastActivityDate ("YYYY-MM-DD"),
/// dailyGoal, badges[]`.
@immutable
class ProgressDto {
  const ProgressDto({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastActivityDate,
    this.dailyGoal = const DailyGoalDto(),
    this.badges = const [],
  });

  factory ProgressDto.fromMap(Map<String, dynamic> map) {
    final goalMap = mapOrNull(map['dailyGoal']);
    return ProgressDto(
      currentStreak: intOr(map['currentStreak']),
      longestStreak: intOr(map['longestStreak']),
      lastActivityDate: stringOrNull(map['lastActivityDate']),
      dailyGoal:
          goalMap == null ? const DailyGoalDto() : DailyGoalDto.fromMap(goalMap),
      badges: mapListFrom(map['badges'])
          .map(BadgeDto.fromMap)
          .toList(growable: false),
    );
  }

  final int currentStreak;
  final int longestStreak;

  /// The last qualifying-activity date as `"YYYY-MM-DD"` (stored as a string,
  /// per the design, for calendar-day streak comparisons).
  final String? lastActivityDate;
  final DailyGoalDto dailyGoal;
  final List<BadgeDto> badges;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastActivityDate': lastActivityDate,
      'dailyGoal': dailyGoal.toMap(),
      'badges': badges.map((b) => b.toMap()).toList(growable: false),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ProgressDto &&
      other.currentStreak == currentStreak &&
      other.longestStreak == longestStreak &&
      other.lastActivityDate == lastActivityDate &&
      other.dailyGoal == dailyGoal &&
      listEquals(other.badges, badges);

  @override
  int get hashCode => Object.hash(
        currentStreak,
        longestStreak,
        lastActivityDate,
        dailyGoal,
        Object.hashAll(badges),
      );
}

/// DTO for `users/{uid}/progress/main/dailyActivity/{yyyy-mm-dd}`:
/// `activities, timeSpentSec, wordsLearned, mistakesFixed`.
@immutable
class DailyActivityDto {
  const DailyActivityDto({
    this.activities = 0,
    this.timeSpentSec = 0,
    this.wordsLearned = 0,
    this.mistakesFixed = 0,
  });

  factory DailyActivityDto.fromMap(Map<String, dynamic> map) {
    return DailyActivityDto(
      activities: intOr(map['activities']),
      timeSpentSec: intOr(map['timeSpentSec']),
      wordsLearned: intOr(map['wordsLearned']),
      mistakesFixed: intOr(map['mistakesFixed']),
    );
  }

  final int activities;
  final int timeSpentSec;
  final int wordsLearned;
  final int mistakesFixed;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'activities': activities,
      'timeSpentSec': timeSpentSec,
      'wordsLearned': wordsLearned,
      'mistakesFixed': mistakesFixed,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is DailyActivityDto &&
      other.activities == activities &&
      other.timeSpentSec == timeSpentSec &&
      other.wordsLearned == wordsLearned &&
      other.mistakesFixed == mistakesFixed;

  @override
  int get hashCode =>
      Object.hash(activities, timeSpentSec, wordsLearned, mistakesFixed);
}

/// DTO for `users/{uid}/weeklySummaries/{isoWeek}`:
/// `timeSpentSec, wordsLearned, mistakesFixed, generatedAt`.
@immutable
class WeeklySummaryDto {
  const WeeklySummaryDto({
    this.timeSpentSec = 0,
    this.wordsLearned = 0,
    this.mistakesFixed = 0,
    this.generatedAt,
  });

  factory WeeklySummaryDto.fromMap(Map<String, dynamic> map) {
    return WeeklySummaryDto(
      timeSpentSec: intOr(map['timeSpentSec']),
      wordsLearned: intOr(map['wordsLearned']),
      mistakesFixed: intOr(map['mistakesFixed']),
      generatedAt: dateTimeFromFirestore(map['generatedAt']),
    );
  }

  final int timeSpentSec;
  final int wordsLearned;
  final int mistakesFixed;
  final DateTime? generatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'timeSpentSec': timeSpentSec,
      'wordsLearned': wordsLearned,
      'mistakesFixed': mistakesFixed,
      'generatedAt': timestampFromDateTime(generatedAt),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is WeeklySummaryDto &&
      other.timeSpentSec == timeSpentSec &&
      other.wordsLearned == wordsLearned &&
      other.mistakesFixed == mistakesFixed &&
      other.generatedAt == generatedAt;

  @override
  int get hashCode =>
      Object.hash(timeSpentSec, wordsLearned, mistakesFixed, generatedAt);
}
