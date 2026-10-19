import 'package:flutter/material.dart';

// Shared, consistent "whole-screen state" views used across features for the
// loading, empty, and error states a data-backed screen can be in.
//
// Before this, each feature re-implemented the same centered icon-plus-message
// (optionally with a retry button) layout inline — the quiz screen's
// `_QuizMessage`/`_QuizError` and the chat screen's `_EmptyChat`, for example.
// Factoring the layout here gives every feature the same spacing, typography,
// and accessibility semantics so error, empty, and offline states look and
// behave the same everywhere, and keeps the per-feature screens free of
// duplicated presentation logic. (Design "Error Handling": the UI renders
// consistent error/empty views with retry where safe.)
//
// These widgets are intentionally presentation-only: they take a ready message
// and an optional retry callback. Mapping a typed AppException (or an AI
// `status`) to the right view and deciding whether a retry is safe is the job
// of app_exception_view.dart, which composes these.

/// A centered spinner for the loading state.
///
/// Thin wrapper over [CircularProgressIndicator] so every screen shows the
/// same loading affordance and callers do not re-wrap it in a [Center] each
/// time.
class LoadingStateView extends StatelessWidget {
  const LoadingStateView({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// A centered icon + message view for an "empty"/"nothing here" state that is
/// not an error (e.g. an all-caught-up quiz or an empty transcript).
///
/// [icon] defaults to a neutral inbox glyph and is tinted with the primary
/// color to read as informational rather than alarming. An optional [action]
/// renders a button beneath the message for empty states that offer a next
/// step (for example, "refresh"); omit it for a purely informational empty
/// state.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  /// The user-facing message describing why the view is empty.
  final String message;

  /// The glyph shown above the message. Defaults to a neutral inbox icon.
  final IconData icon;

  /// An optional call-to-action button rendered beneath the message.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CenteredState(
      icon: icon,
      iconColor: scheme.primary,
      message: message,
      action: action,
    );
  }
}

/// A centered icon + message view for an error state, with an optional retry
/// action rendered only when retrying is safe.
///
/// [icon] defaults to an error glyph (and is tinted with the error color);
/// callers surface a different glyph for distinct errors — for example a
/// wifi-off glyph for an offline state. When [onRetry] is non-null a "Try
/// again" button is shown; pass `null` for failures where an immediate retry
/// cannot help (an exhausted usage limit, a moderation refusal) so the learner
/// is not invited to repeat an action that will fail the same way.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.message,
    this.onRetry,
    this.icon = Icons.error_outline,
    this.retryLabel = 'Try again',
  });

  /// The user-facing error message.
  final String message;

  /// Invoked when the learner taps the retry button. When `null`, no retry
  /// button is shown because a retry is not safe/useful for this failure.
  final VoidCallback? onRetry;

  /// The glyph shown above the message. Defaults to an error glyph.
  final IconData icon;

  /// The label for the retry button, shown only when [onRetry] is non-null.
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _CenteredState(
      icon: icon,
      iconColor: scheme.error,
      message: message,
      action: onRetry == null
          ? null
          : FilledButton(onPressed: onRetry, child: Text(retryLabel)),
    );
  }
}

/// The shared layout backing [LoadingStateView] siblings: a centered column of
/// a large icon, a message, and an optional action, with consistent spacing
/// and accessibility semantics.
class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.iconColor,
    required this.message,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The icon is decorative; the message carries the meaning, so the
            // icon is excluded from the semantics tree to avoid redundant
            // screen-reader output.
            ExcludeSemantics(child: Icon(icon, size: 48, color: iconColor)),
            const SizedBox(height: 16),
            Text(
              message,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (action case final action?) ...[
              const SizedBox(height: 24),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
