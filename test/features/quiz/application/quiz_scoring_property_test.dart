// Property-based test for quiz answer-count consistency.
//
// Property 12: Quiz answer counts are consistent. For any sequence of answers
// in a quiz session, the running correct and wrong tallies partition the
// answered questions (correctCount + wrongCount == answeredCount), the correct
// tally always equals the number of answers scored correct, and when the
// session completes every question has been answered
// (answeredCount == totalCount). (Validates: Requirements 6.2)
//
// The project has no dedicated property-testing package, so this test follows
// the convention of `learning_path_property_test.dart` /
// `placement_property_test.dart`: drive many (200+) randomly generated
// sessions through the real `QuizController` (and `Answer.score` at the domain
// level) and assert the invariant after every answer. A fixed seed keeps
// iterations reproducible; a failing case prints the generated scenario.

import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/network/connectivity.dart';
import 'package:learnx/features/quiz/application/quiz_controller.dart';
import 'package:learnx/features/quiz/domain/quiz.dart';

/// A randomly generated quiz: the authored question bank plus the response the
/// learner will type for each question, carried together so a failing
/// iteration can print the scenario.
class _Scenario {
  const _Scenario({required this.questions, required this.responses});

  /// The seeded quiz items, in presentation order.
  final List<Question> questions;

  /// The learner's response to each question, aligned with [questions] by
  /// index. May be the exact answer, a case/whitespace variant of it, or an
  /// arbitrary wrong string.
  final List<String> responses;

  /// The number of responses that score correct against their question, the
  /// independent oracle the controller's [QuizState.correctCount] must match.
  int get expectedCorrect {
    var count = 0;
    for (var i = 0; i < questions.length; i++) {
      if (questions[i].isCorrect(responses[i])) count++;
    }
    return count;
  }

  @override
  String toString() {
    final rows = <String>[
      for (var i = 0; i < questions.length; i++)
        '(${questions[i].id}: answer="${questions[i].answer}", '
            'response="${responses[i]}")',
    ];
    return '_Scenario(count: ${questions.length}, '
        'expectedCorrect: $expectedCorrect, $rows)';
  }
}

/// Builds a varied session: 1..8 questions, each a fill-in-the-blank or
/// choose-the-right-word item with a short random answer. For each question the
/// response is chosen to exercise the full space:
///   - an exact-correct answer,
///   - a case/whitespace variant that must still score correct,
///   - or an arbitrary wrong answer.
/// Mixing these keeps the correct/wrong split unpredictable across iterations.
_Scenario _generateScenario(Random random) {
  const words = <String>['sunny', 'rainy', 'blue', 'run', 'cat', 'dog', 'go'];

  final count = 1 + random.nextInt(8); // 1..8 questions
  final questions = <Question>[];
  final responses = <String>[];

  for (var i = 0; i < count; i++) {
    final answer = words[random.nextInt(words.length)];
    final isChoose = random.nextBool();
    questions.add(
      Question(
        id: 'q$i',
        type: isChoose ? QuestionType.chooseWord : QuestionType.fillBlank,
        prompt: 'prompt $i',
        answer: answer,
        options: isChoose ? <String>[answer, 'other'] : const <String>[],
      ),
    );

    switch (random.nextInt(3)) {
      case 0: // exact correct
        responses.add(answer);
      case 1: // case/whitespace variant — Answer.score must still score correct
        responses.add('  ${answer.toUpperCase()} ');
      default: // arbitrary wrong answer (guaranteed different word)
        var wrong = words[random.nextInt(words.length)];
        while (wrong == answer) {
          wrong = words[random.nextInt(words.length)];
        }
        responses.add(wrong);
    }
  }

  return _Scenario(questions: questions, responses: responses);
}

void main() {
  const iterations = 300;

  group('Property 12: quiz answer counts are consistent (Requirements 6.2)', () {
    test('domain level: Answer.score tallies partition answered questions and '
        'correctCount matches the count of correct answers', () {
      // Fixed seed => reproducible iterations; any counterexample prints.
      final random = Random(6002);

      for (var i = 0; i < iterations; i++) {
        final scenario = _generateScenario(random);
        final reason = 'iteration $i, $scenario';

        var correct = 0;
        var wrong = 0;
        final answers = <Answer>[];

        for (var j = 0; j < scenario.questions.length; j++) {
          final scored = Answer.score(
            scenario.questions[j],
            scenario.responses[j],
          );
          answers.add(scored);
          if (scored.correct) {
            correct++;
          } else {
            wrong++;
          }

          // After every answer the tallies partition what has been answered.
          expect(correct + wrong, answers.length, reason: reason);
        }

        // On completion every question has been answered exactly once.
        expect(answers.length, scenario.questions.length, reason: reason);
        // The correct tally matches the independent oracle.
        expect(correct, scenario.expectedCorrect, reason: reason);
        expect(
          wrong,
          scenario.questions.length - scenario.expectedCorrect,
          reason: reason,
        );
      }
    });

    test('controller level: correctCount + wrongCount == answeredCount after '
        'every answer, correctCount matches the oracle, and a completed session '
        'has answeredCount == totalCount', () async {
      final random = Random(6012);

      for (var i = 0; i < iterations; i++) {
        final scenario = _generateScenario(random);
        final reason = 'iteration $i, $scenario';

        final firestore = FakeFirebaseFirestore();
        for (final q in scenario.questions) {
          await firestore
              .doc(FirestorePaths.quizItemDoc(q.id))
              .set(<String, dynamic>{
                'type': q.type.wireValue,
                'prompt': q.prompt,
                'options': q.options,
                'answer': q.answer,
                'tags': <String>[],
              });
        }

        final container = ProviderContainer(
          overrides: [
            firebaseFirestoreProvider.overrideWithValue(firestore),
            // Quizzes are network-required; keep the controller on the online
            // path so this property exercises scoring, not the offline guard
            // (task 9.6). (Requirements 6.6, 8.4)
            connectivityStatusProvider.overrideWith(
              (ref) =>
                  Stream<ConnectivityStatus>.value(ConnectivityStatus.online),
            ),
          ],
        );

        // Let the overridden connectivity stream deliver its first value so
        // the controller's opening load observes a resolved online status.
        final connSub = container.listen(connectivityStatusProvider, (_, _) {});
        while (container.read(connectivityStatusProvider).asData == null) {
          await Future<void>.delayed(Duration.zero);
        }
        connSub.close();

        final initial = await container.read(quizControllerProvider.future);
        // The session must open in progress with the full bank loaded; a
        // mismatch would mean the invariant below is being checked against
        // the wrong set of questions.
        expect(initial.phase, QuizPhase.inProgress, reason: reason);
        expect(initial.totalCount, scenario.questions.length, reason: reason);

        final controller = container.read(quizControllerProvider.notifier);

        for (var j = 0; j < scenario.questions.length; j++) {
          controller.answer(scenario.responses[j]);

          final s = container.read(quizControllerProvider).value!;
          // Counts partition the answered questions at every step.
          expect(
            s.correctCount + s.wrongCount,
            s.answeredCount,
            reason: '$reason — after answer $j',
          );
          expect(s.answeredCount, j + 1, reason: '$reason — after answer $j');
        }

        final s = container.read(quizControllerProvider).value!;
        // A completed session has scored every question exactly once.
        expect(s.phase, QuizPhase.results, reason: reason);
        expect(s.answeredCount, s.totalCount, reason: reason);
        expect(s.correctCount + s.wrongCount, s.totalCount, reason: reason);
        // The displayed correct count equals the number of correct answers
        // (Requirement 6.2), verified against the independent oracle.
        expect(s.correctCount, scenario.expectedCorrect, reason: reason);
        expect(
          s.wrongCount,
          scenario.questions.length - scenario.expectedCorrect,
          reason: reason,
        );

        container.dispose();
      }
    });
  });
}
