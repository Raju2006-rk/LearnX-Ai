// Widget test for the daily quiz screen: it renders fill-in-the-blank and
// choose-the-right-word questions, scores answers, and shows a results view
// with the correct and wrong counts. (Requirements 6.1, 6.2)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/network/connectivity.dart';
import 'package:learnx/features/quiz/presentation/quiz_screen.dart';

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

  Future<void> pumpScreen(
    WidgetTester tester, {
    ConnectivityStatus connectivity = ConnectivityStatus.online,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(firestore),
          connectivityStatusProvider.overrideWith(
            (ref) => Stream<ConnectivityStatus>.value(connectivity),
          ),
        ],
        child: const MaterialApp(home: QuizScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders a fill-in-the-blank question with a text field', (
    tester,
  ) async {
    await seedQuizItem('q1', prompt: 'A ___ day', answer: 'sunny');
    await pumpScreen(tester);

    expect(find.text('A ___ day'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
  });

  testWidgets('renders a choose-the-right-word question as option buttons', (
    tester,
  ) async {
    await seedQuizItem(
      'q1',
      type: 'choose_word',
      prompt: 'Pick the verb',
      options: const ['run', 'blue'],
      answer: 'run',
    );
    await pumpScreen(tester);

    expect(find.text('Pick the verb'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'run'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'blue'), findsOneWidget);
  });

  testWidgets(
    'completing the quiz shows the correct and wrong counts (Req 6.2)',
    (tester) async {
      await seedQuizItem('q1', prompt: 'A ___ day', answer: 'sunny');
      await seedQuizItem(
        'q2',
        type: 'choose_word',
        prompt: 'Pick the verb',
        options: const ['run', 'blue'],
        answer: 'run',
      );
      await pumpScreen(tester);

      // Answer q1 correctly via the text field.
      await tester.enterText(find.byType(TextField), 'sunny');
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Answer q2 wrong by choosing the non-answer option.
      await tester.tap(find.widgetWithText(OutlinedButton, 'blue'));
      await tester.pumpAndSettle();

      expect(find.text('Quiz complete'), findsOneWidget);
      expect(find.text('Correct: 1'), findsOneWidget);
      expect(find.text('Wrong: 1'), findsOneWidget);
    },
  );

  testWidgets('an empty bank shows the caught-up message', (tester) async {
    await pumpScreen(tester);

    expect(
      find.text("You're all caught up. No quiz questions right now."),
      findsOneWidget,
    );
  });

  testWidgets(
    'when offline, shows a network-required message with a retry (Req 6.6, 8.4)',
    (tester) async {
      // A non-empty bank would otherwise start a session; the offline guard
      // must surface the network-required view instead.
      await seedQuizItem('q1', prompt: 'A ___ day', answer: 'sunny');
      await pumpScreen(tester, connectivity: ConnectivityStatus.offline);

      expect(
        find.text(
          'Quizzes require a network connection. Reconnect and try again.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
      // The question was never presented.
      expect(find.text('A ___ day'), findsNothing);
    },
  );
}
