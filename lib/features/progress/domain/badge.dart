import 'package:flutter/foundation.dart';

import '../../../shared/models/dtos/dtos.dart';

/// The three reward tiers a learner can earn as they cross configured
/// progress milestones. (Requirement 7.3)
///
/// The [wireValue] matches the raw `tier` string stored on a
/// `progress/main.badges[]` entry (`"bronze" | "silver" | "gold"`), which the
/// Firestore security rules also validate against this enum, so the feature
/// never hand-writes these literals.
enum BadgeTier {
  /// The entry-level reward, awarded at the lowest milestone.
  bronze('bronze'),

  /// The mid-tier reward, awarded at an intermediate milestone.
  silver('silver'),

  /// The top-tier reward, awarded at the highest milestone.
  gold('gold');

  const BadgeTier(this.wireValue);

  /// The Firestore/wire representation of this tier.
  final String wireValue;

  /// Parses a stored [value] into a [BadgeTier], returning `null` when the
  /// value is missing or unrecognized so a corrupt stored tier is dropped
  /// rather than crashing the progress read.
  static BadgeTier? fromWire(String? value) {
    if (value == null) return null;
    for (final tier in BadgeTier.values) {
      if (tier.wireValue == value) return tier;
    }
    return null;
  }
}

/// A reward a learner has earned, mirroring a `progress/main.badges[]` entry.
///
/// [tier] is the earned [BadgeTier]; [milestone] is the config-defined
/// identifier of the crossed threshold (so the awarding rule in later tasks
/// can stay idempotent — a milestone is awarded once); [awardedAt] records
/// when it was granted. The badge *awarding* logic (evaluating thresholds)
/// lives in task 10.3; this type is the domain model those tasks and the
/// progress read model share. (Requirement 7.3)
@immutable
class Badge {
  const Badge({required this.tier, this.milestone, this.awardedAt});

  /// Builds a [Badge] from its DTO, returning `null` when the stored [tier]
  /// is missing or unrecognized (an invalid tier is not a valid badge).
  static Badge? fromDto(BadgeDto dto) {
    final tier = BadgeTier.fromWire(dto.tier);
    if (tier == null) return null;
    return Badge(
      tier: tier,
      milestone: dto.milestone,
      awardedAt: dto.awardedAt,
    );
  }

  /// The earned reward tier.
  final BadgeTier tier;

  /// The config-defined identifier of the crossed milestone, or `null` when
  /// the badge was recorded without one.
  final String? milestone;

  /// When the badge was awarded, or `null` when unknown.
  final DateTime? awardedAt;

  /// Serializes this badge back to its DTO for persistence.
  BadgeDto toDto() => BadgeDto(
    tier: tier.wireValue,
    milestone: milestone,
    awardedAt: awardedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is Badge &&
      other.tier == tier &&
      other.milestone == milestone &&
      other.awardedAt == awardedAt;

  @override
  int get hashCode => Object.hash(tier, milestone, awardedAt);

  @override
  String toString() =>
      'Badge(tier: ${tier.wireValue}, milestone: $milestone)';
}
