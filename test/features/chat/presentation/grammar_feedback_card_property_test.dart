// Property-based test for the Grammar_Feedback card rendering contract.
//
// Property 8: Grammar feedback rendering completeness. For ANY GrammarFeedback
// the card always renders the corrected sentence (in green), the tip, and the
// native-language translation (labelled with the language's own endonym). When
// `hasMistake` is true the flagged mistake span renders in red; when
// `hasMistake` is false the span is omitted and no red mistake styling appears
// anywhere on the card. (Validates: Requirements 4.2, 4.3)
//
// The widget-level examples in `grammar_feedback_card_test.dart` pin a couple
// of concrete feedbacks; this test drives many (100+) randomly generated
// feedbacks — varying the mistake flag, spans, languages, and text — through
// the real GrammarFeedbackCard so the completeness invariant is exercised
// across the whole input space, not just two hand-picked cases.
//
// The project has no dedicated property-testing package, so this follows the
// convention of `step_content_property_test.dart`: a fixed seed keeps
// iterations reproducible and a failing case is reported via `reason`.

import 'dart:math';

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

// The fixed red/green the card codes mistakes and corrections with.
const _mistakeColor = Color(0xFFD32F2F); // red 700
const _correctedColor = Color(0xFF2E7D32); // green 800

/// A short, non-empty, unique-ish random string so generated feedbacks have
/// distinguishable text that won't collide with the card's static labels
/// ("Mistake", "Corrected", "Tip") or an endonym.
String _text(Random random, String tag) =>
    '$tag-${random.nextInt(1 << 20)} words';

/// Builds a random [GrammarFeedback]. One in four is forced to `hasMistake:
/// false` so the no-mistake branch is exercised directly rather than just by
/// chance; the rest carry a mistake span with a non-empty flagged substring.
GrammarFeedback _generate(Random random) {
  final language =
      NativeLanguage.values[random.nextInt(NativeLanguage.values.length)];
  final translation = FeedbackTranslation(
    language: language,
    text: _text(random, 'tr'),
  );
  final corrected = _text(random, 'corrected');
  final tip = _text(random, 'tip');

  final hasMistake = random.nextInt(4) != 0;
  if (!hasMistake) {
    return GrammarFeedback(
      hasMistake: false,
      correctedSentence: corrected,
      tip: tip,
      translation: translation,
    );
  }

  final start = random.nextInt(8);
  final mistakeText = _text(random, 'mistake');
  return GrammarFeedback(
    hasMistake: true,
    mistakeSpan: MistakeSpan(
      start: start,
      end: start + mistakeText.length,
      text: mistakeText,
    ),
    correctedSentence: corrected,
    tip: tip,
    translation: translation,
  );
}

void main() {
  const iterations = 200;

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
              originalText: 'original learner text',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// All [Text] widgets currently in the tree.
  Iterable<Text> allTexts(WidgetTester tester) =>
      tester.widgetList<Text>(find.byType(Text));

  /// The color of the single [Text] whose data equals [data].
  Color? colorOf(String data) =>
      (find.text(data).evaluate().single.widget as Text).style?.color;

  testWidgets(
    'Property 8: the card always renders corrected (green), tip, and '
    'translation, and codes the mistake span in red iff hasMistake '
    '(Req 4.2, 4.3)',
    (tester) async {
      // Fixed seed => reproducible iterations; any counterexample prints.
      final random = Random(4821);

      for (var i = 0; i < iterations; i++) {
        final feedback = _generate(random);
        final reason = 'iteration $i, feedback=$feedback';

        await pump(tester, feedback);

        // Completeness: corrected sentence, tip, and translation are always
        // present, regardless of whether there was a mistake. (Req 4.2, 4.3)
        expect(find.text(feedback.correctedSentence), findsOneWidget,
            reason: reason);
        expect(find.text(feedback.tip), findsOneWidget, reason: reason);
        expect(find.text(feedback.translation.text), findsOneWidget,
            reason: reason);

        // The corrected sentence is coded green. (Req 4.2)
        expect(colorOf(feedback.correctedSentence), _correctedColor,
            reason: reason);

        // The translation is labelled with the language's own endonym. (Req 4.3)
        expect(find.text(feedback.translation.language.nativeName),
            findsOneWidget,
            reason: reason);

        final redTexts = allTexts(tester)
            .where((t) => t.style?.color == _mistakeColor)
            .toList();

        if (feedback.hasMistake) {
          // The flagged span is rendered, and in red. (Req 4.2)
          final mistakeText = feedback.mistakeSpan!.text;
          expect(find.text(mistakeText), findsOneWidget, reason: reason);
          expect(colorOf(mistakeText), _mistakeColor, reason: reason);
          // The red styling is exactly the flagged span, nothing else.
          expect(redTexts.length, 1, reason: reason);
          expect((redTexts.single).data, mistakeText, reason: reason);
        } else {
          // No mistake => no red mistake styling appears anywhere. (Req 4.2)
          expect(redTexts, isEmpty, reason: reason);
          // Nor the "Mistake" label the span line carries.
          expect(find.text('Mistake'), findsNothing, reason: reason);
        }

        // Reset between iterations so widgets don't carry over.
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
