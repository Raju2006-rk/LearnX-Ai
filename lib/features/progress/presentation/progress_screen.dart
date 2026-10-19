import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/progress_controller.dart';
import '../domain/daily_goal.dart';
import '../domain/progress_overview.dart';
import '../domain/streak.dart';
import 'weekly_summary_view.dart';

/// The Progress screen: the learner's current and longest streak
/// (Requirement 7.1), a Day 1–15-and-beyond daily goal tracker
/// (Requirement 7.2), and the current-week summary panel (task 10.4's
/// [WeeklySummaryView], composed here).
///
/// Watches [progressControllerProvider] and renders the loading, error, and
/// data phases uniformly, mirroring the learning-path screen. In the data
/// phase the streak summary and the goal tracker read from a single
/// [ProgressOverview], so the two panels stay consistent with one another. The
/// screen is purely a read view: the streak and tracker advance when a
/// qualifying activity is recorded elsewhere (via the controller), which flows
/// back through the watched providers.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(progressControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: SafeArea(
        child: switch (overviewAsync) {
          AsyncData(:final value) => _ProgressBody(overview: value),
          AsyncError() => _ProgressBody(overview: ProgressOverview.empty),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// The scrollable body: the streak summary, the daily goal tracker, and the
/// weekly summary panel.
class _ProgressBody extends StatelessWidget {
  const _ProgressBody({required this.overview});

  final ProgressOverview overview;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreakSummaryCard(streak: overview.streak),
        const SizedBox(height: 16),
        DailyGoalTracker(goal: overview.dailyGoal),
        const SizedBox(height: 16),
        const WeeklySummaryView(),
      ],
    );
  }
}

/// A card showing the learner's current and longest streak side by side.
/// (Requirement 7.1)
class StreakSummaryCard extends StatelessWidget {
  const StreakSummaryCard({required this.streak, super.key});

  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Streak', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StreakStat(
                    icon: Icons.local_fire_department,
                    label: 'Current',
                    days: streak.current,
                    highlight: streak.isActive,
                  ),
                ),
                Expanded(
                  child: _StreakStat(
                    icon: Icons.emoji_events_outlined,
                    label: 'Longest',
                    days: streak.longest,
                    highlight: false,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One streak statistic column: an icon, the day count, and a caption.
class _StreakStat extends StatelessWidget {
  const _StreakStat({
    required this.icon,
    required this.label,
    required this.days,
    required this.highlight,
  });

  final IconData icon;
  final String label;
  final int days;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
    final unit = days == 1 ? 'day' : 'days';
    return Semantics(
      label: '$label streak: $days $unit',
      excludeSemantics: true,
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 8),
          Text(
            '$days',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$label ($unit)',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The daily goal tracker: a row of day chips spanning Day 1 through Day 15,
/// then continuing beyond Day 15. (Requirement 7.2)
///
/// Days up to and including the learner's current [DailyGoal.day] are marked
/// complete; the rest are upcoming. Once the learner passes Day 15 the tracker
/// keeps going: it renders Day 1 through the current day (and always at least
/// through Day 15) so the "and beyond" days appear as the learner reaches
/// them, matching the design's Day 1–15-and-beyond tracker.
class DailyGoalTracker extends StatelessWidget {
  const DailyGoalTracker({required this.goal, super.key});

  final DailyGoal goal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Always render through Day 15; extend to the current day once the learner
    // has gone beyond it so the "and beyond" days surface as they are reached.
    final lastDay = goal.day > DailyGoal.trackerSpanDays
        ? goal.day
        : DailyGoal.trackerSpanDays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily goal', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              goal.hasStarted
                  ? 'Day ${goal.day} · ${goal.targetPerDay} '
                        'activit${goal.targetPerDay == 1 ? 'y' : 'ies'} a day'
                  : 'Complete an activity to start your daily goal',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var day = 1; day <= lastDay; day++)
                  _DayChip(day: day, completed: day <= goal.day),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A single day chip in the goal tracker: filled when completed, outlined when
/// still upcoming.
class _DayChip extends StatelessWidget {
  const _DayChip({required this.day, required this.completed});

  final int day;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = completed ? scheme.primary : scheme.surface;
    final foreground = completed ? scheme.onPrimary : scheme.onSurfaceVariant;
    final border = completed ? scheme.primary : scheme.outlineVariant;

    return Semantics(
      label: 'Day $day, ${completed ? 'completed' : 'upcoming'}',
      excludeSemantics: true,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2),
        ),
        child: Text(
          '$day',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
