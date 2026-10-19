import 'package:flutter/material.dart';

/// A single selectable option in an onboarding step.
///
/// Renders as a card-like tile that reflects its [selected] state (a filled
/// check and an accent border) and invokes [onTap] when pressed. Exposed as a
/// radio in the accessibility tree so assistive tech announces the single-
/// choice semantics.
class OnboardingChoiceTile extends StatelessWidget {
  const OnboardingChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
  });

  /// The primary label of the option.
  final String title;

  /// An optional secondary label shown beneath [title].
  final String? subtitle;

  /// Whether this option is the current selection.
  final bool selected;

  /// Called when the learner taps the option.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        elevation: 0,
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The common layout for an onboarding selection step: a titled, scrollable
/// list of options with a persistent bottom "continue" action.
///
/// Keeps the three selection steps visually consistent and lets each step
/// screen focus on just its options and callbacks.
class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.stepLabel,
    required this.options,
    required this.onContinue,
    required this.canContinue,
    this.isSaving = false,
    this.errorMessage,
    this.onBack,
    this.continueLabel = 'Continue',
  });

  /// The step's heading (e.g. "What's your English level?").
  final String title;

  /// An optional supporting line under the heading.
  final String? subtitle;

  /// A short progress label, e.g. "Step 1 of 3".
  final String stepLabel;

  /// The option tiles for this step.
  final List<Widget> options;

  /// Called when the learner presses continue (enabled only when
  /// [canContinue]).
  final VoidCallback onContinue;

  /// Whether the continue action is enabled.
  final bool canContinue;

  /// Whether a save is in flight; shows progress and disables continue.
  final bool isSaving;

  /// An error to surface above the options, or `null`.
  final String? errorMessage;

  /// Called when the learner presses back; when `null` no back control shows.
  final VoidCallback? onBack;

  /// The label for the continue button.
  final String continueLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(stepLabel),
        leading: onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: isSaving ? null : onBack,
              ),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      if (errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: errorMessage!),
                      ],
                      const SizedBox(height: 16),
                      ...options,
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed:
                          (!canContinue || isSaving) ? null : onContinue,
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(continueLabel),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A prominent, accessible error banner shown above a step's options when a
/// save fails, keeping the learner on the step.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
