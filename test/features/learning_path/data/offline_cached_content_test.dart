// Hardening test: offline read of cached authored content, end to end.
// (Task 12.3; Requirement 8.1)
//
// path_repository_test.dart covers the offline fallback with a pre-seeded
// cache. This test instead exercises the full round-trip a learner actually
// takes: open a step online (which caches its authored skeleton), then open it
// again while the device is offline and confirm the repository serves the
// cached skeleton for read/practice instead of surfacing a network error — and
// that a *different*, never-opened step still fails offline because nothing was
// cached for it. The two repositories share one ContentCacheDataSource, the way
// the app wires it as a single app-lifetime instance.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/learning_path/data/content_cache_data_source.dart';
import 'package:learnx/features/learning_path/data/path_repository.dart';
import 'package:learnx/features/learning_path/domain/step_content.dart';
import 'package:mocktail/mocktail.dart';

import '../learning_path_test_support.dart';

/// A [FirebaseFirestore] whose every collection read throws the SDK's
/// offline-read failure, so a repository backed by it behaves as if the device
/// has no connection. (Mirrors path_repository_test's offline double.)
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
  const pathId = 'path-1';
  const skeleton = StepSkeleton(
    objectives: ['Greet politely'],
    examples: ['Good morning!'],
    practice: ['Greet a classmate.'],
  );

  late FakeFirebaseFirestore onlineFirestore;
  late ContentCacheDataSource sharedCache;

  setUp(() {
    onlineFirestore = FakeFirebaseFirestore();
    // One shared, app-lifetime cache instance across the online and offline
    // repositories, as path_providers wires it.
    sharedCache = ContentCacheDataSource();
  });

  Future<void> seedStep(String stepId, {int contentVersion = 1}) async {
    await onlineFirestore.doc(FirestorePaths.sectionDoc(pathId, 'sec1')).set(
      <String, dynamic>{'title': 'Section 1', 'order': 0},
    );
    await onlineFirestore
        .doc(FirestorePaths.weekDoc(pathId, 'sec1', 'wk1'))
        .set(<String, dynamic>{'title': 'Week 1', 'order': 0});
    await onlineFirestore
        .doc(FirestorePaths.stepDoc(pathId, 'sec1', 'wk1', stepId))
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
  }

  test(
    'a step opened online stays readable offline from the shared cache (Req 8.1)',
    () async {
      await seedStep('s1');

      // 1) Online open: reads the authored skeleton and caches it.
      final onlineRepo = PathRepository(
        firestore: onlineFirestore,
        aiClient: FakeAiFunctionClient(),
        contentCache: sharedCache,
      );
      final onlineResult = await onlineRepo.loadStepContent(
        pathId: pathId,
        stepId: 's1',
      );
      expect(onlineResult, isA<Success<StepContent>>());
      expect(onlineResult.valueOrNull!.skeleton, skeleton);

      // 2) Offline open of the same step: the live read fails, but the shared
      // cache serves the previously read skeleton for offline read/practice.
      final offlineRepo = PathRepository(
        firestore: _OfflineFirestore(),
        aiClient: FakeAiFunctionClient(),
        contentCache: sharedCache,
      );
      final offlineResult = await offlineRepo.loadStepContent(
        pathId: pathId,
        stepId: 's1',
      );

      expect(offlineResult, isA<Success<StepContent>>());
      final content = offlineResult.valueOrNull!;
      expect(content.title, 'Greetings');
      expect(content.skeleton, skeleton);
      expect(content.containsSkeleton, isTrue);
    },
  );

  test(
    'a step never opened online still fails offline with a NetworkException',
    () async {
      await seedStep('s1');

      // Open s1 online so the cache holds *that* step.
      final onlineRepo = PathRepository(
        firestore: onlineFirestore,
        aiClient: FakeAiFunctionClient(),
        contentCache: sharedCache,
      );
      await onlineRepo.loadStepContent(pathId: pathId, stepId: 's1');

      // A different step was never opened, so nothing is cached for it; an
      // offline open surfaces a network error rather than wrong content.
      final offlineRepo = PathRepository(
        firestore: _OfflineFirestore(),
        aiClient: FakeAiFunctionClient(),
        contentCache: sharedCache,
      );
      final result = await offlineRepo.loadStepContent(
        pathId: pathId,
        stepId: 's2-never-opened',
      );

      expect(result, isA<Failure<StepContent>>());
      expect(result.exceptionOrNull, isA<NetworkException>());
    },
  );
}
