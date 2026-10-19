import 'package:flutter/foundation.dart';

import '../../../core/config/remote_config.dart' as config;
import 'badge.dart';

/// The pure badge-awarding rule: given a learner's current progress value and
/// the configured [config.BadgeMilestone]s, it decides which milestones have
/// been crossed and which of those are *not yet recorded*, so the matching
/// Bronze/Silver/Gold badges can be awarded idempotently. (Requirement 7.3)
///
/// This carries no I/O. The repository reads the persisted `progress/main`
/// document (current streak + already-awarded `badges[]`), runs this rule, and
/// writes any newly-earned badges back, keeping the threshold arithmetic
/// independent of Firestore and trivially testable.
///
/// Idempotency is keyed on each milestone's stable [config.BadgeMilestone.id]:
/// a milestone whose id already appears in the recorded badges is never
/// re-awarded, so replaying the evaluation (an offline resync, a second device,
/// or simply the same day's activity) adds nothing. A milestone is crossed when
/// the progress value is greater than or equal to its threshold.
abstract final class BadgeAwarder {
  const BadgeAwarder._();

  /// The badges to newly award for a learner at [progressValue], given the
  /// configured [milestones] and the ids of milestones already recorded in
  /// [awardedMilestoneIds].
  ///
  /// A milestone contributes a badge when both:
  /// - it is *crossed* — `progressValue >= threshold`, and
  /// - it is *not already recorded* — its id is absent from
  ///   [awardedMilestoneIds].
  ///
  /// The returned badges are ordered by ascending threshold (lowest milestone
  /// first) and stamped with [awardedAt] when provided. Milestones with a
  /// duplicate id in the config are collapsed to the first occurrence so a
  /// misconfigured duplicate cannot yield two badges for one milestone.
  static List<Badge> badgesToAward({
    required int progressValue,
    required List<config.BadgeMilestone> milestones,
    required Set<String> awardedMilestoneIds,
    DateTime? awardedAt,
  }) {
    final ordered = [...milestones]
      ..sort((a, b) => a.threshold.compareTo(b.threshold));

    final seenIds = <String>{};
    final result = <Badge>[];
    for (final milestone in ordered) {
      // Collapse duplicate milestone ids from config to the first occurrence.
      if (!seenIds.add(milestone.id)) continue;
      // Not crossed yet.
      if (progressValue < milestone.threshold) continue;
      // Already recorded: idempotent no-op.
      if (awardedMilestoneIds.contains(milestone.id)) continue;
      result.add(
        Badge(
          tier: _domainTier(milestone.tier),
          milestone: milestone.id,
          awardedAt: awardedAt,
        ),
      );
    }
    return List.unmodifiable(result);
  }

  /// Maps the config-layer [config.BadgeTier] to the progress domain's
  /// [BadgeTier]. The two enums are kept separate so the domain does not have
  /// to depend on the config package's identity, but they carry the same
  /// Bronze/Silver/Gold set.
  static BadgeTier _domainTier(config.BadgeTier tier) {
    switch (tier) {
      case config.BadgeTier.bronze:
        return BadgeTier.bronze;
      case config.BadgeTier.silver:
        return BadgeTier.silver;
      case config.BadgeTier.gold:
        return BadgeTier.gold;
    }
  }
}

/// The outcome of evaluating badges for a learner: the full set of badges that
/// should exist (existing + newly awarded) plus just the [newlyAwarded] ones,
/// so a caller can both persist the merged list and react to fresh awards
/// (e.g. show a celebration) without recomputing. Purely a value aggregate
/// over [BadgeAwarder]; it holds no I/O.
@immutable
class BadgeEvaluation {
  const BadgeEvaluation({
    required this.existing,
    required this.newlyAwarded,
  });

  /// The badges already recorded before this evaluation.
  final List<Badge> existing;

  /// The badges newly earned by this evaluation (crossed and not yet
  /// recorded); empty when nothing new was earned.
  final List<Badge> newlyAwarded;

  /// Whether this evaluation produced at least one new badge.
  bool get hasNewAwards => newlyAwarded.isNotEmpty;

  /// The complete badge list to persist: existing badges followed by the
  /// newly-awarded ones (lowest milestone first among the new ones).
  List<Badge> get merged =>
      List.unmodifiable([...existing, ...newlyAwarded]);
}
