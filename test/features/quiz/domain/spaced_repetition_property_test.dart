// Property-based tests for the pure spaced-repetition scheduling core in
// `SpacedRepetition`.
//
// Property 13: Every wrong answer enters the review queue. For any item id and
// any scheduling moment, a wrong answer always produces a review entry pinned
// at the shortest interval (`intervalIndex 0`), due `INTERVALS_DAYS[0]` days
// out, and marked `wrong` — whether the miss comes from a fresh quiz answer
// (`onWrongAnswer`) or from a wrong review answer on an already-advanced item
// (`onReviewAnswer`). (Validates: Requirements 6.3)
//
// Property 14: Only due review items are presented. For any bag of review
// items and any "now", `dueItems` returns exactly the items whose `dueDate`
// has passed (or is null/unscheduled), never a not-yet-due item, and orders
// the survivors earliest-due first. (Validates: Requirements 6.4)
//
// Property 15: Correct review answers lengthen the interval. For any item at
// any rung on the ladder, a correct review answer advances it to a strictly
// longer interval — strictly longer below the top rung, and clamped to stay
// equal (never shorter, never out of range) at the final rung. (Validates:
// Requirements 6.5)
//
// The project has no dedicated property-testing package, so these tests follow
// the convention of the other `*_property_test.dart` files: drive many (100+)
// randomly generated inputs through the real pure domain core. Testing at the
// `SpacedRepetition` level keeps every iteration deterministic (no I/O). A
// fixed seed keeps iterations reproducible; a failing case prints the
// generated scenario.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/quiz/domain/quiz.dart';

/// A randomly generated review item spread across the full input space: any
/// ladder rung, and a due date anywhere in a wide window around a fixed epoch
/// (plus an occasional unscheduled, null-dueDate item).
ReviewItem _generateItem(Random random, int index, DateTime epoch) {
  // ~1 in 8 items are unscheduled (null dueDate) to exercise that branch.
  final unscheduled = random.nextInt(8) == 0;
  // Due date from 60 days before to 60 days after the epoch.
  final dayOffset = random.nextInt(121) - 60;
  return ReviewItem(
    itemId: 'q$index',
    intervalIndex: random.nextInt(INTERVALS_DAYS.length),
    dueDate: unscheduled ? null : epoch.add(Duration(days: dayOffset)),
    lastResult: random.nextBool() ? ReviewResult.correct : ReviewResult.wrong,
  );
}

/// A random moment within the generation window used for scheduling calls.
DateTime _generateNow(Random random, DateTime epoch) {
  final dayOffset = random.nextInt(121) - 60;
  final secondOffset = random.nextInt(86400);
  return epoch.add(Duration(days: dayOffset, seconds: secondOffset));
}

void main() {
  const iterations = 200;
  final epoch = DateTime.utc(2024, 6, 1);

  test(
    'Property 13: every wrong answer enters the review queue at the shortest '
    'interval',
    () {
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(6301);

      for (var i = 0; i < iterations; i++) {
        final now = _generateNow(random, epoch);
        final expectedDue = now.add(Duration(days: INTERVALS_DAYS[0]));

        // Path A: a fresh wrong quiz answer enters the queue.
        final fresh = SpacedRepetition.onWrongAnswer(
          itemId: 'q$i',
          now: now,
        );
        final freshReason = 'iteration $i (fresh), now=$now, item=$fresh';
        expect(fresh.itemId, 'q$i', reason: freshReason);
        expect(fresh.intervalIndex, 0, reason: freshReason);
        expect(fresh.lastResult, ReviewResult.wrong, reason: freshReason);
        expect(fresh.dueDate, expectedDue, reason: freshReason);

        // Path B: a wrong review answer on an item at any rung resets it back
        // into the queue at the shortest interval.
        final existing = _generateItem(random, i, epoch);
        final reset = SpacedRepetition.onReviewAnswer(
          item: existing,
          correct: false,
          now: now,
        );
        final resetReason =
            'iteration $i (reset), now=$now, from=$existing, to=$reset';
        expect(reset.itemId, existing.itemId, reason: resetReason);
        expect(reset.intervalIndex, 0, reason: resetReason);
        expect(reset.lastResult, ReviewResult.wrong, reason: resetReason);
        expect(reset.dueDate, expectedDue, reason: resetReason);
        expect(reset.isDueAt(reset.dueDate!), isTrue, reason: resetReason);
      }
    },
  );

  test(
    'Property 14: dueItems presents only due items, ordered earliest-due '
    'first',
    () {
      final random = Random(6401);

      for (var i = 0; i < iterations; i++) {
        final now = _generateNow(random, epoch);
        final count = random.nextInt(12); // 0..11 items, including empty bags.
        final items = <ReviewItem>[
          for (var j = 0; j < count; j++) _generateItem(random, j, epoch),
        ];

        final due = SpacedRepetition.dueItems(items, now);
        final reason = 'iteration $i, now=$now, items=$items, due=$due';

        // Only due items survive, and every due item in the input is present.
        final expectedDue =
            items.where((item) => item.isDueAt(now)).toList();
        expect(due.length, expectedDue.length, reason: reason);
        for (final item in due) {
          expect(item.isDueAt(now), isTrue, reason: reason);
        }
        // No not-yet-due item ever leaks through.
        for (final item in items) {
          if (!item.isDueAt(now)) {
            expect(due.contains(item), isFalse, reason: reason);
          }
        }

        // The survivors are ordered earliest-due first; a null dueDate
        // (unscheduled, treated as immediately due) sorts ahead of any date.
        for (var k = 1; k < due.length; k++) {
          final prev = due[k - 1].dueDate;
          final curr = due[k].dueDate;
          if (prev == null) {
            // A null is allowed before anything (another null or a date).
            continue;
          }
          // Once a dated item appears, no later item may be a null.
          expect(curr, isNotNull, reason: reason);
          expect(
            prev.isAfter(curr!),
            isFalse,
            reason: reason,
          );
        }
      }
    },
  );

  test(
    'Property 15: a correct review answer always advances to a strictly '
    'longer interval (clamped at the top rung)',
    () {
      final random = Random(6501);

      for (var i = 0; i < iterations; i++) {
        final now = _generateNow(random, epoch);
        final item = _generateItem(random, i, epoch);
        final advanced = SpacedRepetition.onReviewAnswer(
          item: item,
          correct: true,
          now: now,
        );
        final reason =
            'iteration $i, now=$now, from=$item, to=$advanced';

        final beforeDays =
            SpacedRepetition.daysForIndex(item.intervalIndex);
        final afterDays =
            SpacedRepetition.daysForIndex(advanced.intervalIndex);

        // The index stays within the valid ladder range.
        expect(
          advanced.intervalIndex,
          inInclusiveRange(0, SpacedRepetition.lastIntervalIndex),
          reason: reason,
        );
        // A correct answer is recorded and the due date matches the new rung.
        expect(advanced.lastResult, ReviewResult.correct, reason: reason);
        expect(
          advanced.dueDate,
          now.add(Duration(days: afterDays)),
          reason: reason,
        );

        if (item.intervalIndex < SpacedRepetition.lastIntervalIndex) {
          // Below the top rung: the index steps up by one and the interval
          // becomes strictly longer.
          expect(
            advanced.intervalIndex,
            item.intervalIndex + 1,
            reason: reason,
          );
          expect(afterDays, greaterThan(beforeDays), reason: reason);
        } else {
          // At the top rung: clamped — stays equal, never shorter, never out
          // of range.
          expect(
            advanced.intervalIndex,
            SpacedRepetition.lastIntervalIndex,
            reason: reason,
          );
          expect(afterDays, equals(beforeDays), reason: reason);
        }
        // In all cases the interval never shrinks on a correct answer.
        expect(afterDays, greaterThanOrEqualTo(beforeDays), reason: reason);
      }
    },
  );
}
