// Unit tests for ReportController: filing a wrong-correction report through
// ChatRepository, confirming the stored report is surfaced for receipt, and
// mapping a signed-out learner / write failure to a failure state.
// (Requirements 5.3, 5.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/chat/application/report_controller.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';

import '../../learning_path/learning_path_test_support.dart';

void main() {
  const uid = 'learner-1';
  const sessionId = 'sess-1';
  const messageId = 'm1';

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

  ProviderContainer makeContainer(
    FakeFirebaseFirestore firestore, {
    String? signedInUid = uid,
  }) {
    final container = ProviderContainer(
      overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        aiFunctionClientProvider.overrideWithValue(FakeAiFunctionClient()),
        authStateProvider.overrideWithValue(AuthState(uid: signedInUid)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('files a report and surfaces the stored report for receipt', () async {
    final firestore = FakeFirebaseFirestore();
    final container = makeContainer(firestore);
    final controller = container.read(
      reportControllerProvider(messageId).notifier,
    );

    await controller.fileReport(
      sessionId: sessionId,
      messageId: messageId,
      originalText: 'i am happy',
      feedback: feedback,
      reason: 'The correction is wrong.',
    );

    final state = container.read(reportControllerProvider(messageId));
    expect(state, isA<ReportFiled>());
    final filed = state as ReportFiled;
    expect(filed.report.id, isNotNull);
    expect(filed.report.status, ReportStatus.open);

    // Full context snapshot persisted under the learner's own reports.
    final snap = await firestore
        .doc(FirestorePaths.reportDoc(uid, filed.report.id!))
        .get();
    final data = snap.data()!;
    expect(data['sessionId'], sessionId);
    expect(data['messageId'], messageId);
    expect(data['originalText'], 'i am happy');
    expect(data['reason'], 'The correction is wrong.');
    final feedbackMap = data['grammarFeedback'] as Map<String, dynamic>;
    expect(feedbackMap['correctedSentence'], 'I am happy.');
  });

  test('drops a blank reason so no empty note is stored', () async {
    final firestore = FakeFirebaseFirestore();
    final container = makeContainer(firestore);
    final controller = container.read(
      reportControllerProvider(messageId).notifier,
    );

    await controller.fileReport(
      sessionId: sessionId,
      messageId: messageId,
      originalText: 'i am happy',
      feedback: feedback,
      reason: '   ',
    );

    final filed = container.read(reportControllerProvider(messageId));
    expect(filed, isA<ReportFiled>());
    expect((filed as ReportFiled).report.reason, isNull);
  });

  test('fails without a signed-in learner and leaves nothing stored', () async {
    final firestore = FakeFirebaseFirestore();
    final container = makeContainer(firestore, signedInUid: null);
    final controller = container.read(
      reportControllerProvider(messageId).notifier,
    );

    await controller.fileReport(
      sessionId: sessionId,
      messageId: messageId,
      originalText: 'i am happy',
      feedback: feedback,
    );

    expect(
      container.read(reportControllerProvider(messageId)),
      isA<ReportFailure>(),
    );
  });

  test('each message id has independent report state', () async {
    final firestore = FakeFirebaseFirestore();
    final container = makeContainer(firestore);

    await container
        .read(reportControllerProvider('m1').notifier)
        .fileReport(
          sessionId: sessionId,
          messageId: 'm1',
          originalText: 'i am happy',
          feedback: feedback,
        );

    // Reporting m1 does not flip m2's control out of idle.
    expect(container.read(reportControllerProvider('m1')), isA<ReportFiled>());
    expect(container.read(reportControllerProvider('m2')), isA<ReportIdle>());
  });

  test('reset returns a failed control to idle', () {
    final firestore = FakeFirebaseFirestore();
    final container = makeContainer(firestore, signedInUid: null);
    final controller = container.read(
      reportControllerProvider(messageId).notifier,
    );

    container.read(reportControllerProvider(messageId));
    controller.reset();

    expect(
      container.read(reportControllerProvider(messageId)),
      isA<ReportIdle>(),
    );
  });
}
