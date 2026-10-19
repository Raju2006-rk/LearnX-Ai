// Unit tests for ReviewQueueService: the application seam that wires the pure
// SpacedRepetition scheduling rules to the QuizRepository so the quiz flow can
// enter wrong answers at the shortest interval, surface only due items at quiz
// start, and advance/reset review items on review answers.
// (Requirements 6.3, 6.4, 6.5)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/quiz/application/review_queue_service.dart';
import 'package:learnx/features/quiz/data/quiz_repository.dart';
import 'package:learnx/features/quiz/data/review_queue_data_source.dart';
import 'package:learnx/features/quiz/domain/quiz.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late QuizRepository repository;
  late ReviewQueueService service;

  const uid = 'user-123';
  // A fixed clock so due-date math is deterministic.
  final now = DateTime.utc(2025, 1, 1, 12);

  setUp(() {
    firestore = FakeFirebaseFirestore();
    final reviewQueue = ReviewQueueDataSource(firestore: firestore);
    repository = QuizRepository(firestore: firestore, reviewQueue: reviewQueue);
    service = ReviewQueueService(repository: repository);
  });

  group('recordWrongAnswer', () {
    test(
      'enters a missed item at intervalIndex 0 due INTERVALS_DAYS[0] later',
      () async {
        final result = await service.recordWrongAnswer(
          uid: uid,
          itemId: 'q1',
          now: now,
        );

        expect(result.isSuccess, isTrue);
        final item = result.valueOrNull!;
        expect(item.itemId, 'q1');
        expect(item.intervalIndex, 0);
        expect(item.lastResult, ReviewResult.wrong);
        expect(item.dueDate, now.add(Duration(days: INTERVALS_DAYS[0])));

        // Persisted: a later due load at that moment surfaces it.
        final due = await service.loadDueItems(
          uid: uid,
          now: now.add(Duration(days: INTERVALS_DAYS[0])),
        );
        expect(due.valueOrNull!.map((i) => i.itemId), contains('q1'));
      },
    );

    test('a wrong answer on an advanced item resets it to the shortest '
        'interval', () async {
      // Advance an item to index 2 via two correct reviews.
      var item = (await service.recordWrongAnswer(
        uid: uid,
        itemId: 'q1',
        now: now,
      )).valueOrNull!;
      item = (await service.recordReviewAnswer(
        uid: uid,
        item: item,
        correct: true,
        now: now,
      )).valueOrNull!;
      item = (await service.recordReviewAnswer(
        uid: uid,
        item: item,
        correct: true,
        now: now,
      )).valueOrNull!;
      expect(item.intervalIndex, 2);

      // A fresh wrong answer resets back to 0.
      final reset = await service.recordWrongAnswer(
        uid: uid,
        itemId: 'q1',
        now: now,
      );
      expect(reset.valueOrNull!.intervalIndex, 0);
    });
  });

  group('loadDueItems', () {
    test('surfaces only items whose due date has passed, ordered by due date',
        () async {
      // q1 due in 1 day, q2 due in 7 days (index 2).
      await service.recordWrongAnswer(uid: uid, itemId: 'q1', now: now);
      final q2 = (await service.recordWrongAnswer(
        uid: uid,
        itemId: 'q2',
        now: now,
      )).valueOrNull!;
      await service.recordReviewAnswer(
        uid: uid,
        item: q2,
        correct: true,
        now: now,
      ); // q2 -> index 1, due in 3 days
      final q2b = (await repository.loadDueReviewItems(
        uid: uid,
        now: now.add(const Duration(days: 3)),
      )).valueOrNull!;
      // At day 2, only q1 (due day 1) is due; q2 (due day 3) is not.
      final dueDay2 = await service.loadDueItems(
        uid: uid,
        now: now.add(const Duration(days: 2)),
      );
      expect(dueDay2.valueOrNull!.map((i) => i.itemId), ['q1']);

      // q2b sanity: at day 3 q2 is due too.
      expect(q2b.map((i) => i.itemId), containsAll(<String>['q1', 'q2']));

      // Ordering: at day 4, q1 (day 1) sorts before q2 (day 3).
      final dueDay4 = await service.loadDueItems(
        uid: uid,
        now: now.add(const Duration(days: 4)),
      );
      expect(dueDay4.valueOrNull!.map((i) => i.itemId), ['q1', 'q2']);
    });
  });

  group('recordReviewAnswer', () {
    test('a correct review answer advances to a strictly longer interval, '
        'clamped at the final rung', () async {
      var item = (await service.recordWrongAnswer(
        uid: uid,
        itemId: 'q1',
        now: now,
      )).valueOrNull!;

      final seen = <int>[item.intervalIndex];
      for (var i = 0; i < INTERVALS_DAYS.length + 2; i++) {
        item = (await service.recordReviewAnswer(
          uid: uid,
          item: item,
          correct: true,
          now: now,
        )).valueOrNull!;
        // Each step is strictly longer until clamped at the last index.
        final prev = seen.last;
        final maxIndex = INTERVALS_DAYS.length - 1;
        if (prev < maxIndex) {
          expect(item.intervalIndex, greaterThan(prev));
        } else {
          expect(item.intervalIndex, maxIndex);
        }
        seen.add(item.intervalIndex);
      }
      expect(item.intervalIndex, INTERVALS_DAYS.length - 1);
      expect(item.lastResult, ReviewResult.correct);
      expect(item.dueDate,
          now.add(Duration(days: INTERVALS_DAYS[INTERVALS_DAYS.length - 1])));
    });

    test('a wrong review answer resets the item to the shortest interval',
        () async {
      var item = (await service.recordWrongAnswer(
        uid: uid,
        itemId: 'q1',
        now: now,
      )).valueOrNull!;
      item = (await service.recordReviewAnswer(
        uid: uid,
        item: item,
        correct: true,
        now: now,
      )).valueOrNull!;
      expect(item.intervalIndex, 1);

      final reset = await service.recordReviewAnswer(
        uid: uid,
        item: item,
        correct: false,
        now: now,
      );
      expect(reset.valueOrNull!.intervalIndex, 0);
      expect(reset.valueOrNull!.lastResult, ReviewResult.wrong);
      expect(reset.valueOrNull!.dueDate,
          now.add(Duration(days: INTERVALS_DAYS[0])));
    });
  });
}
