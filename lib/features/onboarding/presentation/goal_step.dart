import 'package:flutter/material.dart';

import '../domain/onboarding_selections.dart';
import 'widgets/onboarding_scaffold.dart';

/// The onboarding step where the learner picks a learning goal of Speaking,
/// Job, or Both. (Requirement 2.2)
///
/// A presentational widget wired by `OnboardingController`; see
/// [EnglishLevelStep] for the shared pattern.
class GoalStep extends StatelessWidget {
  const GoalStep({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    this.onBack,
    this.isSaving = false,
    this.errorMessage,
  });

  /// The currently selected goal, or `null` when none is chosen yet.
  final LearningGoal? selected;

  /// Called with the goal the learner taps.
  final ValueChanged<LearningGoal> onSelected;

  /// Called when the learner advances to the next step.
  final VoidCallback onContinue;

  /// Called when the learner goes back; `null` hides the back control.
  final VoidCallback? onBack;

  /// Whether a save is in flight.
  final bool isSaving;

  /// An error to surface, or `null`.
  final String? errorMessage;

  static const Map<LearningGoal, String> _descriptions = {
    LearningGoal.speaking: 'Get comfortable speaking in everyday situations.',
    LearningGoal.job: 'Build the English you need for work and interviews.',
    LearningGoal.both: 'A balanced mix of speaking and workplace English.',
  };

  @override
  Widget build(BuildContext context) {
    return OnboardingStepScaffold(
      stepLabel: 'Step 2 of 3',
      title: "What's your goal?",
      subtitle: 'This shapes the examples and practice we show you.',
      canContinue: selected != null,
      isSaving: isSaving,
      errorMessage: errorMessage,
      onBack: onBack,
      onContinue: onContinue,
      options: [
        for (final goal in LearningGoal.values)
          OnboardingChoiceTile(
            title: goal.label,
            subtitle: _descriptions[goal],
            selected: selected == goal,
            onTap: () => onSelected(goal),
          ),
      ],
    );
  }
}
