// Unit tests for the Badge / BadgeTier domain types: wire parsing, DTO
// round-tripping, and dropping an unrecognized tier. (Requirement 7.3)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/progress/domain/badge.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

void main() {
  group('BadgeTier.fromWire', () {
    test('parses each known tier', () {
      expect(BadgeTier.fromWire('bronze'), BadgeTier.bronze);
      expect(BadgeTier.fromWire('silver'), BadgeTier.silver);
      expect(BadgeTier.fromWire('gold'), BadgeTier.gold);
    });

    test('returns null for missing or unknown values', () {
      expect(BadgeTier.fromWire(null), isNull);
      expect(BadgeTier.fromWire('platinum'), isNull);
      expect(BadgeTier.fromWire(''), isNull);
    });
  });

  group('Badge.fromDto', () {
    test('builds a badge from a valid DTO', () {
      final awardedAt = DateTime.utc(2024, 3, 10);
      final badge = Badge.fromDto(
        BadgeDto(tier: 'silver', milestone: 'streak-7', awardedAt: awardedAt),
      );

      expect(badge, isNotNull);
      expect(badge!.tier, BadgeTier.silver);
      expect(badge.milestone, 'streak-7');
      expect(badge.awardedAt, awardedAt);
    });

    test('returns null when the stored tier is unrecognized', () {
      expect(Badge.fromDto(const BadgeDto(tier: 'mystery')), isNull);
    });
  });

  test('round-trips through its DTO', () {
    final awardedAt = DateTime.utc(2024, 3, 10);
    const original = Badge(tier: BadgeTier.gold, milestone: 'streak-30');
    final withDate = Badge(
      tier: original.tier,
      milestone: original.milestone,
      awardedAt: awardedAt,
    );

    final restored = Badge.fromDto(withDate.toDto());

    expect(restored, withDate);
  });
}
