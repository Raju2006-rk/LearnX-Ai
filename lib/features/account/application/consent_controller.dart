import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../data/consent_providers.dart';
import '../data/consent_repository.dart';

/// The view state the DPDP consent screen renders, produced by
/// [ConsentController]. (Requirement 10.3)
///
/// The learner is either reviewing the notice ([isSaving] false), a write is
/// in flight ([isSaving] true, which disables the accept action and shows
/// progress), acceptance failed ([errorMessage] set, so the learner stays on
/// the screen and can retry), or acceptance was recorded ([accepted] true,
/// which the router's consent seam observes to advance to onboarding).
@immutable
class ConsentViewState {
  const ConsentViewState({
    this.isSaving = false,
    this.accepted = false,
    this.errorMessage,
  });

  /// Whether the consent write is currently in flight.
  final bool isSaving;

  /// Whether DPDP consent has been successfully recorded.
  final bool accepted;

  /// A human-readable error to display when recording consent fails, else
  /// `null`.
  final String? errorMessage;

  ConsentViewState copyWith({
    bool? isSaving,
    bool? accepted,
    String? errorMessage,
  }) {
    return ConsentViewState(
      isSaving: isSaving ?? this.isSaving,
      accepted: accepted ?? this.accepted,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ConsentViewState &&
      other.isSaving == isSaving &&
      other.accepted == accepted &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(isSaving, accepted, errorMessage);
}

/// Drives the DPDP consent capture: on accept it records the learner's consent
/// (`consent.dpdpAccepted` + `acceptedAt`) via [ConsentRepository] and, on
/// success, marks the state [ConsentViewState.accepted] so the router can move
/// the learner on to onboarding. (Requirement 10.3)
///
/// A failure surfaces an error message and keeps the learner on the consent
/// screen so they can retry — mirroring the sign-in / onboarding failure
/// handling. Consent MUST be recorded here before onboarding, because the
/// security rules gate every profile/feature write on recorded consent.
class ConsentController extends Notifier<ConsentViewState> {
  @override
  ConsentViewState build() => const ConsentViewState();

  ConsentRepository get _repository => ref.read(consentRepositoryProvider);

  /// Records the learner's DPDP acceptance. No-op while a write is already in
  /// flight or once consent has been recorded. (Requirement 10.3)
  Future<void> accept() async {
    if (state.isSaving || state.accepted) return;

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) {
      state = state.copyWith(
        errorMessage: 'You need to be signed in to continue.',
      );
      return;
    }

    state = state.copyWith(isSaving: true);
    final result = await _repository.acceptDpdp(uid: uid);
    state = result.fold(
      (_) => state.copyWith(isSaving: false, accepted: true),
      (exception) =>
          state.copyWith(isSaving: false, errorMessage: exception.message),
    );
  }
}

/// Exposes the [ConsentController] and its [ConsentViewState] to the consent
/// UI.
final consentControllerProvider =
    NotifierProvider<ConsentController, ConsentViewState>(
  ConsentController.new,
  name: 'consentControllerProvider',
);
