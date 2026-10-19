// Widget test for the weekly summary view: it renders the current week's time
// spent, words learned, and mistakes fixed from the provider, serving a live
// dailyActivity fallback when no persisted summary exists, and degrades to a
// zeroed card when signed out. (Requirement 7.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/features/progress/domain/weekly_summary.dart';
import 'package:learnx/features/progress/presentation/weekly_summary_view.dart';

void main() {
  const uid = 'learner-1';
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pump(WidgetTester tester, {String? signedInUid = uid}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(firestore),
          authStateProvider.overrideWithValue(AuthState(uid: signedInUid)),
        ],
        child: const MaterialApp(
          home: Scaffold(body: WeeklySummaryView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders zeroed metrics with no activity', (tester) async {
    await pump(tester);

    expect(find.text('This week'), findsOneWidget);
    expect(find.text('0m'), findsOneWidget); // time spent
    expect(find.text('Words learned'), findsOneWidget);
    expect(find.text('Mistakes fixed'), findsOneWidget);
    // Both the words-learned and mistakes-fixed values are 0.
    expect(find.text('0'), findsNWidgets(2));
  });

  testWidgets('degrades to a zeroed card when signed out', (tester) async {
    await pump(tester, signedInUid: null);

    expect(find.text('0m'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
  });

  group('WeeklySummaryCard (pure presentation)', () {
    Future<void> pumpCard(WidgetTester tester, WeeklySummary summary) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: WeeklySummaryCard(summary: summary))),
      );
    }

    testWidgets('renders all three metrics', (tester) async {
      await pumpCard(
        tester,
        const WeeklySummary(
          timeSpentSec: 5400, // 1h 30m
          wordsLearned: 25,
          mistakesFixed: 7,
        ),
      );

      expect(find.text('1h 30m'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Time spent'), findsOneWidget);
      expect(find.text('Words learned'), findsOneWidget);
      expect(find.text('Mistakes fixed'), findsOneWidget);
    });
  });

  group('formatTimeSpent', () {
    test('formats minutes, hours, and combined', () {
      expect(WeeklySummaryCard.formatTimeSpent(0), '0m');
      expect(WeeklySummaryCard.formatTimeSpent(45 * 60), '45m');
      expect(WeeklySummaryCard.formatTimeSpent(3600), '1h');
      expect(WeeklySummaryCard.formatTimeSpent(5400), '1h 30m');
      expect(WeeklySummaryCard.formatTimeSpent(-10), '0m');
    });
  });
}
