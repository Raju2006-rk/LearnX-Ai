import 'package:flutter/material.dart';

import '../domain/onboarding_selections.dart';
import 'widgets/onboarding_scaffold.dart';

/// The onboarding step where the learner self-selects a current English
/// level. (Requirement 2.1)
///
/// A presentational widget: it renders the [EnglishLevel] options with the
/// [selected] one highlighted and reports choices via [onSelected] and the
/// step transitions via [onContinue]/[onBack]. State lives in
/// `OnboardingController`, which keeps this screen trivially widget-testable.
class EnglishLevelStep extends StatelessWidget {
  const EnglishLevelStep({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    this.onBack,
    this.isSaving = false,
    this.errorMessage,
  });

  /// The currently selected level, or `null` when none is chosen yet.
  final EnglishLevel? selected;

  /// Called with the level the learner taps.
  final ValueChanged<EnglishLevel> onSelected;

  /// Called when the learner advances to the next step.
  final VoidCallback onContinue;

  /// Called when the learner goes back; `null` hides the back control.
  final VoidCallback? onBack;

  /// Whether a save is in flight.
  final bool isSaving;

  /// An error to surface, or `null`.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepScaffold(
      stepLabel: 'Step 1 of 3',
      title: "What's your English level?",
      subtitle: 'Pick the level that feels closest. We fine-tune it with a '
          'short placement next.',
      canContinue: selected != null,
      isSaving: isSaving,
      errorMessage: errorMessage,
      onBack: onBack,
      onContinue: onContinue,
      options: [
        for (final level in EnglishLevel.values)
          OnboardingChoiceTile(
            title: level.label,
            selected: selected == level,
            onTap: () => onSelected(level),
          ),
      ],
    );
  }
}
