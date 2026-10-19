import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../data/path_providers.dart';
import '../data/path_repository.dart';
import '../domain/learning_path.dart';

/// Loads and drives the learner's learning path: the ordered sections/weeks/
/// steps with each step's resolved locked / available / completed state, plus
/// the step-completion action that unlocks the next step.
/// (Requirements 3.2, 3.3, 3.4)
///
/// The controller is an [AsyncNotifier] so the path screen can render the
/// three natural phases uniformly — loading, data, and a retryable error —
/// off the exposed [AsyncValue]. [build] resolves the path once for the
/// signed-in learner via [PathRepository.loadPath]; [completeStep] records a
/// completion and re-resolves so the derived state (and therefore the unlock)
/// is always read back from storage rather than guessed locally.
///
/// The learner's uid comes from the [authStateProvider] seam (overridable in
/// tests and the app's single source of auth identity). The path id is the
/// single MVP path ([kDefaultPathId]).
class PathController extends AsyncNotifier<StepProgress> {
  PathRepository get _repository => ref.read(pathRepositoryProvider);

  /// The signed-in learner's uid, or `null` when signed out.
  String? get _uid => ref.read(authStateProvider).uid;

  @override
  Future<StepProgress> build() => _load();

  /// Resolves the path for the current learner, throwing the typed
  /// [AppException] on failure so the surrounding [AsyncValue] carries it as
  /// an error the UI can render and retry.
  Future<StepProgress> _load() async {
    final uid = _uid;
    if (uid == null) {
      throw const AuthException('You need to be signed in to see your path.');
    }
    final result = await _repository.loadPath(uid: uid, pathId: kDefaultPathId);
    return result.fold((progress) => progress, (exception) => throw exception);
  }

  /// Re-resolves the path from storage, replacing the state with a loading
  /// value while the read is in flight. Used by the UI's retry action.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  /// Marks [stepId] completed for the current learner and re-resolves the
  /// path so the next step unlocks (Requirement 3.4).
  ///
  /// Only an [StepState.available] step may be completed; a request to
  /// complete a locked step (which the UI prevents starting, Requirement 3.3)
  /// or an already-completed step is ignored. On a write failure the current
  /// resolved path is kept and the failure surfaces as an error value the UI
  /// can retry, so a failed completion never drops the learner's view of the
  /// path.
  Future<void> completeStep(String stepId) async {
    final uid = _uid;
    if (uid == null) return;

    final current = state.value;
    if (current == null) return;

    final step = _findStep(current, stepId);
    if (step == null || step.state != StepState.available) return;

    final result = await _repository.completeStep(uid: uid, stepId: stepId);
    await result.fold((_) => refresh(), (exception) async {
      state = AsyncValue<StepProgress>.error(exception, StackTrace.current);
    });
  }

  /// Finds the step with [stepId] in the resolved [progress], or `null`.
  Step? _findStep(StepProgress progress, String stepId) {
    for (final step in progress.orderedSteps) {
      if (step.id == stepId) return step;
    }
    return null;
  }
}

/// Exposes the [PathController] and its asynchronous [StepProgress] to the
/// home learning-path UI.
final pathControllerProvider =
    AsyncNotifierProvider<PathController, StepProgress>(
      PathController.new,
      name: 'pathControllerProvider',
    );
