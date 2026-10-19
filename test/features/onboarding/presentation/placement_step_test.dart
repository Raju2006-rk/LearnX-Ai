// Widget test for the adaptive placement step: it fetches questions, lets the
// learner answer, and on completion stores the level + onboarded flag, showing
// the confirmation. (Requirements 2.4, 2.5, 2.6)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/onboarding/data/onboarding_providers.dart';
import 'package:learnx/features/onboarding/data/placement_repository.dart';
import 'package:learnx/features/onboarding/domain/placement_engine.dart';
import 'package:learnx/features/onboarding/domain/placement_question.dart';
import 'package:learnx/features/onboarding/presentation/placement_step.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

/// A scripted [PlacementRepository] that serves a fixed sequence of questions
/// and grades every submitted answer as correct, then records the completed
/// level on the fake Firestore.
class _ScriptedPlacementRepository extends PlacementRepository {
  _ScriptedPlacementRepository(this._firestore)
      : super(
          aiClient: AiFunctionClient(_unusedFunctions),
          firestore: _firestore,
        );

  static final _unusedFunctions = _NeverFunctions();
  final FakeFirebaseFirestore _firestore;

  int _served = 0;
  int nextCalls = 0;
  CefrLevel? completedLevel;

  @override
  Future<Result<PlacementQuestionResult>> nextQuestion({
    required CefrLevel band,
    List<PlacementAnswer> priorAnswers = const [],
  }) async {
    nextCalls++;
    final graded = <PlacementGrade>[
      for (final a in priorAnswers)
        PlacementGrade(questionId: a.questionId, correct: true),
    ];
    final q = PlacementQuestion(
      questionId: 'q${_served++}',
      band: band,
      prompt: 'Question for ${band.wireValue}',
      options: const ['one', 'two'],
    );
    return Result.success(
      PlacementQuestionResult(question: q, gradedAnswers: graded),
    );
  }

  @override
  Future<Result<void>> completePlacement({
    required String uid,
    required CefrLevel level,
  }) async {
    completedLevel = level;
    await _firestore.doc(FirestorePaths.profileDoc(uid)).set(
      <String, dynamic>{
        'placementLevel': level.wireValue,
        'englishLevel': level.wireValue,
        'onboarded': true,
      },
      SetOptions(merge: true),
    );
    return const Result.success(null);
  }
}

/// Stand-in [FirebaseFunctions] for the base client, never invoked because the
/// scripted repository overrides every method that would use it.
class _NeverFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FirebaseFunctions is not used in this fake');
}

void main() {
  const uid = 'user-123';
  late FakeFirebaseFirestore firestore;
  late MockFirebaseAuth auth;
  late _ScriptedPlacementRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    repo = _ScriptedPlacementRepository(firestore);
  });

  Future<void> pump(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          firebaseFirestoreProvider.overrideWithValue(firestore),
          placementRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PlacementStep()),
      ),
    );
  }

  testWidgets('renders the first question after loading', (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Question for'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('two'), findsOneWidget);
    expect(find.textContaining('Question 1 of'), findsOneWidget);
  });

  testWidgets(
      'answering through the whole session stores the level and onboards',
      (tester) async {
    await pump(tester);
    await tester.pumpAndSettle();

    // Answer every question (default 8) by tapping the first option.
    for (var i = 0; i < PlacementEngine.defaultTotalQuestions; i++) {
      await tester.tap(find.text('one').first);
      await tester.pumpAndSettle();
    }

    // Placement stored a valid CEFR level and onboarded the profile.
    expect(repo.completedLevel, isNotNull);
    final profile =
        (await firestore.doc(FirestorePaths.profileDoc(uid)).get()).data();
    expect(profile!['onboarded'], isTrue);
    expect(profile['placementLevel'], repo.completedLevel!.wireValue);

    // Confirmation shown; the router advances to home off the persisted flag.
    expect(find.textContaining("You're all set"), findsOneWidget);
  });
}
