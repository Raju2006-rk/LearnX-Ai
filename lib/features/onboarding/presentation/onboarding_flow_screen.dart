import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/onboarding_controller.dart';
import 'english_level_step.dart';
import 'goal_step.dart';
import 'native_language_step.dart';
import 'placement_step.dart';

/// The stepped onboarding flow shown at `Routes.onboarding`.
///
/// Watches [onboardingControllerProvider] and renders the current step:
/// English level → goal → native language (Requirements 2.1–2.3). Advancing
/// past the final selection step persists a profile draft and lands on the
/// [OnboardingStep.placement] step, which runs the adaptive placement test
/// ([PlacementStep]): it stores the assigned `placementLevel`, marks the
/// profile `onboarded`, and the router then routes the learner to home off the
/// persisted flag. (Requirements 2.4, 2.5, 2.6)
class OnboardingFlowScreen extends ConsumerWidget {
  const OnboardingFlowScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    switch (state.step) {
      case OnboardingStep.level:
        return EnglishLevelStep(
          selected: state.selections.englishLevel,
          onSelected: controller.selectEnglishLevel,
          onContinue: controller.advance,
          isSaving: state.isSaving,
          errorMessage: state.errorMessage,
        );
      case OnboardingStep.goal:
        return GoalStep(
          selected: state.selections.goal,
          onSelected: controller.selectGoal,
          onContinue: controller.advance,
          onBack: controller.back,
          isSaving: state.isSaving,
          errorMessage: state.errorMessage,
        );
      case OnboardingStep.language:
        return NativeLanguageStep(
          selected: state.selections.nativeLanguage,
          onSelected: controller.selectNativeLanguage,
          onContinue: controller.advance,
          onBack: controller.back,
          isSaving: state.isSaving,
          errorMessage: state.errorMessage,
        );
      case OnboardingStep.placement:
        return const PlacementStep();
    }
  }
}
