import 'package:flutter/material.dart';

import '../domain/onboarding_selections.dart';
import 'widgets/onboarding_scaffold.dart';

/// The onboarding step where the learner picks a native language from Hindi,
/// Tamil, Telugu, Bengali, or Marathi. (Requirement 2.3)
///
/// A presentational widget wired by `OnboardingController`. Because this is
/// the final selection step, its continue action persists the profile draft;
/// [isSaving] reflects that in-flight save.
class NativeLanguageStep extends StatelessWidget {
  const NativeLanguageStep({
    super.key,
    required this.selected,
    required this.onSelected,
    required this.onContinue,
    this.onBack,
    this.isSaving = false,
    this.errorMessage,
  });

  /// The currently selected native language, or `null` when none is chosen.
  final NativeLanguage? selected;

  /// Called with the language the learner taps.
  final ValueChanged<NativeLanguage> onSelected;

  /// Called when the learner confirms and the draft is persisted.
  final VoidCallback onContinue;

  /// Called when the learner goes back; `null` hides the back control.
  final VoidCallback? onBack;

  /// Whether the draft save is in flight.
  final bool isSaving;

  /// An error to surface (e.g. a failed save), or `null`.
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return OnboardingStepScaffold(
      stepLabel: 'Step 3 of 3',
      title: "What's your native language?",
      subtitle: 'We use it for translations in your grammar feedback.',
      canContinue: selected != null,
      isSaving: isSaving,
      errorMessage: errorMessage,
      onBack: onBack,
      onContinue: onContinue,
      continueLabel: 'Save and continue',
      options: [
        for (final language in NativeLanguage.values)
          OnboardingChoiceTile(
            title: language.label,
            subtitle: language.nativeName,
            selected: selected == language,
            onTap: () => onSelected(language),
          ),
      ],
    );
  }
}
