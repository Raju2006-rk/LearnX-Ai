/// The DPDP consent policy the learner is asked to accept on first run.
///
/// The [version] is the policy revision the learner acknowledges in the UI.
/// It is displayed for transparency but is **not** written to Firestore by the
/// client: `consent.policyVersion` is server-owned (the security rules make it
/// read-only to clients, stamping it via a trusted path). The client records
/// only `consent.dpdpAccepted` and `consent.acceptedAt`; the acknowledged
/// version travels here for display and can be reconciled server-side.
/// (Requirement 10.3)
abstract final class ConsentPolicy {
  const ConsentPolicy._();

  /// The current DPDP policy version presented to the learner.
  ///
  /// Kept as a client-side reference only; the server owns the authoritative
  /// `consent.policyVersion` value on the user document.
  static const String version = 'v1';

  /// The short, plain-language summary shown on the consent screen describing
  /// what personal data LearnX processes and why. (Requirement 10.3)
  static const String summary =
      'LearnX processes the information you share while learning — your '
      'onboarding choices, chat messages with the AI teacher, quiz answers, '
      'and progress — to personalize lessons and track your streaks. Your '
      'data is stored securely and never sold. You can delete your data at any '
      'time from the Account screen.';
}
