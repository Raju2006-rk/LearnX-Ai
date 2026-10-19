// Widget test for the onboarding flow: stepping through level → goal → native
// language persists a profile draft and lands on the placement seam.
// (Requirements 2.1, 2.2, 2.3)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/onboarding/data/onboarding_providers.dart';
import 'package:learnx/features/onboarding/data/placement_repository.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';
import 'package:learnx/features/onboarding/domain/placement_engine.dart';
import 'package:learnx/features/onboarding/domain/placement_question.dart';
import 'package:learnx/features/onboarding/presentation/english_level_step.dart';
import 'package:learnx/features/onboarding/presentation/goal_step.dart';
import 'package:learnx/features/onboarding/presentation/native_language_step.dart';
import 'package:learnx/features/onboarding/presentation/onboarding_flow_screen.dart';
import 'package:learnx/features/onboarding/presentation/placement_step.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

/// A placement repository stub so reaching the placement step in the flow test
/// does not hit a live callable; it just serves one question and never
/// completes within the test's scope.
class _StubPlacementRepository implements PlacementRepository {
  @override
  Future<Result<PlacementQuestionResult>> nextQuestion({
    required CefrLevel band,
    List<PlacementAnswer> priorAnswers = const [],
  }) async {
    return Result.success(
      PlacementQuestionResult(
        question: PlacementQuestion(
          questionId: 'q0',
          band: band,
          prompt: 'Placement question',
          options: const ['one', 'two'],
        ),
        gradedAnswers: const [],
      ),
    );
  }

  @override
  Future<Result<void>> completePlacement({
    required String uid,
    required CefrLevel level,
  }) async =>
      const Result.success(null);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;

  const uid = 'user-123';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
  });

  Future<void> pumpFlow(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(firestore),
          firebaseAuthProvider.overrideWithValue(auth),
          placementRepositoryProvider
              .overrideWithValue(_StubPlacementRepository()),
        ],
        child: const MaterialApp(home: OnboardingFlowScreen()),
      ),
    );
  }

  testWidgets(
    'completing all three selections persists the draft and advances to '
    'placement',
    (tester) async {
      await pumpFlow(tester);

      // Step 1: English level.
      expect(find.byType(EnglishLevelStep), findsOneWidget);
      await tester.tap(find.text(EnglishLevel.b1.label));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      // Step 2: goal.
      expect(find.byType(GoalStep), findsOneWidget);
      await tester.tap(find.text('Job'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pumpAndSettle();

      // Step 3: native language, then save.
      expect(find.byType(NativeLanguageStep), findsOneWidget);
      await tester.tap(find.text(NativeLanguage.hindi.label));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save and continue'));
      await tester.pumpAndSettle();

      // Landed on the adaptive placement step (task 5.6).
      expect(find.byType(PlacementStep), findsOneWidget);

      // Draft persisted with allowed enum wire values.
      final profile =
          (await firestore.doc(FirestorePaths.profileDoc(uid)).get()).data();
      expect(profile, isNotNull);
      expect(profile!['englishLevel'], 'B1');
      expect(profile['goal'], 'job');
      expect(profile['nativeLanguage'], 'hi');
      // 5.6 owns the onboarded transition; the draft must not flip it here.
      expect(profile['onboarded'], anyOf(isNull, isFalse));
    },
  );

  testWidgets('back returns to the previous step preserving selections',
      (tester) async {
    await pumpFlow(tester);

    await tester.tap(find.text(EnglishLevel.a2.label));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    expect(find.byType(GoalStep), findsOneWidget);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    // Back on the level step with the earlier choice still selected, so
    // continue works immediately.
    expect(find.byType(EnglishLevelStep), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.byType(GoalStep), findsOneWidget);
  });
}
