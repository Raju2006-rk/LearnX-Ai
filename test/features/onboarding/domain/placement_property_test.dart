// Property-based tests for the adaptive placement contract.
//
// Property 3: Placement difficulty steps within bounds. For any sequence of
// correct/wrong answers, the difficulty band index the engine targets always
// stays within [0, 4] (A1–C1) — a correct answer never steps above C1 and a
// wrong answer never steps below A1, and that holds after every answer, not
// just at the end. (Validates: Requirements 2.4)
//
// Property 4: Placement always assigns a valid CEFR level. For any completed
// session (any sequence of answers, any total-question count), the settled
// result is always one of the five valid CEFR levels (A1, A2, B1, B2, C1) and
// its ladder index is within [0, 4]. (Validates: Requirements 2.5)
//
// Property 5: Onboarding completion transition. When a learner's level, goal,
// native language, and placement are all set — modeled as a draft profile plus
// a `completePlacement` write — the profile is marked onboarded and the
// `watchOnboarded` seam that drives the router emits `true`, regardless of the
// draft's prior values or the settled CEFR level. (Validates: Requirements 2.6)
//
// The project has no dedicated property-testing package, so these tests follow
// the convention of `auth_session_property_test.dart`: drive many (100+)
// randomly generated inputs through the real engine/collaborators — the pure
// `PlacementEngine` and, for Property 5, the actual `OnboardingRepository`
// running against an in-memory `FakeFirebaseFirestore` with a draft seeded via
// `OnboardingRepository.saveDraft`. A fixed seed keeps iterations reproducible;
// a failing case prints the generated scenario.

import 'dart:math';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/onboarding/data/onboarding_repository.dart';
import 'package:learnx/features/onboarding/data/placement_repository.dart';
import 'package:learnx/features/onboarding/domain/onboarding_selections.dart';
import 'package:learnx/features/onboarding/domain/placement_engine.dart';

import '../data/placement_repository_test_support.dart';

/// A randomly generated placement run: a sequence of answer outcomes played
/// against an engine with a generated total-question count.
class _Run {
  const _Run({required this.totalQuestions, required this.outcomes});

  /// The number of questions this session asks before settling.
  final int totalQuestions;

  /// The correct/wrong outcome of each answer, in order. May be longer than
  /// [totalQuestions] so that over-answering (a no-op once complete) is also
  /// exercised.
  final List<bool> outcomes;

  @override
  String toString() =>
      '_Run(totalQuestions: $totalQuestions, outcomes: $outcomes)';
}

/// Builds a varied run from [random]: a total between 1 and 12 questions and a
/// sequence of 0..(total+4) correct/wrong outcomes (so sessions that stop
/// short, finish exactly, and over-answer are all covered).
_Run _generateRun(Random random) {
  final totalQuestions = 1 + random.nextInt(12);
  final count = random.nextInt(totalQuestions + 5);
  return _Run(
    totalQuestions: totalQuestions,
    outcomes: [for (var i = 0; i < count; i++) random.nextBool()],
  );
}

void main() {
  const iterations = 200;

  // The five valid CEFR levels the placement result must always be one of.
  const validLevels = {
    CefrLevel.a1,
    CefrLevel.a2,
    CefrLevel.b1,
    CefrLevel.b2,
    CefrLevel.c1,
  };

  test(
    'Property 3: placement difficulty steps stay within bounds (A1..C1) '
    'after every answer',
    () {
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(2407);

      for (var i = 0; i < iterations; i++) {
        final run = _generateRun(random);
        final reason = 'iteration $i, $run';

        var engine = PlacementEngine.initial(
          totalQuestions: run.totalQuestions,
        );

        // The starting band is in bounds before any answer.
        expect(engine.bandIndex, inInclusiveRange(0, 4), reason: reason);

        for (final correct in run.outcomes) {
          engine = engine.answer(correct: correct);
          // After every step the targeted band index never leaves [0, 4].
          expect(engine.bandIndex, inInclusiveRange(0, 4), reason: reason);
          expect(validLevels, contains(engine.currentBand), reason: reason);
        }
      }
    },
  );

  test(
    'Property 4: a completed placement always assigns a valid CEFR level',
    () {
      final random = Random(5521);

      for (var i = 0; i < iterations; i++) {
        final run = _generateRun(random);
        final reason = 'iteration $i, $run';

        var engine = PlacementEngine.initial(
          totalQuestions: run.totalQuestions,
        );
        for (final correct in run.outcomes) {
          engine = engine.answer(correct: correct);
        }

        // Only a completed session is meaningfully "assigned" a level; drive
        // the engine to completion so the settle result reflects a finished
        // placement regardless of how many outcomes were generated.
        while (!engine.isComplete) {
          engine = engine.answer(correct: random.nextBool());
        }

        expect(engine.isComplete, isTrue, reason: reason);
        expect(engine.settleIndex, inInclusiveRange(0, 4), reason: reason);
        expect(validLevels, contains(engine.settleLevel), reason: reason);
      }
    },
  );

  test(
    'Property 5: completing onboarding marks the profile onboarded and the '
    'router seam observes the transition',
    () async {
      final random = Random(9133);

      // A smaller iteration count keeps the Firestore-backed property fast
      // while still exercising every draft/level combination many times over.
      const completionIterations = 120;

      for (var i = 0; i < completionIterations; i++) {
        final scenario = _generateCompletion(random);
        final reason = 'iteration $i, $scenario';

        final firestore = FakeFirebaseFirestore();
        final onboarding = OnboardingRepository(firestore: firestore);
        final placement = PlacementRepository(
          aiClient: FakeAiFunctionClient(),
          firestore: firestore,
        );

        // Before completion the seam reflects an un-onboarded profile.
        final before = await onboarding.watchOnboarded(scenario.uid).first;
        expect(before, isFalse, reason: reason);

        // The learner has chosen level + goal + native language (a draft).
        final draft = await onboarding.saveDraft(
          uid: scenario.uid,
          selections: scenario.selections,
        );
        expect(draft.isSuccess, isTrue, reason: reason);

        // Placement settles on a level and completion is persisted.
        final completed = await placement.completePlacement(
          uid: scenario.uid,
          level: scenario.placement,
        );
        expect(completed.isSuccess, isTrue, reason: reason);

        // The persisted profile is marked onboarded with the placement level,
        // and the draft selections are preserved by the merge writes.
        final profile = (await firestore
                .doc(FirestorePaths.profileDoc(scenario.uid))
                .get())
            .data();
        expect(profile, isNotNull, reason: reason);
        expect(profile!['onboarded'], isTrue, reason: reason);
        expect(profile['placementLevel'], scenario.placement.wireValue,
            reason: reason);
        expect(profile['englishLevel'], scenario.placement.wireValue,
            reason: reason);
        expect(profile['goal'], scenario.selections.goal!.wireValue,
            reason: reason);
        expect(
          profile['nativeLanguage'],
          scenario.selections.nativeLanguage!.wireValue,
          reason: reason,
        );

        // The router seam now observes the transition to onboarded == true.
        final after = await onboarding.watchOnboarded(scenario.uid).first;
        expect(after, isTrue, reason: reason);
      }
    },
  );
}

/// One randomly generated onboarding-completion scenario: a learner with a
/// complete set of self-selections plus the CEFR level placement settles on.
class _Completion {
  const _Completion({
    required this.uid,
    required this.selections,
    required this.placement,
  });

  final String uid;
  final OnboardingSelections selections;
  final CefrLevel placement;

  @override
  String toString() => '_Completion(uid: $uid, selections: $selections, '
      'placement: $placement)';
}

/// Builds a completion scenario with a full set of selections and a settled
/// level, varying every field across the allowed domains.
_Completion _generateCompletion(Random random) {
  EnglishLevel level() =>
      EnglishLevel.values[random.nextInt(EnglishLevel.values.length)];
  LearningGoal goal() =>
      LearningGoal.values[random.nextInt(LearningGoal.values.length)];
  NativeLanguage language() =>
      NativeLanguage.values[random.nextInt(NativeLanguage.values.length)];
  CefrLevel placement() =>
      CefrLevel.values[random.nextInt(CefrLevel.values.length)];

  return _Completion(
    uid: 'user-${random.nextInt(1 << 32)}',
    selections: OnboardingSelections(
      englishLevel: level(),
      goal: goal(),
      nativeLanguage: language(),
    ),
    placement: placement(),
  );
}
