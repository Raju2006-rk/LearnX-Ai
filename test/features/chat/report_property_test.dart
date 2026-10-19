// Property-based tests for report-a-wrong-correction. (Requirements 5.3, 5.4)
//
// Property 10: Every feedback item exposes a report control. For any list of
// rendered Grammar_Feedback items, each item exposes a report-a-wrong-correction
// control. (Validates: Requirements 5.3)
//
// Property 11: Reports preserve context (round-trip). For any reported wrong
// correction, the stored report record reproduces the original message and the
// associated feedback context, and a receipt is confirmed to the learner.
// (Validates: Requirements 5.4)
//
// The project has no dedicated property-testing package, so these tests follow
// the convention of the other `*_property_test.dart` files: drive many randomly
// generated inputs through the real widget / controller + `fake_cloud_firestore`
// and assert the invariant over each. A fixed seed keeps iterations
// reproducible; a failing case prints the generated scenario via `reason`.

import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/chat/application/report_controller.dart';
import 'package:learnx/features/chat/domain/chat.dart';
import 'package:learnx/features/chat/presentation/grammar_feedback_card.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';
import 'package:learnx/shared/models/dtos/dtos.dart';

import '../learning_path/learning_path_test_support.dart';

// ---------------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------------

const _safeWords = <String>[
  'hello',
  'grammar',
  'please',
  'learning',
  'english',
  'practice',
  'sentence',
  'today',
  'friendly',
  'question',
];

/// A short safe phrase built from harmless words, or the empty string.
String _phrase(Random random, {int minWords = 0, int maxWords = 5}) {
  final count = minWords + random.nextInt(maxWords - minWords + 1);
  return List.generate(
    count,
    (_) => _safeWords[random.nextInt(_safeWords.length)],
  ).join(' ');
}

/// A randomly generated [GrammarFeedback]. When [hasMistake] is true a
/// non-empty mistake span is produced so the card renders the mistake line.
GrammarFeedback _feedback(Random random) {
  final hasMistake = random.nextBool();
  final corrected = _phrase(random, minWords: 1);
  final language =
      NativeLanguage.values[random.nextInt(NativeLanguage.values.length)];
  return GrammarFeedback(
    hasMistake: hasMistake,
    mistakeSpan: hasMistake
        ? MistakeSpan(
            start: random.nextInt(10),
            end: 10 + random.nextInt(10),
            text: _phrase(random, minWords: 1, maxWords: 2),
          )
        : null,
    correctedSentence: corrected,
    tip: _phrase(random, minWords: 1),
    translation: FeedbackTranslation(
      language: language,
      text: _phrase(random, minWords: 1),
    ),
  );
}

/// A single reported scenario: the context snapshot the learner was shown plus
/// the (possibly null) free-text reason they supplied.
class _ReportScenario {
  const _ReportScenario({
    required this.sessionId,
    required this.messageId,
    required this.originalText,
    required this.feedback,
    required this.reason,
  });

  final String sessionId;
  final String messageId;
  final String originalText;
  final GrammarFeedback feedback;
  final String? reason;

  /// The reason as the controller stores it: trimmed, or null when blank.
  String? get expectedStoredReason {
    final r = reason;
    if (r == null) return null;
    final trimmed = r.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  String toString() =>
      '_ReportScenario(session: $sessionId, message: $messageId, '
      'originalText: "$originalText", reason: $reason, '
      'hasMistake: ${feedback.hasMistake})';
}

_ReportScenario _reportScenario(Random random, int i) {
  // A reason that is sometimes null, sometimes blank, sometimes real text so
  // the round-trip covers the controller's blank-dropping normalization.
  final String? reason;
  switch (random.nextInt(3)) {
    case 0:
      reason = null;
    case 1:
      reason = '   '; // blank -> dropped
    default:
      reason = _phrase(random, minWords: 1);
  }
  return _ReportScenario(
    sessionId: 'sess-$i',
    messageId: 'm$i',
    originalText: _phrase(random, minWords: 1),
    feedback: _feedback(random),
    reason: reason,
  );
}

void main() {
  const uid = 'learner-1';

  // -------------------------------------------------------------------------
  // Property 10: Every feedback item exposes a report control (Req 5.3)
  // -------------------------------------------------------------------------
  testWidgets(
    'Property 10: every rendered Grammar_Feedback item exposes a report control',
    (tester) async {
      const iterations = 60;
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(5311);

      for (var i = 0; i < iterations; i++) {
        // A randomly sized list of feedback items, each rendered in its own
        // card with a distinct message id so controls do not share state.
        final itemCount = 1 + random.nextInt(4); // 1..4
        final feedbacks = List.generate(itemCount, (_) => _feedback(random));
        final reason = 'iteration $i, itemCount=$itemCount';

        final firestore = FakeFirebaseFirestore();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firebaseFirestoreProvider.overrideWithValue(firestore),
              aiFunctionClientProvider.overrideWithValue(
                FakeAiFunctionClient(),
              ),
              authStateProvider.overrideWithValue(const AuthState(uid: uid)),
            ],
            child: MaterialApp(
              home: Scaffold(
                // A non-lazy Column (not a lazy ListView) so every generated
                // feedback item is actually built and rendered — the property
                // is "every rendered item exposes a control", so all items in
                // the list must be laid out, not just the on-screen subset.
                body: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var j = 0; j < feedbacks.length; j++)
                        GrammarFeedbackCard(
                          feedback: feedbacks[j],
                          sessionId: 'sess-$i',
                          messageId: 'm${i}_$j',
                          originalText: 'original $j',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Each rendered feedback item exposes exactly one report affordance:
        // one "Report" control per card in the list.
        expect(
          find.text('Report'),
          findsNWidgets(feedbacks.length),
          reason: reason,
        );
        expect(
          find.byIcon(Icons.flag_outlined),
          findsNWidgets(feedbacks.length),
          reason: reason,
        );
      }
    },
  );

  // -------------------------------------------------------------------------
  // Property 11: Reports preserve context — round-trip (Req 5.4)
  // -------------------------------------------------------------------------
  test(
    'Property 11: a filed report round-trips the full context snapshot',
    () async {
      const iterations = 200;
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(1104);

      for (var i = 0; i < iterations; i++) {
        final scenario = _reportScenario(random, i);
        final why = 'iteration $i, $scenario';

        final firestore = FakeFirebaseFirestore();
        final container = ProviderContainer(
          overrides: [
            firebaseFirestoreProvider.overrideWithValue(firestore),
            aiFunctionClientProvider.overrideWithValue(FakeAiFunctionClient()),
            authStateProvider.overrideWithValue(const AuthState(uid: uid)),
          ],
        );
        addTearDown(container.dispose);

        final controller = container.read(
          reportControllerProvider(scenario.messageId).notifier,
        );

        await controller.fileReport(
          sessionId: scenario.sessionId,
          messageId: scenario.messageId,
          originalText: scenario.originalText,
          feedback: scenario.feedback,
          reason: scenario.reason,
        );

        // A receipt is confirmed to the learner: the controller resolves to
        // ReportFiled carrying the stored report. (Req 5.4)
        final state = container.read(
          reportControllerProvider(scenario.messageId),
        );
        expect(state, isA<ReportFiled>(), reason: why);
        final filed = state as ReportFiled;
        expect(filed.report.id, isNotNull, reason: why);
        expect(filed.report.status, ReportStatus.open, reason: why);

        // The stored record reproduces the full context snapshot the learner
        // was shown. Read it back from Firestore and rebuild the domain Report
        // so the assertion exercises the real persistence round-trip. (Req 5.4)
        final snap = await firestore
            .doc(FirestorePaths.reportDoc(uid, filed.report.id!))
            .get();
        expect(snap.exists, isTrue, reason: why);
        final stored = Report.fromDto(
          ReportDto.fromMap(snap.data()!),
          id: filed.report.id,
        );

        expect(stored.sessionId, scenario.sessionId, reason: why);
        expect(stored.messageId, scenario.messageId, reason: why);
        expect(stored.originalText, scenario.originalText, reason: why);
        expect(stored.reason, scenario.expectedStoredReason, reason: why);
        expect(stored.status, ReportStatus.open, reason: why);
        // The associated feedback context round-trips field-for-field.
        expect(stored.grammarFeedback, scenario.feedback, reason: why);

        // The report surfaced for the receipt matches what was persisted
        // (ignoring the server-stamped createdAt the client never sets).
        expect(
          filed.report,
          Report(
            id: filed.report.id,
            sessionId: scenario.sessionId,
            messageId: scenario.messageId,
            originalText: scenario.originalText,
            grammarFeedback: scenario.feedback,
            reason: scenario.expectedStoredReason,
            status: ReportStatus.open,
          ),
          reason: why,
        );
      }
    },
  );
}
