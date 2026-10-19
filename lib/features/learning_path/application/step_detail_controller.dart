import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/path_providers.dart';
import '../domain/learning_path.dart';
import '../domain/step_content.dart';

/// Loads a single step's detail — the authored skeleton combined with AI
/// personalization — keyed by step id. (Requirements 3.5, 3.6)
///
/// The provider always loads the authored skeleton first; only once the
/// skeleton is in hand does it request `personalizeLesson` and *append* the
/// returned AI examples and practice. Because personalization is layered on
/// top of the skeleton (and the repository maps any failure/refusal to an
/// empty personalization), the authored skeleton is always present in the
/// resolved [StepContent], satisfying the skeleton-always-present invariant
/// (design Property 7). A failure to load the skeleton itself surfaces as an
/// error [AsyncValue] the UI can retry; a failure to personalize never fails
/// the step open — it falls back to the skeleton alone (Requirement 3.6).
///
/// This is a [FutureProvider.family] rather than a stateful notifier because
/// the step detail is a pure read: completion is driven through the shared
/// `PathController` (which owns the completion write and the next-step unlock),
/// so there is no per-step mutable state to hold here.
final stepDetailControllerProvider = FutureProvider.family<StepContent, String>(
  (ref, stepId) async {
    final repository = ref.watch(pathRepositoryProvider);

    final contentResult = await repository.loadStepContent(
      pathId: kDefaultPathId,
      stepId: stepId,
    );
    final content = contentResult.fold(
      (value) => value,
      (exception) => throw exception,
    );

    final personalizationResult = await repository.personalizeStep(
      stepId: stepId,
    );
    // personalizeStep maps any failure/refusal to an empty personalization,
    // so this fold never throws; the skeleton is preserved either way.
    final personalization = personalizationResult.fold(
      (value) => value,
      (_) => StepPersonalization.empty,
    );

    return content.withPersonalization(personalization);
  },
  name: 'stepDetailControllerProvider',
);
