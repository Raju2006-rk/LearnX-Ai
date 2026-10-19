// Widget tests for the onboarding step screens (English level, goal, native
// language). These verify option rendering, single-choice selection, and that
// the continue action is gated on a selection. (Requirements 2.1, 2.2, 2.3)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';
import 'package:learnx/features/onboarding/presentation/english_level_step.dart';
import 'package:learnx/features/onboarding/presentation/goal_step.dart';
import 'package:learnx/features/onboarding/presentation/native_language_step.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    // Use a tall surface so every option in the scrollable list is laid out
    // (a ListView lazily builds only visible items on the default viewport).
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(MaterialApp(home: child));
  }

  group('EnglishLevelStep', () {
    testWidgets('renders every CEFR level option', (tester) async {
      await pump(
        tester,
        EnglishLevelStep(
          selected: null,
          onSelected: (_) {},
          onContinue: () {},
        ),
      );

      for (final level in EnglishLevel.values) {
        expect(find.text(level.label), findsOneWidget);
      }
      expect(find.text('Step 1 of 3'), findsOneWidget);
    });

    testWidgets('tapping a level reports it via onSelected', (tester) async {
      EnglishLevel? picked;
      await pump(
        tester,
        EnglishLevelStep(
          selected: null,
          onSelected: (level) => picked = level,
          onContinue: () {},
        ),
      );

      await tester.tap(find.text(EnglishLevel.b1.label));
      await tester.pump();

      expect(picked, EnglishLevel.b1);
    });

    testWidgets('continue is disabled until a level is selected',
        (tester) async {
      var continued = false;
      await pump(
        tester,
        EnglishLevelStep(
          selected: null,
          onSelected: (_) {},
          onContinue: () => continued = true,
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();
      expect(continued, isFalse);

      // With a selection, continue fires.
      await pump(
        tester,
        EnglishLevelStep(
          selected: EnglishLevel.a2,
          onSelected: (_) {},
          onContinue: () => continued = true,
        ),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
      await tester.pump();
      expect(continued, isTrue);
    });
  });

  group('GoalStep', () {
    testWidgets('renders Speaking, Job, and Both options', (tester) async {
      await pump(
        tester,
        GoalStep(selected: null, onSelected: (_) {}, onContinue: () {}),
      );

      expect(find.text('Speaking'), findsOneWidget);
      expect(find.text('Job'), findsOneWidget);
      expect(find.text('Both'), findsOneWidget);
      expect(find.text('Step 2 of 3'), findsOneWidget);
    });

    testWidgets('tapping a goal reports it via onSelected', (tester) async {
      LearningGoal? picked;
      await pump(
        tester,
        GoalStep(
          selected: null,
          onSelected: (goal) => picked = goal,
          onContinue: () {},
        ),
      );

      await tester.tap(find.text('Job'));
      await tester.pump();

      expect(picked, LearningGoal.job);
    });
  });

  group('NativeLanguageStep', () {
    testWidgets('renders all five allowed native languages', (tester) async {
      await pump(
        tester,
        NativeLanguageStep(
          selected: null,
          onSelected: (_) {},
          onContinue: () {},
        ),
      );

      for (final language in NativeLanguage.values) {
        expect(find.text(language.label), findsOneWidget);
      }
      expect(find.text('Step 3 of 3'), findsOneWidget);
      // Final step confirms with a save-oriented label.
      expect(find.text('Save and continue'), findsOneWidget);
    });

    testWidgets('tapping a language reports it via onSelected',
        (tester) async {
      NativeLanguage? picked;
      await pump(
        tester,
        NativeLanguageStep(
          selected: null,
          onSelected: (language) => picked = language,
          onContinue: () {},
        ),
      );

      await tester.tap(find.text(NativeLanguage.tamil.label));
      await tester.pump();

      expect(picked, NativeLanguage.tamil);
    });

    testWidgets('shows a progress indicator while saving', (tester) async {
      await pump(
        tester,
        NativeLanguageStep(
          selected: NativeLanguage.hindi,
          onSelected: (_) {},
          onContinue: () {},
          isSaving: true,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('surfaces an error message when a save fails', (tester) async {
      await pump(
        tester,
        NativeLanguageStep(
          selected: NativeLanguage.hindi,
          onSelected: (_) {},
          onContinue: () {},
          errorMessage: 'Could not save your onboarding selections.',
        ),
      );

      expect(
        find.text('Could not save your onboarding selections.'),
        findsOneWidget,
      );
    });
  });
}
