// Unit tests for PlacementRepository: mapping the server callable payload into
// domain results, mapping non-ok statuses to typed failures, and persisting
// the placement result. (Requirements 2.4, 2.5, 2.6)

import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/onboarding/data/placement_repository.dart';
import 'package:learnx/features/onboarding/domain/placement_engine.dart';
import 'package:learnx/features/onboarding/domain/placement_question.dart';

/// A fake [AiFunctionClient] that returns a canned payload or throws, recording
/// the arguments of the last call so assertions can check the wire shape.
class _FakeAiFunctionClient extends AiFunctionClient {
  _FakeAiFunctionClient({this.response, this.error})
      : super(_UnusedFunctions());

  final Map<String, dynamic>? response;
  final Object? error;

  String? lastName;
  Map<String, dynamic>? lastData;

  @override
  Future<Map<String, dynamic>> call(String name,
      [Map<String, dynamic>? data]) async {
    lastName = name;
    lastData = data;
    if (error != null) throw error!;
    return response ?? <String, dynamic>{};
  }
}

/// Stand-in for the [FirebaseFunctions] the base client needs; never invoked
/// because [_FakeAiFunctionClient.call] is overridden.
class _UnusedFunctions implements FirebaseFunctions {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FirebaseFunctions is not used in this fake');
}

void main() {
  const uid = 'user-123';

  Map<String, dynamic> okResponse({
    String questionId = 'q1',
    String band = 'A2',
    List<Object?>? gradedAnswers,
  }) {
    return <String, dynamic>{
      'status': 'ok',
      'result': <String, dynamic>{
        'question': <String, dynamic>{
          'questionId': questionId,
          'band': band,
          'prompt': 'Choose the correct word.',
          'options': <String>['a', 'b', 'c'],
        },
        'gradedAnswers': gradedAnswers ?? const <Object?>[],
      },
    };
  }

  group('nextQuestion', () {
    test('sends the band and prior answers, returns the parsed question',
        () async {
      final client = _FakeAiFunctionClient(response: okResponse());
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.nextQuestion(
        band: CefrLevel.a2,
        priorAnswers: const [
          PlacementAnswer(questionId: 'q0', selectedIndex: 2),
        ],
      );

      expect(client.lastName, PlacementRepository.callableName);
      final sessionState =
          client.lastData!['sessionState'] as Map<String, dynamic>;
      expect(sessionState['band'], 'A2');
      expect(sessionState['priorAnswers'], [
        {'questionId': 'q0', 'selectedIndex': 2},
      ]);

      expect(result, isA<Success<PlacementQuestionResult>>());
      final payload = result.valueOrNull!;
      expect(payload.question.questionId, 'q1');
      expect(payload.question.band, CefrLevel.a2);
      expect(payload.question.options, ['a', 'b', 'c']);
    });

    test('omits priorAnswers when none are provided', () async {
      final client = _FakeAiFunctionClient(response: okResponse());
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      await repo.nextQuestion(band: CefrLevel.b1);

      final sessionState =
          client.lastData!['sessionState'] as Map<String, dynamic>;
      expect(sessionState.containsKey('priorAnswers'), isFalse);
      expect(sessionState['band'], 'B1');
    });

    test('parses graded answers (correctness only)', () async {
      final client = _FakeAiFunctionClient(
        response: okResponse(gradedAnswers: [
          {'questionId': 'q0', 'correct': true},
        ]),
      );
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.nextQuestion(
        band: CefrLevel.a2,
        priorAnswers: const [
          PlacementAnswer(questionId: 'q0', selectedIndex: 0),
        ],
      );

      expect(result.valueOrNull!.gradedAnswers, [
        const PlacementGrade(questionId: 'q0', correct: true),
      ]);
    });

    test('limit_reached status maps to UsageLimitException', () async {
      final client = _FakeAiFunctionClient(
        response: <String, dynamic>{'status': 'limit_reached', 'limit': 5},
      );
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.nextQuestion(band: CefrLevel.a2);
      expect(result.exceptionOrNull, isA<UsageLimitException>());
    });

    test('refusal status maps to ModerationRefusalException', () async {
      final client = _FakeAiFunctionClient(
        response: <String, dynamic>{
          'status': 'refusal',
          'safeMessage': 'Blocked.',
        },
      );
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.nextQuestion(band: CefrLevel.a2);
      expect(result.exceptionOrNull, isA<ModerationRefusalException>());
      expect(result.exceptionOrNull!.message, 'Blocked.');
    });

    test('a malformed question fails rather than returning a broken question',
        () async {
      final client = _FakeAiFunctionClient(
        response: <String, dynamic>{
          'status': 'ok',
          'result': <String, dynamic>{
            'question': <String, dynamic>{
              'questionId': 'q1',
              'band': 'A2',
              'prompt': 'Only one option',
              'options': <String>['just one'],
            },
            'gradedAnswers': const <Object?>[],
          },
        },
      );
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.nextQuestion(band: CefrLevel.a2);
      expect(result.isFailure, isTrue);
    });

    test('a thrown FirebaseFunctionsException maps to a typed failure',
        () async {
      final client = _FakeAiFunctionClient(
        error: FirebaseFunctionsException(
          message: 'offline',
          code: 'unavailable',
        ),
      );
      final repo = PlacementRepository(
        aiClient: client,
        firestore: FakeFirebaseFirestore(),
      );

      final result = await repo.nextQuestion(band: CefrLevel.a2);
      expect(result.exceptionOrNull, isA<NetworkException>());
    });
  });

  group('completePlacement', () {
    test('stores placementLevel, refines englishLevel, and marks onboarded',
        () async {
      final firestore = FakeFirebaseFirestore();
      // A prior draft exists; the merge write must preserve goal/language.
      await firestore.doc(FirestorePaths.profileDoc(uid)).set(<String, dynamic>{
        'goal': 'job',
        'nativeLanguage': 'hi',
      });
      final repo = PlacementRepository(
        aiClient: _FakeAiFunctionClient(),
        firestore: firestore,
      );

      final result =
          await repo.completePlacement(uid: uid, level: CefrLevel.b2);

      expect(result, isA<Success<void>>());
      final profile =
          (await firestore.doc(FirestorePaths.profileDoc(uid)).get()).data();
      expect(profile!['placementLevel'], 'B2');
      expect(profile['englishLevel'], 'B2');
      expect(profile['onboarded'], isTrue);
      // Draft fields preserved by the merge write.
      expect(profile['goal'], 'job');
      expect(profile['nativeLanguage'], 'hi');
    });
  });

  group('watchOnboarded', () {
    // This lives on OnboardingRepository; verified in its own test. Here we
    // confirm completePlacement produces an onboarded profile a watcher sees.
    test('completePlacement result is observable as onboarded == true',
        () async {
      final firestore = FakeFirebaseFirestore();
      final repo = PlacementRepository(
        aiClient: _FakeAiFunctionClient(),
        firestore: firestore,
      );

      await repo.completePlacement(uid: uid, level: CefrLevel.a1);
      final snap = await firestore.doc(FirestorePaths.profileDoc(uid)).get();
      expect(snap.data()!['onboarded'], isTrue);
    });
  });
}
