// Unit tests for PathController: resolving the learner's path and the
// step-completion action that unlocks the next step.
// (Requirements 3.2, 3.3, 3.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/learning_path/application/path_controller.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';

import '../learning_path_test_support.dart';

void main() {
  const uid = 'learner-1';

  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  /// Seeds the single MVP path with [stepCount] linear steps s1..sN.
  Future<void> seedPath({int stepCount = 3}) async {
    await firestore.doc(FirestorePaths.sectionDoc(kDefaultPathId, 'sec1')).set(
      <String, dynamic>{'title': 'Section 1', 'order': 0},
    );
    await firestore
        .doc(FirestorePaths.weekDoc(kDefaultPathId, 'sec1', 'wk1'))
        .set(<String, dynamic>{'title': 'Week 1', 'order': 0});
    for (var i = 1; i <= stepCount; i++) {
      await firestore
          .doc(FirestorePaths.stepDoc(kDefaultPathId, 'sec1', 'wk1', 's$i'))
          .set(<String, dynamic>{
            'title': 'Step $i',
            'order': i,
            'type': 'lesson',
          });
    }
  }

  ProviderContainer makeContainer({String? signedInUid = uid}) {
    final container = ProviderContainer(
      overrides: [
        firebaseFirestoreProvider.overrideWithValue(firestore),
        aiFunctionClientProvider.overrideWithValue(FakeAiFunctionClient()),
        authStateProvider.overrideWithValue(
          signedInUid == null
              ? const AuthState.signedOut()
              : AuthState(uid: signedInUid),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Map<String, StepState> statesOf(StepProgress progress) => <String, StepState>{
    for (final step in progress.orderedSteps) step.id: step.state,
  };

  test('build resolves the path with first step available (Req 3.2)', () async {
    await seedPath(stepCount: 3);
    final container = makeContainer();

    final progress = await container.read(pathControllerProvider.future);

    expect(statesOf(progress), {
      's1': StepState.available,
      's2': StepState.locked,
      's3': StepState.locked,
    });
  });

  test('build errors when signed out', () async {
    await seedPath();
    final container = makeContainer(signedInUid: null);

    // Kick off the async build and wait for it to settle.
    container.listen(pathControllerProvider, (previous, next) {});
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(pathControllerProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<AppException>());
  });

  test(
    'completeStep marks the step done and unlocks the next (Req 3.4)',
    () async {
      await seedPath(stepCount: 3);
      final container = makeContainer();
      await container.read(pathControllerProvider.future);

      await container.read(pathControllerProvider.notifier).completeStep('s1');

      final progress = container.read(pathControllerProvider).value!;
      expect(statesOf(progress), {
        's1': StepState.completed,
        's2': StepState.available,
        's3': StepState.locked,
      });
    },
  );

  test('completeStep ignores a locked step (Req 3.3)', () async {
    await seedPath(stepCount: 3);
    final container = makeContainer();
    await container.read(pathControllerProvider.future);

    // s2 is locked; completing it must be a no-op.
    await container.read(pathControllerProvider.notifier).completeStep('s2');

    final progress = container.read(pathControllerProvider).value!;
    expect(statesOf(progress), {
      's1': StepState.available,
      's2': StepState.locked,
      's3': StepState.locked,
    });
    // Nothing was written for s2.
    final snap = await firestore
        .doc(FirestorePaths.pathProgressDoc(uid, 's2'))
        .get();
    expect(snap.exists, isFalse);
  });

  test('completeStep is a no-op for an already-completed step', () async {
    await seedPath(stepCount: 2);
    final container = makeContainer();
    await container.read(pathControllerProvider.future);

    await container.read(pathControllerProvider.notifier).completeStep('s1');
    // Completing s1 again does nothing (it is no longer available).
    await container.read(pathControllerProvider.notifier).completeStep('s1');

    final progress = container.read(pathControllerProvider).value!;
    expect(statesOf(progress), {
      's1': StepState.completed,
      's2': StepState.available,
    });
  });
}
