import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../data/onboarding_providers.dart';
import '../data/onboarding_repository.dart';
import '../domain/onboarding_selections.dart';

/// The steps of the onboarding selection flow, in order.
///
/// [level], [goal], and [language] gather the three self-selected profile
/// fields (Requirements 2.1–2.3). [placement] is the terminal step reached
/// after the draft is persisted; it is a seam the adaptive placement engine
/// (task 5.6) fills in. Keeping it in the enum lets the flow structure the
/// route so placement is simply the next step, without 5.6 having to reshape
/// the state machine.
enum OnboardingStep {
  /// Select current English level. (Requirement 2.1)
  level,

  /// Select the learning goal. (Requirement 2.2)
  goal,

  /// Select the native language. (Requirement 2.3)
  language,

  /// Draft persisted; adaptive placement follows (task 5.6).
  placement;
}

/// The view state the onboarding flow renders, produced by
/// [OnboardingController].
///
/// Holds the [step] the learner is on, the [selections] gathered so far, an
/// [isSaving] flag while the draft is being persisted, and an optional
/// [errorMessage] shown when a save fails (so the learner stays on the step
/// and can retry). (Requirements 2.1–2.3)
@immutable
class OnboardingViewState {
  const OnboardingViewState({
    this.step = OnboardingStep.level,
    this.selections = const OnboardingSelections(),
    this.isSaving = false,
    this.errorMessage,
  });

  /// The current step in the stepped flow.
  final OnboardingStep step;

  /// The selections gathered so far.
  final OnboardingSelections selections;

  /// Whether the profile draft is currently being persisted.
  final bool isSaving;

  /// A human-readable error to display when a save fails, else `null`.
  final String? errorMessage;

  /// Whether the current step's required selection has been made, enabling
  /// the "continue" action.
  bool get canAdvance => switch (step) {
        OnboardingStep.level => selections.englishLevel != null,
        OnboardingStep.goal => selections.goal != null,
        OnboardingStep.language => selections.nativeLanguage != null,
        OnboardingStep.placement => true,
      };

  OnboardingViewState copyWith({
    OnboardingStep? step,
    OnboardingSelections? selections,
    bool? isSaving,
    String? errorMessage,
  }) {
    return OnboardingViewState(
      step: step ?? this.step,
      selections: selections ?? this.selections,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is OnboardingViewState &&
      other.step == step &&
      other.selections == selections &&
      other.isSaving == isSaving &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(step, selections, isSaving, errorMessage);
}

/// Drives the stepped onboarding selection flow (English level, goal, native
/// language), holding the multi-step selection state and persisting a profile
/// draft via [OnboardingRepository]. (Requirements 2.1, 2.2, 2.3)
///
/// The learner picks a value on each step and advances; on leaving the final
/// selection step the controller persists the draft (a merge write to
/// `profile/main`) and moves to the [OnboardingStep.placement] seam. It does
/// not mark the profile `onboarded` or run placement — that is task 5.6, which
/// appends to the [OnboardingStep.placement] step and flips the
/// `onboardedProvider` seam.
class OnboardingController extends Notifier<OnboardingViewState> {
  @override
  OnboardingViewState build() => const OnboardingViewState();

  OnboardingRepository get _repository =>
      ref.read(onboardingRepositoryProvider);

  /// Records the selected English [level] and clears any error.
  void selectEnglishLevel(EnglishLevel level) {
    state = state.copyWith(
      selections: state.selections.copyWith(englishLevel: level),
    );
  }

  /// Records the selected [goal] and clears any error.
  void selectGoal(LearningGoal goal) {
    state = state.copyWith(
      selections: state.selections.copyWith(goal: goal),
    );
  }

  /// Records the selected native [language] and clears any error.
  void selectNativeLanguage(NativeLanguage language) {
    state = state.copyWith(
      selections: state.selections.copyWith(nativeLanguage: language),
    );
  }

  /// Returns to the previous step, clearing any error. No-op on the first
  /// step.
  void back() {
    switch (state.step) {
      case OnboardingStep.level:
        return;
      case OnboardingStep.goal:
        state = state.copyWith(step: OnboardingStep.level);
      case OnboardingStep.language:
        state = state.copyWith(step: OnboardingStep.goal);
      case OnboardingStep.placement:
        state = state.copyWith(step: OnboardingStep.language);
    }
  }

  /// Advances from the current step.
  ///
  /// On the [OnboardingStep.level] and [OnboardingStep.goal] steps this simply
  /// moves to the next selection. On the [OnboardingStep.language] step it
  /// persists the full draft and, only on success, moves to the
  /// [OnboardingStep.placement] seam; a failure keeps the learner on the step
  /// with an error to retry. Does nothing when the current step's selection is
  /// missing or a save is already in flight. (Requirements 2.1–2.3)
  Future<void> advance() async {
    if (state.isSaving || !state.canAdvance) return;

    switch (state.step) {
      case OnboardingStep.level:
        state = state.copyWith(step: OnboardingStep.goal);
      case OnboardingStep.goal:
        state = state.copyWith(step: OnboardingStep.language);
      case OnboardingStep.language:
        await _persistDraft();
      case OnboardingStep.placement:
        return;
    }
  }

  /// Persists the gathered selections as a profile draft, advancing to the
  /// placement step on success or surfacing an error on failure.
  Future<void> _persistDraft() async {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) {
      state = state.copyWith(
        errorMessage: 'You need to be signed in to continue.',
      );
      return;
    }

    state = state.copyWith(isSaving: true);
    final result = await _repository.saveDraft(
      uid: uid,
      selections: state.selections,
    );
    state = result.fold(
      (_) => state.copyWith(
        isSaving: false,
        step: OnboardingStep.placement,
      ),
      (exception) => state.copyWith(
        isSaving: false,
        errorMessage: exception.message,
      ),
    );
  }
}

/// Exposes the [OnboardingController] and its [OnboardingViewState] to the
/// onboarding UI.
final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingViewState>(
  OnboardingController.new,
  name: 'onboardingControllerProvider',
);
