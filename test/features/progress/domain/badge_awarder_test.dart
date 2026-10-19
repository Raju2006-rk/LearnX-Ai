// Unit tests for the pure badge-awarding rule BadgeAwarder.badgesToAward:
// milestones are awarded when crossed (progress >= threshold), awarded once
// (idempotent per milestone id), mapped to the matching Bronze/Silver/Gold
// tier, and ordered lowest-threshold first. (Requirement 7.3)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/config/remote_config.dart' as config;
import 'package:learnx/features/progress/domain/badge.dart';
import 'package:learnx/features/progress/domain/badge_awarder.dart';

void main() {
  // Bronze at 3, Silver at 7, Gold at 15 (the built-in default ladder),
  // deliberately listed out of order to exercise the rule's sorting.
  const milestones = <config.BadgeMilestone>[
    config.BadgeMilestone(
      id: 'streak-15',
      tier: config.BadgeTier.gold,
      threshold: 15,
    ),
    config.BadgeMilestone(
      id: 'streak-3',
      tier: config.BadgeTier.bronze,
      threshold: 3,
    ),
    config.BadgeMilestone(
      id: 'streak-7',
      tier: config.BadgeTier.silver,
      threshold: 7,
    ),
  ];

  List<Badge> award(
    int progressValue, {
    Set<String> awarded = const {},
    DateTime? at,
  }) => BadgeAwarder.badgesToAward(
    progressValue: progressValue,
    milestones: milestones,
    awardedMilestoneIds: awarded,
    awardedAt: at,
  );

  group('BadgeAwarder.badgesToAward thresholds', () {
    test('awards nothing below the lowest threshold', () {
      expect(award(2), isEmpty);
    });

    test('awards Bronze exactly at its threshold (inclusive)', () {
      final badges = award(3);
      expect(badges.map((b) => b.tier), [BadgeTier.bronze]);
      expect(badges.single.milestone, 'streak-3');
    });

    test('awards all crossed milestones, lowest threshold first', () {
      final badges = award(15);
      expect(badges.map((b) => b.tier), [
        BadgeTier.bronze,
        BadgeTier.silver,
        BadgeTier.gold,
      ]);
      expect(badges.map((b) => b.milestone), [
        'streak-3',
        'streak-7',
        'streak-15',
      ]);
    });

    test('awards Bronze and Silver but not Gold between thresholds', () {
      final badges = award(9);
      expect(badges.map((b) => b.milestone), ['streak-3', 'streak-7']);
    });

    test('stamps awarded badges with the supplied timestamp', () {
      final at = DateTime.utc(2024, 3, 11, 9, 30);
      final badges = award(3, at: at);
      expect(badges.single.awardedAt, at);
    });
  });

  group('BadgeAwarder.badgesToAward idempotency', () {
    test('skips a milestone already recorded', () {
      final badges = award(7, awarded: {'streak-3'});
      // Bronze already recorded: only Silver is newly awarded.
      expect(badges.map((b) => b.milestone), ['streak-7']);
    });

    test('awards nothing when every crossed milestone is already recorded', () {
      final badges = award(15, awarded: {'streak-3', 'streak-7', 'streak-15'});
      expect(badges, isEmpty);
    });

    test('re-running on an unchanged value awards nothing the second time', () {
      final first = award(7);
      final firstIds = first.map((b) => b.milestone).whereType<String>().toSet();
      final second = award(7, awarded: firstIds);
      expect(first.map((b) => b.milestone), ['streak-3', 'streak-7']);
      expect(second, isEmpty);
    });
  });

  group('BadgeAwarder.badgesToAward robustness', () {
    test('collapses duplicate milestone ids to a single badge', () {
      const dupes = <config.BadgeMilestone>[
        config.BadgeMilestone(
          id: 'streak-3',
          tier: config.BadgeTier.bronze,
          threshold: 3,
        ),
        config.BadgeMilestone(
          id: 'streak-3',
          tier: config.BadgeTier.bronze,
          threshold: 3,
        ),
      ];
      final badges = BadgeAwarder.badgesToAward(
        progressValue: 5,
        milestones: dupes,
        awardedMilestoneIds: const {},
      );
      expect(badges.length, 1);
      expect(badges.single.milestone, 'streak-3');
    });

    test('returns an unmodifiable list', () {
      final badges = award(3);
      expect(() => badges.add(badges.first), throwsUnsupportedError);
    });

    test('awards nothing when there are no configured milestones', () {
      final badges = BadgeAwarder.badgesToAward(
        progressValue: 100,
        milestones: const [],
        awardedMilestoneIds: const {},
      );
      expect(badges, isEmpty);
    });
  });

  group('BadgeEvaluation', () {
    test('merged is existing followed by newly awarded', () {
      const existing = Badge(tier: BadgeTier.bronze, milestone: 'streak-3');
      const fresh = Badge(tier: BadgeTier.silver, milestone: 'streak-7');
      const evaluation = BadgeEvaluation(
        existing: [existing],
        newlyAwarded: [fresh],
      );
      expect(evaluation.hasNewAwards, isTrue);
      expect(evaluation.merged, [existing, fresh]);
    });

    test('hasNewAwards is false when nothing was newly awarded', () {
      const evaluation = BadgeEvaluation(existing: [], newlyAwarded: []);
      expect(evaluation.hasNewAwards, isFalse);
      expect(evaluation.merged, isEmpty);
    });
  });
}
