// Unit tests for QuizRepository and ReviewQueueDataSource: loading the
// authored quizItems bank, reading/upserting the per-user reviewQueue, and
// surfacing only due review items. (Requirements 6.1, 6.3, 6.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/quiz/data/quiz_repository.dart';
import 'package:learnx/features/quiz/data/review_queue_data_source.dart';
import 'package:learnx/features/quiz/domain/quiz.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReviewQueueDataSource reviewQueue;
  late QuizRepository repository;

  const uid = 'user-123';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    reviewQueue = ReviewQueueDataSource(firestore: firestore);
    repository = QuizRepository(firestore: firestore, reviewQueue: reviewQueue);
  });

  Future<void> seedQuizItem(
    String id, {
    String type = 'fill_blank',
    String prompt = 'prompt',
    List<String> options = const [],
    String answer = 'answer',
    List<String> tags = const [],
  }) async {
    await firestore.doc(FirestorePaths.quizItemDoc(id)).set(<String, dynamic>{
      'type': type,
      'prompt': prompt,
      'options': options,
      'answer': answer,
      'tags': tags,
    });
  }

  group('loadQuizItems', () {
    test('loads the authored bank as Questions keyed by document id', () async {
      await seedQuizItem(
        'q1',
        type: 'choose_word',
        prompt: 'Pick the verb',
        options: const ['run', 'blue'],
        answer: 'run',
        tags: const ['verbs'],
      );

      final result = await repository.loadQuizItems();

      expect(result.isSuccess, isTrue);
      final questions = result.valueOrNull!;
      expect(questions, hasLength(1));
      expect(questions.single.id, 'q1');
      expect(questions.single.type, QuestionType.chooseWord);
      expect(questions.single.answer, 'run');
      expect(questions.single.options, const ['run', 'blue']);
    });

    test('an empty bank succeeds with an empty list (not a failure)', () async {
      final result = await repository.loadQuizItems();

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });
  });

  group('review queue upsert + read', () {
    test('upsert then read round-trips a review item', () async {
      final item = SpacedRepetition.onWrongAnswer(
        itemId: 'q1',
        now: DateTime.utc(2024, 6, 1),
      );

      final upsertResult = await repository.upsertReviewItem(
        uid: uid,
        item: item,
      );
      expect(upsertResult.isSuccess, isTrue);

      final stored = await reviewQueue.read(uid, 'q1');
      expect(stored, isNotNull);
      expect(stored!.itemId, 'q1');
      expect(stored.intervalIndex, 0);
      expect(stored.lastResult, ReviewResult.wrong);
      // updatedAt is written as a server timestamp.
      expect(stored.updatedAt, isNotNull);
    });

    test('upsert merges rather than clobbering the document', () async {
      final first = SpacedRepetition.onWrongAnswer(
        itemId: 'q1',
        now: DateTime.utc(2024, 6, 1),
      );
      await repository.upsertReviewItem(uid: uid, item: first);

      final stored = (await reviewQueue.read(uid, 'q1'))!;
      final advanced = SpacedRepetition.onReviewAnswer(
        item: stored,
        correct: true,
        now: DateTime.utc(2024, 6, 2),
      );
      await repository.upsertReviewItem(uid: uid, item: advanced);

      final reread = (await reviewQueue.read(uid, 'q1'))!;
      expect(reread.intervalIndex, 1);
      expect(reread.lastResult, ReviewResult.correct);
    });
  });

  group('saveQuizSession', () {
    Future<Map<String, dynamic>?> readSession(String sessionId) async {
      final snap = await firestore
          .doc(FirestorePaths.quizSessionDoc(uid, sessionId))
          .get();
      return snap.data();
    }

    test('persists the earned result with a server updatedAt', () async {
      final result = await repository.saveQuizSession(
        uid: uid,
        sessionId: 's1',
        session: QuizSessionDto(
          startedAt: DateTime.utc(2024, 6, 1, 10),
          completedAt: DateTime.utc(2024, 6, 1, 10, 5),
          correctCount: 7,
          wrongCount: 3,
        ),
      );

      expect(result.isSuccess, isTrue);
      final data = await readSession('s1');
      expect(data?['correctCount'], 7);
      expect(data?['wrongCount'], 3);
      // updatedAt is written as a server timestamp for last-write-wins sync.
      expect(data?['updatedAt'], isNotNull);
    });

    test('merges rather than clobbering an existing session doc', () async {
      await firestore.doc(FirestorePaths.quizSessionDoc(uid, 's2')).set(
        <String, dynamic>{'note': 'kept'},
      );

      await repository.saveQuizSession(
        uid: uid,
        sessionId: 's2',
        session: const QuizSessionDto(correctCount: 1, wrongCount: 0),
      );

      final data = await readSession('s2');
      expect(data?['note'], 'kept');
      expect(data?['correctCount'], 1);
      expect(data?['updatedAt'], isNotNull);
    });
  });

  group('loadDueReviewItems', () {
    test('returns only due items ordered by due date', () async {
      await firestore
          .doc(FirestorePaths.reviewQueueDoc(uid, 'future'))
          .set(
            const ReviewItem(
              itemId: 'future',
              intervalIndex: 0,
            ).copyToMap(DateTime.utc(2024, 6, 20)),
          );
      await firestore
          .doc(FirestorePaths.reviewQueueDoc(uid, 'earlier'))
          .set(
            const ReviewItem(
              itemId: 'earlier',
              intervalIndex: 0,
            ).copyToMap(DateTime.utc(2024, 6, 1)),
          );
      await firestore
          .doc(FirestorePaths.reviewQueueDoc(uid, 'later'))
          .set(
            const ReviewItem(
              itemId: 'later',
              intervalIndex: 0,
            ).copyToMap(DateTime.utc(2024, 6, 3)),
          );

      final result = await repository.loadDueReviewItems(
        uid: uid,
        now: DateTime.utc(2024, 6, 5),
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull!.map((i) => i.itemId), <String>[
        'earlier',
        'later',
      ]);
    });

    test('an empty queue succeeds with an empty list', () async {
      final result = await repository.loadDueReviewItems(
        uid: uid,
        now: DateTime.utc(2024, 6, 5),
      );

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });
  });
}

/// Test helper: serialize a [ReviewItem] with an explicit due date into a
/// Firestore map (the production upsert uses a server timestamp for
/// `updatedAt`, which the fake does not advance, so tests set dueDate here).
extension on ReviewItem {
  Map<String, dynamic> copyToMap(DateTime dueDate) {
    return ReviewItem(
      itemId: itemId,
      intervalIndex: intervalIndex,
      dueDate: dueDate,
      lastResult: lastResult,
      updatedAt: updatedAt,
    ).toDto().toMap();
  }
}
