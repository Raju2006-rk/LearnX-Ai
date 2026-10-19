// Unit tests for the quiz domain: question scoring, review-item mapping, and
// the spaced-repetition interval ladder transitions.
// (Requirements 6.1, 6.3, 6.4, 6.5)

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/quiz/domain/quiz.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

void main() {
  group('INTERVALS_DAYS ladder', () {
    test('matches the design ladder', () {
      expect(INTERVALS_DAYS, <int>[1, 3, 7, 16, 35]);
    });

    test('is strictly increasing so advancing always lengthens the interval', () {
      for (var i = 1; i < INTERVALS_DAYS.length; i++) {
        expect(INTERVALS_DAYS[i], greaterThan(INTERVALS_DAYS[i - 1]));
      }
    });
  });

  group('QuestionType.fromWire', () {
    test('parses the authored type strings', () {
      expect(QuestionType.fromWire('fill_blank'), QuestionType.fillBlank);
      expect(QuestionType.fromWire('choose_word'), QuestionType.chooseWord);
    });

    test('defaults to fillBlank for unknown or missing values', () {
      expect(QuestionType.fromWire(null), QuestionType.fillBlank);
      expect(QuestionType.fromWire('mystery'), QuestionType.fillBlank);
    });
  });

  group('Question', () {
    test('maps from a DTO with its document id', () {
      final dto = QuizItemDto(
        type: 'choose_word',
        prompt: 'Pick the verb',
        options: const ['run', 'blue'],
        answer: 'run',
        tags: const ['verbs'],
      );

      final q = Question.fromDto('q1', dto);

      expect(q.id, 'q1');
      expect(q.type, QuestionType.chooseWord);
      expect(q.prompt, 'Pick the verb');
      expect(q.options, const ['run', 'blue']);
      expect(q.answer, 'run');
      expect(q.tags, const ['verbs']);
    });

    test('scores answers case-insensitively and trims whitespace', () {
      const q = Question(
        id: 'q1',
        type: QuestionType.fillBlank,
        prompt: 'The sky is ___',
        answer: 'blue',
      );

      expect(q.isCorrect('blue'), isTrue);
      expect(q.isCorrect('  BLUE '), isTrue);
      expect(q.isCorrect('green'), isFalse);
    });

    test('Answer.score records the question id, response, and correctness', () {
      const q = Question(
        id: 'q1',
        type: QuestionType.fillBlank,
        prompt: 'The sky is ___',
        answer: 'blue',
      );

      final right = Answer.score(q, 'Blue');
      final wrong = Answer.score(q, 'red');

      expect(right.questionId, 'q1');
      expect(right.response, 'Blue');
      expect(right.correct, isTrue);
      expect(wrong.correct, isFalse);
    });
  });

  group('ReviewItem', () {
    test('clamps a corrupt intervalIndex into the ladder range', () {
      final high = ReviewItem.fromDto(
        const ReviewQueueItemDto(itemId: 'q1', intervalIndex: 99),
      );
      final low = ReviewItem.fromDto(
        const ReviewQueueItemDto(itemId: 'q2', intervalIndex: -5),
      );

      expect(high.intervalIndex, INTERVALS_DAYS.length - 1);
      expect(low.intervalIndex, 0);
    });

    test('isDueAt treats a past or null dueDate as due', () {
      final now = DateTime.utc(2024, 1, 10);
      final past = ReviewItem(
        itemId: 'q1',
        intervalIndex: 0,
        dueDate: DateTime.utc(2024, 1, 9),
      );
      final future = ReviewItem(
        itemId: 'q2',
        intervalIndex: 0,
        dueDate: DateTime.utc(2024, 1, 11),
      );
      const unscheduled = ReviewItem(itemId: 'q3', intervalIndex: 0);

      expect(past.isDueAt(now), isTrue);
      expect(future.isDueAt(now), isFalse);
      expect(unscheduled.isDueAt(now), isTrue);
    });

    test('maps lastResult to and from its wire value', () {
      final item = ReviewItem.fromDto(
        const ReviewQueueItemDto(
          itemId: 'q1',
          intervalIndex: 1,
          lastResult: 'wrong',
        ),
      );
      expect(item.lastResult, ReviewResult.wrong);
      expect(item.toDto().lastResult, 'wrong');
    });
  });

  group('SpacedRepetition', () {
    final now = DateTime.utc(2024, 6, 1);

    test('onWrongAnswer schedules at the shortest interval', () {
      final item = SpacedRepetition.onWrongAnswer(itemId: 'q1', now: now);

      expect(item.itemId, 'q1');
      expect(item.intervalIndex, 0);
      expect(item.lastResult, ReviewResult.wrong);
      expect(item.dueDate, now.add(const Duration(days: 1)));
    });

    test('a correct review answer advances to a strictly longer interval', () {
      var item = SpacedRepetition.onWrongAnswer(itemId: 'q1', now: now);

      for (var i = 1; i < INTERVALS_DAYS.length; i++) {
        final previousIndex = item.intervalIndex;
        item = SpacedRepetition.onReviewAnswer(
          item: item,
          correct: true,
          now: now,
        );
        expect(item.intervalIndex, previousIndex + 1);
        expect(
          SpacedRepetition.daysForIndex(item.intervalIndex),
          greaterThan(SpacedRepetition.daysForIndex(previousIndex)),
        );
        expect(item.lastResult, ReviewResult.correct);
      }
    });

    test('correct answers clamp at the final rung without going out of range', () {
      var item = ReviewItem(
        itemId: 'q1',
        intervalIndex: SpacedRepetition.lastIntervalIndex,
        dueDate: now,
      );
      item = SpacedRepetition.onReviewAnswer(
        item: item,
        correct: true,
        now: now,
      );
      expect(item.intervalIndex, SpacedRepetition.lastIntervalIndex);
      expect(
        item.dueDate,
        now.add(Duration(days: INTERVALS_DAYS.last)),
      );
    });

    test('a wrong review answer resets to the shortest interval', () {
      final advanced = ReviewItem(
        itemId: 'q1',
        intervalIndex: 3,
        dueDate: now,
      );
      final reset = SpacedRepetition.onReviewAnswer(
        item: advanced,
        correct: false,
        now: now,
      );
      expect(reset.intervalIndex, 0);
      expect(reset.lastResult, ReviewResult.wrong);
      expect(reset.dueDate, now.add(const Duration(days: 1)));
    });

    test('dueItems returns only due entries ordered by due date', () {
      final items = <ReviewItem>[
        ReviewItem(
          itemId: 'later',
          intervalIndex: 2,
          dueDate: DateTime.utc(2024, 6, 3),
        ),
        ReviewItem(
          itemId: 'future',
          intervalIndex: 0,
          dueDate: DateTime.utc(2024, 6, 10),
        ),
        ReviewItem(
          itemId: 'earlier',
          intervalIndex: 1,
          dueDate: DateTime.utc(2024, 6, 1),
        ),
      ];

      final due = SpacedRepetition.dueItems(items, DateTime.utc(2024, 6, 5));

      expect(due.map((i) => i.itemId), <String>['earlier', 'later']);
    });
  });
}
