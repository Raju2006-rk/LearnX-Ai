import 'package:flutter/material.dart';

import '../../core/errors/app_exception.dart';
import 'app_state_view.dart';

/// Maps a typed [AppException] to the consistent error/empty view a screen
/// should show, deciding per failure kind whether an immediate retry is safe.
///
/// This is the single place the app turns the exhaustive [AppException]
/// hierarchy into UI, so every feature surfaces the same failure the same way
/// (Design "Error Handling": controllers map exceptions to error states; the
/// UI renders consistent error/empty views with retry where safe). Because the
/// hierarchy is `sealed`, the switch is exhaustive — a new failure type is a
/// compile error here until it is given a presentation, so no failure can slip
/// through to a blank screen.
///
/// Retry policy, by subtype:
/// - [NetworkException] — a connectivity glyph and a retry action; a retry can
///   succeed once the connection returns.
/// - [NotFoundException] — a retry action; the resource may appear on reload.
/// - [AuthException] — no retry here; re-tapping cannot fix an auth problem,
///   the learner needs to re-authenticate, so the message explains that
///   instead of offering a button that would fail the same way.
/// - [UsageLimitException] — rendered as an informational empty-style view
///   with no retry; the daily limit will not clear by retrying, so inviting a
///   retry would be misleading.
/// - [ModerationRefusalException] — no retry; repeating the same request would
///   be refused again, so the safe message is shown without a retry button.
///
/// [onRetry] is used only for the retryable kinds; pass the action that reruns
/// the failed load. It is ignored for the non-retryable kinds above, which is
/// how "retry where safe" is enforced in one place rather than at each call
/// site.
class AppExceptionView extends StatelessWidget {
  const AppExceptionView({
    super.key,
    required this.exception,
    this.onRetry,
  });

  /// The typed failure to present.
  final AppException exception;

  /// The retry action, applied only to failure kinds where a retry is safe.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    // Branch on the sealed type, never on the free-form [message] string, so
    // the presentation stays exhaustive and resilient to message wording
    // changes.
    return switch (exception) {
      NetworkException() => ErrorStateView(
        icon: Icons.wifi_off,
        message: exception.message,
        onRetry: onRetry,
      ),
      NotFoundException() => ErrorStateView(
        icon: Icons.search_off,
        message: exception.message,
        onRetry: onRetry,
      ),
      // Re-tapping cannot resolve an auth failure, so no retry button; the
      // message tells the learner to sign in again.
      AuthException() => ErrorStateView(
        icon: Icons.lock_outline,
        message: exception.message,
      ),
      // A reached usage limit is not an error the learner can retry away — it
      // is a "come back later" state, so it reads as an informational empty
      // view with no retry.
      UsageLimitException() => EmptyStateView(
        icon: Icons.hourglass_empty,
        message: exception.message,
      ),
      // Repeating a refused request would be refused again; show the safe
      // message without inviting a retry.
      ModerationRefusalException() => ErrorStateView(
        icon: Icons.block,
        message: exception.message,
      ),
    };
  }
}

/// The shared offline view for a network-required feature that fails fast when
/// the connectivity stream reports the device is offline, rather than issuing
/// a request that would hang.
///
/// This is distinct from [AppExceptionView] for [NetworkException]: offline is
/// detected proactively (before any call) from the connectivity stream, so the
/// feature can show this immediately instead of waiting for a request to time
/// out (Design "Error Handling": offline is detected proactively via a
/// connectivity stream so network-required features fail fast; Req 4.5, 6.6).
/// [onRetry] reruns the gated action, so reconnecting and tapping retry
/// proceeds normally.
class OfflineStateView extends StatelessWidget {
  const OfflineStateView({
    super.key,
    required this.message,
    this.onRetry,
  });

  /// The user-facing message explaining the feature needs a connection.
  final String message;

  /// Reruns the action that was blocked by the offline check.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ErrorStateView(
      icon: Icons.wifi_off,
      message: message,
      onRetry: onRetry,
    );
  }
}
