// Widget tests for the Progress screen: it renders the learner's current and
// longest streak (Requirement 7.1) and a Day 1-15-and-beyond daily goal
// tracker (Requirement 7.2), and the ProgressController records a qualifying
// activity that advances both (Requirement 7.5).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/progress/application/progress_controller.dart';
import 'package:learnx/features/progress/domain/daily_goal.dart';
import 'package:learnx/features/progress/presentation/progress_screen.dart';

void main() {
  const uid = 'learner-1';
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer containerFor({String? signedInUid = uid}) {
    return ProviderContainer(
      overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        authStateProvider.overrideWithValue(AuthState(uid: signedInUid)),
      ],
    );
  }

  Future<void> pump(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ProgressScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders current and longest streak', (tester) async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 5,
      'longestStreak': 8,
      'dailyGoal': <String, dynamic>{'day': 5, 'targetPerDay': 1},
    });

    final container = containerFor();
    addTearDown(container.dispose);
    await pump(tester, container);

    expect(find.text('Current (days)'), findsOneWidget);
    expect(find.text('Longest (days)'), findsOneWidget);
    // Scope the streak counts to the streak card so the day-chip numbers in
    // the tracker (which also contain "5" and "8") do not collide.
    expect(
      find.descendant(
        of: find.byType(StreakSummaryCard),
        matching: find.text('5'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(StreakSummaryCard),
        matching: find.text('8'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('renders the Day 1-15 tracker with no learner progress', (
    tester,
  ) async {
    final container = containerFor();
    addTearDown(container.dispose);
    await pump(tester, container);

    // The tracker always spans Day 1 through Day 15.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('15'), findsOneWidget);
    expect(
      find.text('Complete an activity to start your daily goal'),
      findsOneWidget,
    );
  });

  testWidgets('extends the tracker beyond Day 15 once the learner passes it', (
    tester,
  ) async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'dailyGoal': <String, dynamic>{'day': 18, 'targetPerDay': 1},
    });

    final container = containerFor();
    addTearDown(container.dispose);
    await pump(tester, container);

    // Day 18 chip is rendered (beyond the Day 15 span).
    expect(find.text('18'), findsOneWidget);
  });

  testWidgets('recordQualifyingActivity advances the streak and goal', (
    tester,
  ) async {
    final container = containerFor();
    addTearDown(container.dispose);
    await pump(tester, container);

    // Resolve the controller and record an activity for a fixed date.
    final controller = container.read(progressControllerProvider.notifier);
    await controller.recordQualifyingActivity(date: '2024-03-10');
    await tester.pumpAndSettle();

    // The persisted document reflects the streak + goal advance.
    final snap = await firestore.doc(FirestorePaths.progressDoc(uid)).get();
    final data = snap.data();
    expect(data?['currentStreak'], 1);
    expect(data?['longestStreak'], 1);
    expect((data?['dailyGoal'] as Map)['day'], 1);

    // And the on-screen overview reflects Day 1.
    final overview = container.read(progressControllerProvider).value;
    expect(overview?.streak.current, 1);
    expect(overview?.dailyGoal.day, 1);
  });

  testWidgets('recordQualifyingActivity is a no-op when signed out', (
    tester,
  ) async {
    final container = containerFor(signedInUid: null);
    addTearDown(container.dispose);
    await pump(tester, container);

    final controller = container.read(progressControllerProvider.notifier);
    await controller.recordQualifyingActivity(date: '2024-03-10');
    await tester.pumpAndSettle();

    final overview = container.read(progressControllerProvider).value;
    expect(overview?.streak, isNotNull);
    expect(overview?.dailyGoal, DailyGoal.initial);
  });
}
