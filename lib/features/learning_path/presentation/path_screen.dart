import 'package:flutter/material.dart' hide Step, StepState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/app_exception_view.dart';
import '../../../shared/widgets/app_state_view.dart';
import '../../progress/presentation/streak_flame_indicator.dart';
import '../application/path_controller.dart';
import '../domain/learning_path.dart';

/// The home learning-path screen: the learner's authored path rendered as a
/// sequence of step circles, each reflecting its locked / available /
/// completed state. (Requirements 3.2, 3.3, 3.4)
///
/// Watches [pathControllerProvider] and renders the loading, error, and data
/// phases uniformly. In the data phase every step is a circle
/// ([PathStepCircle]): completed steps show a check, the available step is
/// highlighted and tappable, and locked steps are dimmed with a lock icon and
/// cannot be started (Requirement 3.3). Tapping an available step opens its
/// detail screen, which combines the authored skeleton with AI personalization
/// and records completion (which unlocks the next step, Requirement 3.4).
/// Completed steps re-open their detail (read-only review); locked steps
/// surface a brief explanation and cannot be started.
///
/// The app bar carries a [StreakFlameIndicator] showing the learner's current
/// streak — the flame that lights up on the first qualifying activity of a
/// calendar day. The streak count is computed and persisted by the Progress
/// feature (tasks 9/10) and read here through the progress provider seam.
/// (Requirement 3.7)
class PathScreen extends ConsumerWidget {
  const PathScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pathAsync = ref.watch(pathControllerProvider);
    final controller = ref.read(pathControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('LearnX'),
        actions: const [StreakFlameIndicator()],
      ),
      body: SafeArea(
        child: switch (pathAsync) {
          AsyncData(:final value) => _PathList(
            progress: value,
            onStartStep: (step) => _onStartStep(context, step),
          ),
          AsyncError(:final error) => _pathError(
            error,
            onRetry: controller.refresh,
          ),
          _ => const LoadingStateView(),
        },
      ),
    );
  }

  /// Handles a tap on a step circle: available (and completed) steps open the
  /// step-detail screen, where the skeleton + personalization render and the
  /// learner can mark the step complete (unlocking the next step); locked
  /// steps are non-startable and surface a brief explanation.
  void _onStartStep(BuildContext context, Step step) {
    switch (step.state) {
      case StepState.available:
      case StepState.completed:
        context.go(Routes.stepDetail(step.id));
      case StepState.locked:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Finish the previous step to unlock this one.'),
            ),
          );
    }
  }

  /// The error view for a failed path load. A typed [AppException] is handed to
  /// the shared [AppExceptionView], which maps each failure kind to a
  /// consistent view and decides whether a retry is safe; an untyped error
  /// falls back to a generic retryable [ErrorStateView].
  Widget _pathError(Object error, {required VoidCallback onRetry}) {
    if (error is AppException) {
      return AppExceptionView(exception: error, onRetry: onRetry);
    }
    return ErrorStateView(
      message: 'Could not load your learning path.',
      onRetry: onRetry,
    );
  }
}

/// The scrollable list of the path's sections, weeks, and step circles.
class _PathList extends StatelessWidget {
  const _PathList({required this.progress, required this.onStartStep});

  final StepProgress progress;
  final ValueChanged<Step> onStartStep;

  @override
  Widget build(BuildContext context) {
    final sections = progress.sections;
    if (sections.isEmpty) {
      return const Center(child: Text('Your learning path is empty.'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final section in sections) ...[
          _SectionHeader(title: section.title),
          for (final week in section.weeks) ...[
            _WeekHeader(title: week.title),
            for (final step in week.steps)
              PathStepCircle(step: step, onTap: () => onStartStep(step)),
          ],
        ],
      ],
    );
  }
}

/// A section title header.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

/// A week title sub-header.
class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A single learning-path step rendered as a circle whose appearance and
/// interactivity reflect its [StepState]. (Requirements 3.2, 3.3)
///
/// - [StepState.completed]: a filled primary circle with a check.
/// - [StepState.available]: an outlined, highlighted circle; tappable to
///   start the step.
/// - [StepState.locked]: a dimmed circle with a lock icon; not startable, so
///   [onTap] still fires but the screen declines to start it.
///
/// The circle exposes a button semantics node with its state so assistive
/// tech announces whether the step can be started.
class PathStepCircle extends StatelessWidget {
  const PathStepCircle({super.key, required this.step, required this.onTap});

  final Step step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final (background, foreground, border, icon) = switch (step.state) {
      StepState.completed => (
        scheme.primary,
        scheme.onPrimary,
        scheme.primary,
        Icons.check,
      ),
      StepState.available => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        scheme.primary,
        Icons.play_arrow,
      ),
      StepState.locked => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        scheme.outlineVariant,
        Icons.lock_outline,
      ),
    };

    return Semantics(
      button: true,
      enabled: step.state.isStartable,
      label: '${step.title}, ${_semanticState(step.state)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Opacity(
            opacity: step.state == StepState.locked ? 0.6 : 1,
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: background,
                    shape: BoxShape.circle,
                    border: Border.all(color: border, width: 2),
                  ),
                  child: Icon(icon, color: foreground, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    step.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _semanticState(StepState state) => switch (state) {
    StepState.completed => 'completed',
    StepState.available => 'available, double tap to start',
    StepState.locked => 'locked',
  };
}
