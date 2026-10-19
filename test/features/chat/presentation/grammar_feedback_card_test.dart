// Widget tests for the Grammar_Feedback card: the flagged mistake renders in
// red (and is omitted when there is no mistake), the corrected sentence renders
// in green, and the tip and native-language translation are shown. (Req 4.2, 4.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/chat/presentation/grammar_feedback_card.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';

import '../../learning_path/learning_path_test_support.dart';

void main() {
  const mistakeColor = Color(0xFFD32F2F);
  const correctedColor = Color(0xFF2E7D32);

  Future<void> pump(WidgetTester tester, GrammarFeedback feedback) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          aiFunctionClientProvider.overrideWithValue(FakeAiFunctionClient()),
          authStateProvider.overrideWithValue(const AuthState(uid: 'u1')),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: GrammarFeedbackCard(
              feedback: feedback,
              sessionId: 's1',
              messageId: 'm1',
              originalText: 'i has a apple',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Finds the [Text] widget whose data equals [data].
  Text textWidget(String data) =>
      find.text(data).evaluate().single.widget as Text;

  const withMistake = GrammarFeedback(
    hasMistake: true,
    mistakeSpan: MistakeSpan(start: 2, end: 5, text: 'has'),
    correctedSentence: 'I have an apple.',
    tip: 'Use "have" with "I".',
    translation: FeedbackTranslation(
      language: NativeLanguage.hindi,
      text: '"I" के साथ "have" का प्रयोग करें।',
    ),
  );

  const withoutMistake = GrammarFeedback(
    hasMistake: false,
    correctedSentence: 'I have an apple.',
    tip: 'Looks good!',
    translation: FeedbackTranslation(
      language: NativeLanguage.tamil,
      text: 'நன்றாக உள்ளது!',
    ),
  );

  testWidgets('renders the mistake span in red when there is a mistake '
      '(Req 4.2)', (tester) async {
    await pump(tester, withMistake);

    expect(find.text('has'), findsOneWidget);
    expect(textWidget('has').style?.color, mistakeColor);
  });

  testWidgets('renders the corrected sentence in green (Req 4.2)', (
    tester,
  ) async {
    await pump(tester, withMistake);

    expect(find.text('I have an apple.'), findsOneWidget);
    expect(textWidget('I have an apple.').style?.color, correctedColor);
  });

  testWidgets('shows the tip and the native-language translation (Req 4.3)', (
    tester,
  ) async {
    await pump(tester, withMistake);

    expect(find.text('Use "have" with "I".'), findsOneWidget);
    expect(find.text('"I" के साथ "have" का प्रयोग करें।'), findsOneWidget);
    // Labelled with the language's own endonym.
    expect(find.text(NativeLanguage.hindi.nativeName), findsOneWidget);
  });

  testWidgets('omits the mistake span (and its red styling) when there is no '
      'mistake (Req 4.2)', (tester) async {
    await pump(tester, withoutMistake);

    // The corrected sentence, tip, and translation are still shown.
    expect(find.text('I have an apple.'), findsOneWidget);
    expect(find.text('Looks good!'), findsOneWidget);
    expect(find.text('நன்றாக உள்ளது!'), findsOneWidget);

    // No text is rendered in the mistake red.
    final reds = find
        .byType(Text)
        .evaluate()
        .map((e) => e.widget as Text)
        .where((t) => t.style?.color == mistakeColor);
    expect(reds, isEmpty);
    // There is no "Mistake" label either.
    expect(find.text('Mistake'), findsNothing);
  });

  testWidgets('embeds the report control on the card (Req 5.3)', (
    tester,
  ) async {
    await pump(tester, withMistake);

    expect(find.text('Report'), findsOneWidget);
  });
}
