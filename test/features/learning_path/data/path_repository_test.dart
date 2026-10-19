// Unit tests for PathRepository: reading the authored skeleton from
// content/** and per-user pathProgress, and resolving step state.
// (Requirements 3.1, 3.2, 3.3, 3.4)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/learning_path/data/content_cache_data_source.dart';
import 'package:learnx/features/learning_path/data/path_repository.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';
import 'package:learnx/features/learning_path/domain/step_content.dart';
import 'package:mocktail/mocktail.dart';

import '../learning_path_test_support.dart';

/// A [FirebaseFirestore] whose every collection read throws a Firestore
/// `unavailable` error — the SDK's offline-read failure — so repository tests
/// can exercise the offline fallback path.
class _OfflineFirestore extends Mock implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'unavailable',
      message: 'The service is currently unavailable.',
    );
  }
}

void main() {
  late FakeFirebaseFirestore firestore;
  late PathRepository repository;

  const uid = 'user-123';
  const pathId = 'path-1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = PathRepository(
      firestore: firestore,
      aiClient: FakeAiFunctionClient(),
    );
  });

  /// Seeds a one-section, one-week authored path with [stepCount] steps named
  /// s1..sN (order 1..N).
  Future<void> seedAuthoredPath({int stepCount = 3}) async {
    await firestore.doc(FirestorePaths.sectionDoc(pathId, 'sec1')).set(
      <String, dynamic>{'title': 'Section 1', 'order': 0},
    );
    await firestore.doc(FirestorePaths.weekDoc(pathId, 'sec1', 'wk1')).set(
      <String, dynamic>{'title': 'Week 1', 'order': 0},
    );
    for (var i = 1; i <= stepCount; i++) {
      await firestore
          .doc(FirestorePaths.stepDoc(pathId, 'sec1', 'wk1', 's$i'))
          .set(<String, dynamic>{
            'title': 'Step $i',
            'order': i,
            'type': 'lesson',
            'contentVersion': 1,
          });
    }
  }

  Future<void> markCompleted(String stepId) async {
    await firestore.doc(FirestorePaths.pathProgressDoc(uid, stepId)).set(
      <String, dynamic>{'state': 'completed'},
    );
  }

  Map<String, StepState> statesOf(StepProgress progress) => <String, StepState>{
    for (final step in progress.orderedSteps) step.id: step.state,
  };

  test(
    'loadPath returns NotFound when the authored path has no sections',
    () async {
      final result = await repository.loadPath(uid: uid, pathId: pathId);

      expect(result, isA<Failure<StepProgress>>());
      expect(result.exceptionOrNull, isA<NotFoundException>());
    },
  );

  test('loadPath presents authored sections/weeks/steps (Req 3.1)', () async {
    await seedAuthoredPath(stepCount: 2);

    final result = await repository.loadPath(uid: uid, pathId: pathId);
    final progress = result.valueOrNull;

    expect(progress, isNotNull);
    expect(progress!.pathId, pathId);
    expect(progress.sections, hasLength(1));
    expect(progress.sections.single.weeks, hasLength(1));
    expect(progress.orderedSteps.map((s) => s.id).toList(), ['s1', 's2']);
    expect(progress.sections.single.title, 'Section 1');
  });

  test(
    'first step available, rest locked with no progress (Req 3.2/3.3)',
    () async {
      await seedAuthoredPath(stepCount: 3);

      final result = await repository.loadPath(uid: uid, pathId: pathId);

      expect(statesOf(result.valueOrNull!), {
        's1': StepState.available,
        's2': StepState.locked,
        's3': StepState.locked,
      });
    },
  );

  test('completed pathProgress unlocks the next step (Req 3.4)', () async {
    await seedAuthoredPath(stepCount: 3);
    await markCompleted('s1');

    final result = await repository.loadPath(uid: uid, pathId: pathId);

    expect(statesOf(result.valueOrNull!), {
      's1': StepState.completed,
      's2': StepState.available,
      's3': StepState.locked,
    });
  });

  test('non-completed stored progress does not unlock a step', () async {
    await seedAuthoredPath(stepCount: 3);
    // s1 has an "available" record but is not completed; s2 must stay locked.
    await firestore.doc(FirestorePaths.pathProgressDoc(uid, 's1')).set(
      <String, dynamic>{'state': 'available'},
    );

    final result = await repository.loadPath(uid: uid, pathId: pathId);

    expect(statesOf(result.valueOrNull!), {
      's1': StepState.available,
      's2': StepState.locked,
      's3': StepState.locked,
    });
  });

  test('progress is isolated per user', () async {
    await seedAuthoredPath(stepCount: 2);
    await markCompleted('s1'); // for `uid`

    final other = await repository.loadPath(uid: 'other-user', pathId: pathId);

    // The other learner sees no completion.
    expect(statesOf(other.valueOrNull!), {
      's1': StepState.available,
      's2': StepState.locked,
    });
  });

  test(
    'completeStep marks the step completed so reload unlocks next (Req 3.4)',
    () async {
      await seedAuthoredPath(stepCount: 3);

      final writeResult = await repository.completeStep(uid: uid, stepId: 's1');
      expect(writeResult, isA<Success<void>>());

      // The stored document reflects the completion.
      final snap = await firestore
          .doc(FirestorePaths.pathProgressDoc(uid, 's1'))
          .get();
      expect(snap.data()!['state'], 'completed');
      expect(snap.data()!['completedAt'], isNotNull);
      expect(snap.data()!['updatedAt'], isNotNull);

      // Re-resolving the path surfaces s2 as the newly available step.
      final result = await repository.loadPath(uid: uid, pathId: pathId);
      expect(statesOf(result.valueOrNull!), {
        's1': StepState.completed,
        's2': StepState.available,
        's3': StepState.locked,
      });
    },
  );

  test('completeStep merges, preserving unrelated fields on the doc', () async {
    await seedAuthoredPath(stepCount: 2);
    // A pre-existing field that must survive the merge write.
    await firestore.doc(FirestorePaths.pathProgressDoc(uid, 's1')).set(
      <String, dynamic>{'note': 'keep me', 'state': 'available'},
    );

    await repository.completeStep(uid: uid, stepId: 's1');

    final snap = await firestore
        .doc(FirestorePaths.pathProgressDoc(uid, 's1'))
        .get();
    expect(snap.data()!['state'], 'completed');
    expect(snap.data()!['note'], 'keep me');
  });

  test(
    'authored docs returned out of order are sorted by order field',
    () async {
      // Seed steps with ids that sort differently than their order fields.
      await firestore.doc(FirestorePaths.sectionDoc(pathId, 'sec1')).set(
        <String, dynamic>{'title': 'S', 'order': 0},
      );
      await firestore.doc(FirestorePaths.weekDoc(pathId, 'sec1', 'wk1')).set(
        <String, dynamic>{'title': 'W', 'order': 0},
      );
      await firestore
          .doc(FirestorePaths.stepDoc(pathId, 'sec1', 'wk1', 'zeta'))
          .set(<String, dynamic>{'title': 'Z', 'order': 3, 'type': 'lesson'});
      await firestore
          .doc(FirestorePaths.stepDoc(pathId, 'sec1', 'wk1', 'alpha'))
          .set(<String, dynamic>{'title': 'A', 'order': 1, 'type': 'lesson'});
      await firestore
          .doc(FirestorePaths.stepDoc(pathId, 'sec1', 'wk1', 'mid'))
          .set(<String, dynamic>{'title': 'M', 'order': 2, 'type': 'lesson'});

      final result = await repository.loadPath(uid: uid, pathId: pathId);
      final progress = result.valueOrNull!;

      expect(progress.orderedSteps.map((s) => s.id).toList(), [
        'alpha',
        'mid',
        'zeta',
      ]);
      expect(progress.orderedSteps.first.state, StepState.available);
    },
  );

  group('loadStepContent offline cache (Req 8.1)', () {
    const skeleton = StepSkeleton(
      objectives: ['Understand greetings'],
      examples: ['Hello!'],
      practice: ['Greet a friend.'],
    );

    /// Seeds a one-step authored path carrying a `skeleton` block and a
    /// `contentVersion`, returning that content version.
    Future<int> seedStepWithSkeleton({int contentVersion = 1}) async {
      await firestore.doc(FirestorePaths.sectionDoc(pathId, 'sec1')).set(
        <String, dynamic>{'title': 'Section 1', 'order': 0},
      );
      await firestore.doc(FirestorePaths.weekDoc(pathId, 'sec1', 'wk1')).set(
        <String, dynamic>{'title': 'Week 1', 'order': 0},
      );
      await firestore
          .doc(FirestorePaths.stepDoc(pathId, 'sec1', 'wk1', 's1'))
          .set(<String, dynamic>{
            'title': 'Greetings',
            'order': 1,
            'type': 'lesson',
            'contentVersion': contentVersion,
            'skeleton': <String, dynamic>{
              'objectives': skeleton.objectives,
              'examples': skeleton.examples,
              'practice': skeleton.practice,
            },
          });
      return contentVersion;
    }

    test('a successful read caches the skeleton by contentVersion', () async {
      final cache = ContentCacheDataSource();
      repository = PathRepository(
        firestore: firestore,
        aiClient: FakeAiFunctionClient(),
        contentCache: cache,
      );
      final version = await seedStepWithSkeleton(contentVersion: 4);

      final result = await repository.loadStepContent(
        pathId: pathId,
        stepId: 's1',
      );

      expect(result, isA<Success<StepContent>>());
      expect(result.valueOrNull!.skeleton, skeleton);
      // The skeleton is now cached at the exact version it was read at.
      final cached = cache.lookup(stepId: 's1', contentVersion: version);
      expect(cached, isNotNull);
      expect(cached!.skeleton, skeleton);
      expect(cached.title, 'Greetings');
    });

    test(
      'serves the cached skeleton when the live read fails offline',
      () async {
        // Pre-seed the cache as if the step had been opened online before.
        final cache = ContentCacheDataSource()
          ..cache(
            stepId: 's1',
            contentVersion: 2,
            title: 'Greetings',
            skeleton: skeleton,
          );
        // The firestore read now fails offline.
        final offlineRepo = PathRepository(
          firestore: _OfflineFirestore(),
          aiClient: FakeAiFunctionClient(),
          contentCache: cache,
        );

        final result = await offlineRepo.loadStepContent(
          pathId: pathId,
          stepId: 's1',
        );

        expect(result, isA<Success<StepContent>>());
        final content = result.valueOrNull!;
        expect(content.skeleton, skeleton);
        expect(content.title, 'Greetings');
        // The authored skeleton is fully present for offline read/practice.
        expect(content.containsSkeleton, isTrue);
      },
    );

    test(
      'offline read with nothing cached surfaces a NetworkException',
      () async {
        final offlineRepo = PathRepository(
          firestore: _OfflineFirestore(),
          aiClient: FakeAiFunctionClient(),
          contentCache: ContentCacheDataSource(),
        );

        final result = await offlineRepo.loadStepContent(
          pathId: pathId,
          stepId: 's1',
        );

        expect(result, isA<Failure<StepContent>>());
        expect(result.exceptionOrNull, isA<NetworkException>());
      },
    );
  });
}
