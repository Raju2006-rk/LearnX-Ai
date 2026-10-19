// Widget test for the report-a-wrong-correction control: every Grammar_Feedback
// item exposes a report affordance, and filing a report confirms receipt to the
// learner and persists the full context snapshot. (Requirements 5.3, 5.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/chat/presentation/feedback_report_control.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';

import '../../learning_path/learning_path_test_support.dart';

void main() {
  const uid = 'learner-1';
  const sessionId = 'sess-1';

  const feedback = GrammarFeedback(
    hasMistake: true,
    mistakeSpan: MistakeSpan(start: 0, end: 1, text: 'i'),
    correctedSentence: 'I am happy.',
    tip: 'Capitalize "I".',
    translation: FeedbackTranslation(
      language: NativeLanguage.hindi,
      text: 'संकेत',
    ),
  );

  Future<void> pump(
    WidgetTester tester,
    FakeFirebaseFirestore firestore, {
    String messageId = 'm1',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(firestore),
          aiFunctionClientProvider.overrideWithValue(FakeAiFunctionClient()),
          authStateProvider.overrideWithValue(const AuthState(uid: uid)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: FeedbackReportControl(
              sessionId: sessionId,
              messageId: messageId,
              originalText: 'i am happy',
              feedback: feedback,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('every feedback item exposes a report control (Req 5.3)', (
    tester,
  ) async {
    await pump(tester, FakeFirebaseFirestore());

    expect(find.text('Report'), findsOneWidget);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });

  testWidgets('filing a report confirms receipt to the learner (Req 5.4)', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();
    await pump(tester, firestore);

    // Open the report dialog.
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('Report this correction'), findsOneWidget);

    // Add a reason and submit.
    await tester.enterText(find.byType(TextField), 'This is wrong.');
    await tester.tap(find.text('Submit report'));
    await tester.pumpAndSettle();

    // Receipt confirmed and the control reflects the reported state.
    expect(
      find.text('Thanks — your report has been received.'),
      findsOneWidget,
    );
    expect(find.text('Reported'), findsOneWidget);

    // Context snapshot persisted under the learner's own reports.
    final reports = await firestore
        .collection(FirestorePaths.reportsCollection(uid))
        .get();
    expect(reports.docs, hasLength(1));
    final data = reports.docs.single.data();
    expect(data['sessionId'], sessionId);
    expect(data['messageId'], 'm1');
    expect(data['originalText'], 'i am happy');
    expect(data['reason'], 'This is wrong.');
  });

  testWidgets('dismissing the dialog files nothing', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await pump(tester, firestore);

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    // No report stored and the control is still offered.
    final reports = await firestore
        .collection(FirestorePaths.reportsCollection(uid))
        .get();
    expect(reports.docs, isEmpty);
    expect(find.text('Report'), findsOneWidget);
  });
}
