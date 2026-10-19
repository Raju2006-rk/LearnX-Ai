import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress_providers.dart';
import '../domain/weekly_summary.dart';

/// The weekly summary view shown on the Progress screen: the learner's three
/// headline metrics for the current ISO week — time spent, words learned, and
/// mistakes fixed. (Requirement 7.4)
///
/// Watches [currentWeekSummaryProvider], which serves the persisted
/// `weeklySummaries/{isoWeek}` document when the scheduled function has written
/// it and otherwise a live current-week view aggregated from `dailyActivity`,
/// so the current week always shows up-to-date numbers. Loading and error
/// phases degrade to [WeeklySummary.empty] (a zeroed card) rather than a
/// spinner or an error surface, keeping this a calm, always-present panel.
class WeeklySummaryView extends ConsumerWidget {
  const WeeklySummaryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary =
        ref.watch(currentWeekSummaryProvider).value ?? WeeklySummary.empty;
    return WeeklySummaryCard(summary: summary);
  }
}

/// The pure presentation of a [WeeklySummary], split out so it can be rendered
/// and tested without a provider scope.
class WeeklySummaryCard extends StatelessWidget {
  const WeeklySummaryCard({required this.summary, super.key});

  final WeeklySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('This week', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Metric(
                    icon: Icons.timer_outlined,
                    label: 'Time spent',
                    value: formatTimeSpent(summary.timeSpentSec),
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.menu_book_outlined,
                    label: 'Words learned',
                    value: '${summary.wordsLearned}',
                  ),
                ),
                Expanded(
                  child: _Metric(
                    icon: Icons.check_circle_outline,
                    label: 'Mistakes fixed',
                    value: '${summary.mistakesFixed}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Formats a duration in seconds as a compact human string: `0m`, `45m`,
  /// `1h`, or `1h 30m`. Minutes are floored and dropped when a whole number of
  /// hours has no remainder, so the label stays short on a dense metrics row.
  static String formatTimeSpent(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final totalMinutes = safe ~/ 60;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }
}

/// One metric column: an icon, its value, and a caption label. Grouped under a
/// single semantics node so assistive tech announces "label: value".
class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
