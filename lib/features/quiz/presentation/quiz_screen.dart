import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/app_exception_view.dart';
import '../../../shared/widgets/app_state_view.dart';
import '../application/quiz_controller.dart';
import '../domain/quiz.dart';

/// The daily quiz screen: presents fill-in-the-blank and choose-the-right-word
/// questions one at a time and, once every question is answered, a results view
/// showing the correct and wrong counts. (Requirements 6.1, 6.2)
///
/// Watches [quizControllerProvider] and renders each [QuizPhase] uniformly off
/// the exposed [AsyncValue]:
///
/// - [QuizPhase.loading] (and the async loading phase) → a shared
///   [LoadingStateView] spinner.
/// - [QuizPhase.inProgress] → the current question via [_QuestionView], which
///   renders a text field for [QuestionType.fillBlank] and option buttons for
///   [QuestionType.chooseWord].
/// - [QuizPhase.results] → [_ResultsView] with the correct/wrong tallies and a
///   replay action. (Requirement 6.2)
/// - [QuizPhase.empty] → a shared [EmptyStateView] "all caught up" message.
/// - [QuizPhase.offline] → a shared [OfflineStateView] network-required message
///   with a retry action, shown when a session is started while the device is
///   offline. Quizzes are network-required. (Requirements 6.6, 8.4)
/// - [QuizPhase.error] (and the async error phase) → a shared [ErrorStateView]
///   retryable error view.
class QuizScreen extends ConsumerWidget {
  const QuizScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quizAsync = ref.watch(quizControllerProvider);
    final controller = ref.read(quizControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Quiz')),
      body: SafeArea(
        child: switch (quizAsync) {
          AsyncData(:final value) => _QuizBody(
            state: value,
            onAnswer: controller.answer,
            onRestart: controller.restart,
          ),
          AsyncError() => ErrorStateView(
            message: 'Could not load your quiz.',
            onRetry: controller.restart,
          ),
          _ => const LoadingStateView(),
        },
      ),
    );
  }
}

/// Dispatches on the resolved [QuizState.phase] to the matching view.
class _QuizBody extends StatelessWidget {
  const _QuizBody({
    required this.state,
    required this.onAnswer,
    required this.onRestart,
  });

  final QuizState state;
  final ValueChanged<String> onAnswer;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return switch (state.phase) {
      QuizPhase.loading => const LoadingStateView(),
      QuizPhase.inProgress => _QuestionView(
        // Keying by index rebuilds the input state (cleared text field /
        // unselected options) when the session advances to the next question.
        key: ValueKey<int>(state.index),
        state: state,
        onAnswer: onAnswer,
      ),
      QuizPhase.results => _ResultsView(state: state, onRestart: onRestart),
      QuizPhase.empty => const EmptyStateView(
        icon: Icons.check_circle_outline,
        message: "You're all caught up. No quiz questions right now.",
      ),
      // Quizzes are network-required: when offline, tell the learner to
      // reconnect rather than leaving them on a view that cannot load.
      // Retry reruns the load so reconnecting and tapping again starts the
      // session. (Requirements 6.6, 8.4)
      QuizPhase.offline => OfflineStateView(
        message:
            state.errorMessage ??
            'Quizzes require a network connection. Reconnect and try again.',
        onRetry: onRestart,
      ),
      QuizPhase.error => ErrorStateView(
        message: state.errorMessage ?? 'Could not load your quiz.',
        onRetry: onRestart,
      ),
    };
  }
}

/// Presents the current question with the input appropriate to its type:
/// a text field for [QuestionType.fillBlank] and option buttons for
/// [QuestionType.chooseWord]. (Requirement 6.1)
class _QuestionView extends StatefulWidget {
  const _QuestionView({super.key, required this.state, required this.onAnswer});

  final QuizState state;
  final ValueChanged<String> onAnswer;

  @override
  State<_QuestionView> createState() => _QuestionViewState();
}

class _QuestionViewState extends State<_QuestionView> {
  final TextEditingController _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _submitText() {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    widget.onAnswer(text);
  }

  @override
  Widget build(BuildContext context) {
    final question = widget.state.currentQuestion;
    // Defensive: the body only builds this view while in progress, so a
    // current question is always present, but guard against a race.
    if (question == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ProgressLabel(
            current: widget.state.answeredCount + 1,
            total: widget.state.totalCount,
          ),
          const SizedBox(height: 16),
          Text(
            question.prompt,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          switch (question.type) {
            QuestionType.fillBlank => _FillBlankInput(
              controller: _input,
              onSubmit: _submitText,
            ),
            QuestionType.chooseWord => _ChooseWordOptions(
              options: question.options,
              onSelect: widget.onAnswer,
            ),
          },
        ],
      ),
    );
  }
}

/// A one-based "Question X of Y" progress label.
class _ProgressLabel extends StatelessWidget {
  const _ProgressLabel({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Question $current of $total',
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The fill-in-the-blank input: a text field plus a submit button.
/// (Requirement 6.1)
class _FillBlankInput extends StatelessWidget {
  const _FillBlankInput({required this.controller, required this.onSubmit});

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
            hintText: 'Type your answer',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onSubmit, child: const Text('Submit')),
      ],
    );
  }
}

/// The choose-the-right-word input: one button per option. (Requirement 6.1)
class _ChooseWordOptions extends StatelessWidget {
  const _ChooseWordOptions({required this.options, required this.onSelect});

  final List<String> options;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: OutlinedButton(
              onPressed: () => onSelect(option),
              child: Text(option),
            ),
          ),
      ],
    );
  }
}

/// The results view shown once every question is answered: the correct and
/// wrong counts plus a replay action. (Requirement 6.2)
class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.state, required this.onRestart});

  final QuizState state;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Quiz complete',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            _ScoreTile(
              icon: Icons.check_circle,
              color: Colors.green,
              label: 'Correct',
              count: state.correctCount,
            ),
            const SizedBox(height: 12),
            _ScoreTile(
              icon: Icons.cancel,
              color: scheme.error,
              label: 'Wrong',
              count: state.wrongCount,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: onRestart,
              child: const Text('Take another quiz'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single labelled score row (an icon, a label, and a count) used for the
/// correct and wrong tallies on the results view. (Requirement 6.2)
class _ScoreTile extends StatelessWidget {
  const _ScoreTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Text(
            '$label: $count',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
  }
}
