// Property-based tests for the pure progress/reward domain cores:
// `StreakComputation.onQualifyingActivity` and `BadgeAwarder.badgesToAward`.
//
// Property 16: Longest streak dominates current streak. After any sequence of
// `onQualifyingActivity` calls, the resulting state always satisfies
// `longest >= current`. (Validates: Requirements 7.1)
//
// Property 19: Current streak equals the current consecutive-day run. For any
// generated sequence of calendar days fed through `onQualifyingActivity`, the
// resulting `current` equals the length of the trailing run of consecutive
// days ending at the last applied day. (Validates: Requirements 3.7, 7.5)
//
// Property 17: Badge award matches milestone thresholds. For any progress
// value, set of configured milestones, and set of already-awarded milestone
// ids, `badgesToAward` returns exactly the milestones whose
// `threshold <= progressValue` and whose id is not already awarded. (Validates:
// Requirements 7.3)
//
// The project has no dedicated property-testing package, so these tests follow
// the convention of the other `*_property_test.dart` files: drive many (100+)
// randomly generated inputs through the real pure domain core, keeping every
// iteration deterministic (no I/O). A fixed seed keeps iterations reproducible;
// a failing case prints the generated scenario.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/config/remote_config.dart' as config;
import 'package:learnx/features/progress/domain/badge_awarder.dart';
import 'package:learnx/features/progress/domain/streak.dart';

/// Formats a [DateTime] as the `"YYYY-MM-DD"` string the streak rule consumes.
String _ymd(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Generates a sequence of distinct-or-repeated calendar days starting from
/// [epoch]. Each next day steps forward by 0 (same day), 1 (consecutive), or a
/// larger gap, so the sequence exercises every transition the streak rule
/// handles. Returns the `"YYYY-MM-DD"` strings in application order.
List<String> _generateDaySequence(Random random, DateTime epoch, int length) {
  final dates = <String>[];
  var day = epoch;
  for (var i = 0; i < length; i++) {
    if (i == 0) {
      day = epoch;
    } else {
      // Step: ~1/5 same day, ~2/5 consecutive, ~2/5 a multi-day gap (2..6).
      final roll = random.nextInt(5);
      final step = switch (roll) {
        0 => 0, // same day
        1 || 2 => 1, // consecutive day
        _ => 2 + random.nextInt(5), // gap of 2..6 days
      };
      day = day.add(Duration(days: step));
    }
    dates.add(_ymd(day));
  }
  return dates;
}

/// Computes the expected current streak directly from a day sequence: the
/// length of the trailing run of consecutive calendar days ending at the last
/// day, treating repeated same-day entries as a single day. This is an
/// independent reference implementation used only by the property check.
int _expectedCurrentRun(List<String> dates) {
  if (dates.isEmpty) return 0;
  // Collapse consecutive duplicates (same-day repeats don't change the run).
  final parsed = dates.map(DateTime.parse).toList();
  var run = 1;
  for (var i = parsed.length - 1; i > 0; i--) {
    final curr = DateTime.utc(
      parsed[i].year,
      parsed[i].month,
      parsed[i].day,
    );
    final prev = DateTime.utc(
      parsed[i - 1].year,
      parsed[i - 1].month,
      parsed[i - 1].day,
    );
    final diff = curr.difference(prev).inDays;
    if (diff == 0) {
      // Same day: does not extend the run, keep scanning earlier entries.
      continue;
    } else if (diff == 1) {
      run += 1;
    } else {
      // A gap breaks the trailing run.
      break;
    }
  }
  return run;
}

/// A small pool of milestone ids to draw from when generating configs and
/// already-awarded sets, so overlaps between the two actually occur.
const _idPool = <String>[
  'streak-3',
  'streak-7',
  'streak-15',
  'streak-30',
  'streak-50',
  'streak-100',
];

config.BadgeTier _randomTier(Random random) =>
    config.BadgeTier.values[random.nextInt(config.BadgeTier.values.length)];

/// Generates a random list of milestones drawn from [_idPool] with thresholds
/// spread across a window that straddles typical progress values, so both
/// crossed and not-yet-crossed milestones appear.
List<config.BadgeMilestone> _generateMilestones(Random random) {
  final count = random.nextInt(_idPool.length + 1); // 0..pool size
  final shuffled = [..._idPool]..shuffle(random);
  return [
    for (var i = 0; i < count; i++)
      config.BadgeMilestone(
        id: shuffled[i],
        tier: _randomTier(random),
        threshold: random.nextInt(60), // 0..59
      ),
  ];
}

void main() {
  const iterations = 200;

  test(
    'Property 16: longest always dominates current across any activity '
    'sequence',
    () {
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(1601);
      final epoch = DateTime.utc(2024, 1, 1);

      for (var i = 0; i < iterations; i++) {
        final length = 1 + random.nextInt(20); // 1..20 activities
        final dates = _generateDaySequence(random, epoch, length);

        var state = StreakState.initial;
        for (final date in dates) {
          state = StreakComputation.onQualifyingActivity(state, date);
          // The invariant must hold after every single step, not just at end.
          expect(
            state.longest,
            greaterThanOrEqualTo(state.current),
            reason: 'iteration $i, dates=$dates, state=$state',
          );
        }
      }
    },
  );

  test(
    'Property 19: current streak equals the trailing consecutive-day run',
    () {
      final random = Random(1901);
      final epoch = DateTime.utc(2024, 1, 1);

      for (var i = 0; i < iterations; i++) {
        final length = 1 + random.nextInt(20); // 1..20 activities
        final dates = _generateDaySequence(random, epoch, length);

        var state = StreakState.initial;
        for (final date in dates) {
          state = StreakComputation.onQualifyingActivity(state, date);
        }

        final expected = _expectedCurrentRun(dates);
        expect(
          state.current,
          expected,
          reason: 'iteration $i, dates=$dates, state=$state, '
              'expectedRun=$expected',
        );
        // The last applied day must be the recorded last-activity date.
        expect(
          state.lastActivityDate,
          dates.last,
          reason: 'iteration $i, dates=$dates, state=$state',
        );
      }
    },
  );

  test(
    'Property 17: badgesToAward returns exactly the crossed, not-yet-awarded '
    'milestones',
    () {
      final random = Random(1701);

      for (var i = 0; i < iterations; i++) {
        final progressValue = random.nextInt(60); // 0..59
        final milestones = _generateMilestones(random);
        // A random subset of the id pool treated as already recorded.
        final awarded = <String>{
          for (final id in _idPool)
            if (random.nextBool()) id,
        };

        final result = BadgeAwarder.badgesToAward(
          progressValue: progressValue,
          milestones: milestones,
          awardedMilestoneIds: awarded,
        );

        final reason = 'iteration $i, progress=$progressValue, '
            'milestones=$milestones, awarded=$awarded, result=$result';

        // The independent reference set: first-occurrence-per-id milestones
        // that are crossed (threshold <= progress) and not already awarded.
        final seen = <String>{};
        final expected = <config.BadgeMilestone>[];
        for (final m in [...milestones]
          ..sort((a, b) => a.threshold.compareTo(b.threshold))) {
          if (!seen.add(m.id)) continue; // collapse duplicate ids
          if (m.threshold > progressValue) continue; // not crossed
          if (awarded.contains(m.id)) continue; // already recorded
          expected.add(m);
        }

        // Same count, same milestone ids, in ascending-threshold order.
        expect(result.length, expected.length, reason: reason);
        for (var k = 0; k < result.length; k++) {
          expect(result[k].milestone, expected[k].id, reason: reason);
        }

        // No awarded badge is for a not-crossed or already-recorded milestone.
        final thresholdById = {for (final m in milestones) m.id: m.threshold};
        for (final badge in result) {
          final id = badge.milestone;
          expect(id, isNotNull, reason: reason);
          expect(awarded.contains(id), isFalse, reason: reason);
          expect(
            thresholdById[id],
            lessThanOrEqualTo(progressValue),
            reason: reason,
          );
        }

        // Every crossed, not-yet-awarded, first-occurrence milestone is
        // present in the output (nothing eligible is dropped).
        final resultIds = result.map((b) => b.milestone).toSet();
        for (final m in expected) {
          expect(resultIds.contains(m.id), isTrue, reason: reason);
        }
      }
    },
  );
}
