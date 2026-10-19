import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/app_exception_view.dart';
import '../../../shared/widgets/app_state_view.dart';
import '../application/path_controller.dart';
import '../application/step_detail_controller.dart';
import '../domain/step_content.dart';

/// The step-detail screen: the authored skeleton for a step combined with AI
/// personalization. (Requirements 3.5, 3.6)
///
/// Opened from an available step on the path. It watches the
/// [stepDetailControllerProvider] for its [stepId] and renders the loading,
/// error, and data phases uniformly. In the data phase the authored skeleton
/// (objectives, examples, practice) is **always** rendered; any AI-personalized
/// examples/practice are appended to their sections, never replacing the
/// skeleton (design Property 7). When no personalization is returned — because
/// the AI_Proxy failed or withheld it — the screen simply shows the authored
/// skeleton alone (Requirement 3.6). Completing the step records the completion
/// and unlocks the next step before returning to the path.
class StepDetailScreen extends ConsumerWidget {
  const StepDetailScreen({super.key, required this.stepId});

  /// The authored step id to show detail for.
  final String stepId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contentAsync = ref.watch(stepDetailControllerProvider(stepId));

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (contentAsync) {
          AsyncData(:final value) => value.title,
          _ => 'Step',
        }),
      ),
      body: SafeArea(
        child: switch (contentAsync) {
          AsyncData(:final value) => _StepBody(
            content: value,
            onComplete: () => _onComplete(context, ref),
          ),
          AsyncError(:final error) => _stepError(
            error,
            onRetry: () => ref.invalidate(stepDetailControllerProvider(stepId)),
          ),
          _ => const LoadingStateView(),
        },
      ),
    );
  }

  /// Records completion of this step through the shared [PathController]
  /// (which guards that the step is available, writes the completion, and
  /// unlocks the next step), then returns to the path. Completing an already
  /// completed or non-available step is a no-op in the controller; the screen
  /// still pops so review-opening a completed step can be dismissed.
  Future<void> _onComplete(BuildContext context, WidgetRef ref) async {
    await ref.read(pathControllerProvider.notifier).completeStep(stepId);
    if (!context.mounted) return;
    Navigator.of(context).maybePop();
  }

  /// The error view for a failed load. A typed [AppException] is handed to the
  /// shared [AppExceptionView], which maps each failure kind to a consistent
  /// view and decides whether a retry is safe (so, e.g., a usage limit shows
  /// no retry while a network error does). An untyped error falls back to a
  /// generic retryable [ErrorStateView].
  Widget _stepError(Object error, {required VoidCallback onRetry}) {
    if (error is AppException) {
      return AppExceptionView(exception: error, onRetry: onRetry);
    }
    return ErrorStateView(
      message: 'Could not load this step.',
      onRetry: onRetry,
    );
  }
}

/// The scrollable body rendering the authored skeleton plus any AI additions.
class _StepBody extends StatelessWidget {
  const _StepBody({required this.content, required this.onComplete});

  final StepContent content;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (content.objectives.isNotEmpty)
                _ContentSection(title: 'Objectives', items: content.objectives),
              if (content.examples.isNotEmpty)
                _ContentSection(title: 'Examples', items: content.examples),
              if (content.practice.isNotEmpty)
                _ContentSection(title: 'Practice', items: content.practice),
              if (content.hasPersonalization)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Includes examples tailored to you.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onComplete,
              child: const Text('Mark complete'),
            ),
          ),
        ),
      ],
    );
  }
}

/// A titled list of content items (objectives, examples, or practice).
class _ContentSection extends StatelessWidget {
  const _ContentSection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
