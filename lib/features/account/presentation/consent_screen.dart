import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/consent_controller.dart';
import '../domain/consent_policy.dart';

/// The DPDP consent screen shown on first run after auth, before onboarding.
///
/// Presents a plain-language summary of what personal data LearnX processes
/// (Requirement 10.3), the policy version being acknowledged, and an explicit
/// opt-in: the learner must tick the agreement checkbox before the "Agree and
/// continue" action records consent. On failure an error banner is shown and
/// the learner stays on the screen to retry.
///
/// The screen watches [consentControllerProvider]: it disables inputs and
/// shows progress while the write is in flight, and surfaces the error message
/// on failure. On success the controller flips its state to accepted; the
/// router's consent seam observes recorded consent and advances the learner to
/// onboarding.
///
/// Only `consent.dpdpAccepted` and `consent.acceptedAt` are written from the
/// client. The acknowledged [ConsentPolicy.version] is displayed for
/// transparency but not written — `consent.policyVersion` is server-owned
/// (read-only to clients).
class ConsentScreen extends ConsumerStatefulWidget {
  const ConsentScreen({super.key});

  @override
  ConsumerState<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends ConsumerState<ConsentScreen> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(consentControllerProvider);
    final controller = ref.read(consentControllerProvider.notifier);
    final busy = state.isSaving;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your privacy'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.errorMessage != null)
                    _ErrorBanner(message: state.errorMessage!),
                  Icon(
                    Icons.privacy_tip_outlined,
                    size: 48,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'How LearnX uses your data',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    ConsentPolicy.summary,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Policy version ${ConsentPolicy.version}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _agreed,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _agreed = value ?? false),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text(
                      'I agree to LearnX processing my personal data as '
                      'described above.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: (!_agreed || busy) ? null : controller.accept,
                    child: const Text('Agree and continue'),
                  ),
                  if (busy) ...const [
                    SizedBox(height: 24),
                    Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A prominent, accessible error banner shown above the consent content when
/// recording consent fails, keeping the learner on the screen.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
