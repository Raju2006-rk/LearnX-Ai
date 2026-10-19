import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/placement_controller.dart';
import 'widgets/onboarding_scaffold.dart';

/// The adaptive placement step of onboarding, reached after the level/goal/
/// native-language draft is saved. (Requirements 2.4, 2.5, 2.6)
///
/// Watches [placementControllerProvider] and renders the current phase: a
/// loading state while the first/next question is fetched, the current question
/// with its options, a brief "all set" confirmation once the level is stored
/// (the router then routes to home off the persisted `onboarded` flag), or a
/// retryable error. Options are plain tappable tiles; tapping one submits the
/// answer, which the server grades.
class PlacementStep extends ConsumerWidget {
  const PlacementStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(placementControllerProvider);
    final controller = ref.read(placementControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Placement'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: switch (state.phase) {
              PlacementPhase.loading ||
              PlacementPhase.finishing =>
                const _PlacementLoading(),
              PlacementPhase.submitting ||
              PlacementPhase.question =>
                _PlacementQuestionView(
                  state: state,
                  onAnswer: controller.submitAnswer,
                ),
              PlacementPhase.complete => _PlacementComplete(state: state),
              PlacementPhase.error => _PlacementError(
                  message: state.errorMessage ??
                      'Something went wrong. Please try again.',
                  onRetry: controller.retry,
                ),
            },
          ),
        ),
      ),
    );
  }
}

/// A centered progress indicator shown while a question is being fetched or
/// the final result is being saved.
class _PlacementLoading extends StatelessWidget {
  const _PlacementLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Preparing your placement…', textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// Renders the current question prompt and its tappable options, plus a
/// progress label. Options are disabled while an answer is being graded.
class _PlacementQuestionView extends StatelessWidget {
  const _PlacementQuestionView({
    required this.state,
    required this.onAnswer,
  });

  final PlacementViewState state;
  final ValueChanged<int> onAnswer;

  @override
  Widget build(BuildContext context) {
    final question = state.question;
    if (question == null) return const _PlacementLoading();

    final submitting = state.phase == PlacementPhase.submitting;
    final current = (state.askedCount + 1).clamp(1, state.totalQuestions);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Question $current of ${state.totalQuestions}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                question.prompt,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < question.options.length; i++)
                OnboardingChoiceTile(
                  title: question.options[i],
                  selected: false,
                  onTap: submitting ? () {} : () => onAnswer(i),
                ),
              if (submitting) ...[
                const SizedBox(height: 16),
                const Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A brief confirmation shown once the placement level is stored and the
/// profile is marked onboarded. The router advances to home off the persisted
/// flag, so no explicit navigation is needed here.
class _PlacementComplete extends StatelessWidget {
  const _PlacementComplete({required this.state});

  final PlacementViewState state;

  @override
  Widget build(BuildContext context) {
    final level = state.assignedLevel?.wireValue;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 48),
          const SizedBox(height: 16),
          Text(
            level == null
                ? "You're all set!"
                : "You're all set — we placed you at $level.",
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Taking you to your learning path…',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// A retryable error state shown when a question fetch or the final save fails.
class _PlacementError extends StatelessWidget {
  const _PlacementError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: scheme.error),
          const SizedBox(height: 16),
          Text(
            message,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
