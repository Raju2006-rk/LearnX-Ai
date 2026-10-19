import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/report_controller.dart';
import '../domain/chat.dart';

/// The report-a-wrong-correction control shown on a single `Grammar_Feedback`
/// item. (Requirements 5.3, 5.4)
///
/// Every rendered feedback item exposes this control (design Property 10): a
/// compact "Report" affordance the learner taps to flag a wrong correction.
/// Tapping it opens a dialog to optionally add a reason; confirming files a
/// report through [ReportController], which writes the full context snapshot
/// (session, message, original text, and the feedback itself) to the learner's
/// own `reports` collection. On success a receipt is confirmed to the learner
/// via a snackbar and the control shows a "Reported" state; on failure an error
/// is surfaced and the control stays available to retry. (Requirement 5.4)
class FeedbackReportControl extends ConsumerWidget {
  const FeedbackReportControl({
    super.key,
    required this.sessionId,
    required this.messageId,
    required this.originalText,
    required this.feedback,
  });

  /// The chat session the reported message belongs to.
  final String sessionId;

  /// The reported message's id — also the key for this control's report state.
  final String messageId;

  /// The learner's original text that was corrected, captured in the report.
  final String originalText;

  /// The feedback being reported, captured in the report context snapshot.
  final GrammarFeedback feedback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(reportControllerProvider(messageId));

    // Confirm receipt / surface failure the moment the controller resolves,
    // without rebuilding into a snackbar inside build.
    ref.listen<ReportViewState>(reportControllerProvider(messageId), (
      previous,
      next,
    ) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      switch (next) {
        case ReportFiled():
          messenger
            ..clearSnackBars()
            ..showSnackBar(
              const SnackBar(
                content: Text('Thanks — your report has been received.'),
              ),
            );
        case ReportFailure(:final message):
          messenger
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(message)));
        case ReportIdle():
        case ReportSubmitting():
          break;
      }
    });

    return switch (state) {
      ReportSubmitting() => const _ReportChip(
        icon: Icons.hourglass_empty,
        label: 'Reporting…',
        onPressed: null,
      ),
      ReportFiled() => const _ReportChip(
        icon: Icons.check_circle_outline,
        label: 'Reported',
        onPressed: null,
      ),
      ReportIdle() || ReportFailure() => _ReportChip(
        icon: Icons.flag_outlined,
        label: 'Report',
        onPressed: () => _onReport(context, ref),
      ),
    };
  }

  /// Opens the reason dialog and, if the learner confirms, files the report
  /// through the per-message [ReportController].
  Future<void> _onReport(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _ReportReasonDialog(),
    );
    // A null result means the learner dismissed the dialog without submitting.
    if (reason == null) return;

    await ref
        .read(reportControllerProvider(messageId).notifier)
        .fileReport(
          sessionId: sessionId,
          messageId: messageId,
          originalText: originalText,
          feedback: feedback,
          reason: reason,
        );
  }
}

/// The compact chip-style affordance for the report control in its three
/// visual states (report / reporting / reported).
class _ReportChip extends StatelessWidget {
  const _ReportChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}

/// A dialog that optionally captures a free-text reason for the report.
///
/// Returns the entered reason (possibly empty) when the learner submits, or
/// `null` when they cancel so the caller can distinguish dismiss from submit.
class _ReportReasonDialog extends StatefulWidget {
  const _ReportReasonDialog();

  @override
  State<_ReportReasonDialog> createState() => _ReportReasonDialogState();
}

class _ReportReasonDialogState extends State<_ReportReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report this correction'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tell us what looks wrong (optional). We review every report.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'What was wrong?',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Submit report'),
        ),
      ],
    );
  }
}
