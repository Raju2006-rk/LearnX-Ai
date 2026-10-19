import 'package:flutter/material.dart';

import '../domain/chat.dart';
import 'feedback_report_control.dart';

/// The card that renders a single [GrammarFeedback] beneath an AI teacher
/// reply. (Requirements 4.2, 4.3)
///
/// Per the design's Grammar_Feedback contract, the card renders
/// [GrammarFeedback.mistakeSpan] text in red and
/// [GrammarFeedback.correctedSentence] in green, shows the [GrammarFeedback.tip],
/// and shows [FeedbackTranslation.text] in the learner's selected native
/// language. When [GrammarFeedback.hasMistake] is false the span is omitted and
/// no red styling is applied — only the (unchanged) sentence, tip, and
/// translation are shown. (Requirements 4.2, 4.3)
///
/// The report-a-wrong-correction affordance ([FeedbackReportControl], task 7.5)
/// is embedded at the bottom so every rendered feedback item exposes a report
/// control (design Property 10). The card is given the [sessionId], the
/// reported [messageId], and the learner's [originalText] so a filed report
/// captures the full context snapshot.
class GrammarFeedbackCard extends StatelessWidget {
  const GrammarFeedbackCard({
    super.key,
    required this.feedback,
    required this.sessionId,
    required this.messageId,
    required this.originalText,
  });

  /// The structured feedback to render.
  final GrammarFeedback feedback;

  /// The chat session the reply belongs to, forwarded to the report control.
  final String sessionId;

  /// The reply message's id, used to key the report control's state.
  final String messageId;

  /// The learner's original text that was corrected, captured in a report.
  final String originalText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasMistake = feedback.hasMistake;
    final mistakeText = feedback.mistakeSpan?.text;

    // Material has no semantic "error green"; use fixed, high-contrast red and
    // green so the mistake/correction coding reads the same across themes.
    const mistakeColor = Color(0xFFD32F2F); // red 700
    const correctedColor = Color(0xFF2E7D32); // green 800

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The flagged mistake in red, shown only when there is a mistake.
            if (hasMistake && mistakeText != null && mistakeText.isNotEmpty) ...[
              _FeedbackLine(
                label: 'Mistake',
                child: Text(
                  mistakeText,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: mistakeColor,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            // The corrected sentence, always in green.
            _FeedbackLine(
              label: 'Corrected',
              child: Text(
                feedback.correctedSentence,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: correctedColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 8),
            // The short coaching tip.
            _FeedbackLine(
              label: 'Tip',
              child: Text(
                feedback.tip,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            // The native-language translation of the tip/explanation. Labelled
            // with the language's own endonym so the learner recognises it.
            _FeedbackLine(
              label: feedback.translation.language.nativeName,
              child: Text(
                feedback.translation.text,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 4),
            FeedbackReportControl(
              sessionId: sessionId,
              messageId: messageId,
              originalText: originalText,
              feedback: feedback,
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled line within the feedback card: a small caption above its
/// content, so each part (mistake / corrected / tip / translation) is
/// distinguishable without relying on colour alone.
class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}
