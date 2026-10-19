import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/progress_providers.dart';
import '../domain/streak.dart';

/// The streak flame indicator shown on the home learning path: a flame icon
/// with the learner's current streak count. (Requirement 3.7)
///
/// Watches [streakProvider] and renders the current streak. The flame lights
/// up (its accent colour) once the learner has an active run of at least one
/// day; with no active streak it stays muted so the control never shouts at a
/// learner who has not started yet. The streak increments on the first
/// qualifying activity of a calendar day — that computation is persisted by
/// the Progress feature (tasks 9/10) and flows into this control through the
/// provider.
///
/// Loading and error phases fall back to [Streak.none] rather than showing a
/// spinner or an error here: the flame is a lightweight, always-present
/// adornment on the home app bar, so a transient read hiccup should degrade to
/// a muted "0" rather than disrupt the path. The control is exposed as a
/// single semantics node announcing the day count for assistive tech.
class StreakFlameIndicator extends ConsumerWidget {
  const StreakFlameIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streak = ref.watch(streakProvider).value ?? Streak.none;
    return _StreakFlame(streak: streak);
  }
}

/// The pure presentation of a [Streak] flame, split out so it can be rendered
/// and tested without a provider scope.
class _StreakFlame extends StatelessWidget {
  const _StreakFlame({required this.streak});

  final Streak streak;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lit = streak.isActive;
    final color = lit ? scheme.tertiary : scheme.onSurfaceVariant;

    return Semantics(
      label: _semanticLabel(streak),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              lit
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
              color: color,
              size: 24,
            ),
            const SizedBox(width: 4),
            Text(
              '${streak.current}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _semanticLabel(Streak streak) {
    if (!streak.isActive) return 'No current streak';
    final days = streak.current == 1 ? 'day' : 'days';
    return '${streak.current} $days streak';
  }
}
