// Unit tests for QuizController: loading the quiz bank, driving a session over
// fill-in-the-blank and choose-the-right-word questions, scoring answers, and
// tracking the correct/wrong counts the results view shows.
// (Requirements 6.1, 6.2)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/network/connectivity.dart';
import 'package:learnx/features/quiz/application/quiz_controller.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedQuizItem(
    String id, {
    String type = 'fill_blank',
    String prompt = 'prompt',
    List<String> options = const [],
    String answer = 'answer',
  }) async {
    await firestore.doc(FirestorePaths.quizItemDoc(id)).set(<String, dynamic>{
      'type': type,
      'prompt': prompt,
      'options': options,
      'answer': answer,
      'tags': <String>[],
    });
  }

  ProviderContainer makeContainer({
    ConnectivityStatus connectivity = ConnectivityStatus.online,
  }) {
    final container = ProviderContainer(
      overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        connectivityStatusProvider.overrideWith(
          (ref) => Stream<ConnectivityStatus>.value(connectivity),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// Subscribes to [connectivityStatusProvider] and pumps until its first
  /// value lands, so the controller observes a resolved online/offline status
  /// synchronously when a session starts (the overridden stream emits via a
  /// microtask).
  Future<void> settleConnectivity(ProviderContainer container) async {
    final sub = container.listen(connectivityStatusProvider, (_, _) {});
    addTearDown(sub.close);
    while (container.read(connectivityStatusProvider).asData == null) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('build starts an in-progress session at the first question', () async {
    await seedQuizItem('q1', prompt: 'A ___ day', answer: 'sunny');
    final container = makeContainer();

    final state = await container.read(quizControllerProvider.future);

    expect(state.phase, QuizPhase.inProgress);
    expect(state.totalCount, 1);
    expect(state.currentQuestion!.id, 'q1');
    expect(state.correctCount, 0);
    expect(state.wrongCount, 0);
  });

  test('an empty bank resolves to the empty phase', () async {
    final container = makeContainer();

    final state = await container.read(quizControllerProvider.future);

    expect(state.phase, QuizPhase.empty);
    expect(state.totalCount, 0);
  });

  test('a correct answer increments the correct count and advances', () async {
    await seedQuizItem('q1', answer: 'sunny');
    await seedQuizItem('q2', answer: 'rainy');
    final container = makeContainer();
    await container.read(quizControllerProvider.future);
    final controller = container.read(quizControllerProvider.notifier);

    // Case-insensitive, whitespace-trimmed scoring via Answer.score.
    controller.answer('  SUNNY ');

    final state = container.read(quizControllerProvider).value!;
    expect(state.correctCount, 1);
    expect(state.wrongCount, 0);
    expect(state.phase, QuizPhase.inProgress);
    expect(state.index, 1);
  });

  test('a wrong answer increments the wrong count', () async {
    await seedQuizItem('q1', answer: 'sunny');
    await seedQuizItem('q2', answer: 'rainy');
    final container = makeContainer();
    await container.read(quizControllerProvider.future);
    final controller = container.read(quizControllerProvider.notifier);

    controller.answer('cloudy');

    final state = container.read(quizControllerProvider).value!;
    expect(state.correctCount, 0);
    expect(state.wrongCount, 1);
  });

  test(
    'answering every question transitions to results with final tallies',
    () async {
      await seedQuizItem('q1', answer: 'sunny');
      await seedQuizItem(
        'q2',
        type: 'choose_word',
        options: const ['cat', 'dog'],
        answer: 'dog',
      );
      final container = makeContainer();
      await container.read(quizControllerProvider.future);
      final controller = container.read(quizControllerProvider.notifier);

      controller.answer('sunny'); // correct
      controller.answer('cat'); // wrong

      final state = container.read(quizControllerProvider).value!;
      expect(state.phase, QuizPhase.results);
      expect(state.correctCount, 1);
      expect(state.wrongCount, 1);
      // Counts partition the answered questions. (Requirement 6.2)
      expect(state.correctCount + state.wrongCount, state.answeredCount);
      expect(state.answeredCount, state.totalCount);
    },
  );

  test('answering past the results phase is a no-op', () async {
    await seedQuizItem('q1', answer: 'sunny');
    final container = makeContainer();
    await container.read(quizControllerProvider.future);
    final controller = container.read(quizControllerProvider.notifier);

    controller.answer('sunny'); // finishes the single-question session
    expect(
      container.read(quizControllerProvider).value!.phase,
      QuizPhase.results,
    );

    controller.answer('anything'); // ignored

    final state = container.read(quizControllerProvider).value!;
    expect(state.phase, QuizPhase.results);
    expect(state.answeredCount, 1);
  });

  test('restart reloads the bank and starts a fresh session', () async {
    await seedQuizItem('q1', answer: 'sunny');
    final container = makeContainer();
    await container.read(quizControllerProvider.future);
    final controller = container.read(quizControllerProvider.notifier);

    controller.answer('sunny');
    expect(
      container.read(quizControllerProvider).value!.phase,
      QuizPhase.results,
    );

    await controller.restart();

    final state = container.read(quizControllerProvider).value!;
    expect(state.phase, QuizPhase.inProgress);
    expect(state.correctCount, 0);
    expect(state.wrongCount, 0);
    expect(state.answeredCount, 0);
    expect(state.index, 0);
  });

  test('build while offline resolves to the offline phase without loading the '
      'bank (Req 6.6, 8.4)', () async {
    // Seed a non-empty bank so a successful load would start a session; the
    // offline guard must short-circuit before the repository is read.
    await seedQuizItem('q1', answer: 'sunny');
    final container = makeContainer(connectivity: ConnectivityStatus.offline);
    await settleConnectivity(container);

    final state = await container.read(quizControllerProvider.future);

    expect(state.phase, QuizPhase.offline);
    expect(state.errorMessage, QuizController.offlineMessage);
    // No session was started off the bank.
    expect(state.totalCount, 0);
    expect(state.currentQuestion, isNull);
  });

  test(
    'restart while offline resolves to the offline phase (Req 6.6, 8.4)',
    () async {
      await seedQuizItem('q1', answer: 'sunny');
      final container = makeContainer(connectivity: ConnectivityStatus.offline);
      await settleConnectivity(container);
      await container.read(quizControllerProvider.future);
      final controller = container.read(quizControllerProvider.notifier);

      await controller.restart();

      final state = container.read(quizControllerProvider).value!;
      expect(state.phase, QuizPhase.offline);
      expect(state.errorMessage, QuizController.offlineMessage);
    },
  );

  test(
    'build while online starts the session as before (Req 6.6 happy path)',
    () async {
      await seedQuizItem('q1', answer: 'sunny');
      final container = makeContainer(connectivity: ConnectivityStatus.online);
      await settleConnectivity(container);

      final state = await container.read(quizControllerProvider.future);

      expect(state.phase, QuizPhase.inProgress);
      expect(state.totalCount, 1);
    },
  );
}
