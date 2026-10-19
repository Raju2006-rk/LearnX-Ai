// Property-based test for the step-detail content contract.
//
// Property 7: Skeleton content is always present regardless of AI
// personalization. When a learner opens a step, the rendered content combines
// the pre-authored skeleton with any AI-personalized examples and practice
// (Requirement 3.5); and if the AI_Proxy returns no personalized content, the
// pre-authored skeleton is still presented (Requirement 3.6). The testable
// form of that invariant is `StepContent.containsSkeleton`: for ANY
// personalization — including the empty one that models a failed/withheld
// AI call — the combined objectives/examples/practice always contain the full
// authored skeleton as a prefix, and AI content is only ever appended, never
// substituted. (Validates: Requirements 3.5, 3.6)
//
// The project has no dedicated property-testing package, so this test follows
// the convention of `placement_property_test.dart` and
// `auth_session_property_test.dart`: drive many (100+) randomly generated
// skeletons and personalizations through the real `StepContent` domain type. A
// fixed seed keeps iterations reproducible; a failing case prints the
// generated scenario.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/features/learning_path/domain/step_content.dart';

/// One randomly generated step-content scenario: an authored skeleton paired
/// with a personalization that may be empty, examples-only, practice-only, or
/// both.
class _Scenario {
  const _Scenario({required this.skeleton, required this.personalization});

  final StepSkeleton skeleton;
  final StepPersonalization personalization;

  @override
  String toString() =>
      '_Scenario(skeleton: objectives=${skeleton.objectives}, '
      'examples=${skeleton.examples}, practice=${skeleton.practice}; '
      'personalization: examples=${personalization.examples}, '
      'practice=${personalization.practice})';
}

/// A short list of distinct, labelled strings (0..maxLen items). The [tag]
/// keeps generated items distinguishable across skeleton vs. personalization
/// so a mis-ordering (e.g. AI content leaking before skeleton content) is
/// caught rather than masked by coincidental equality.
List<String> _items(Random random, String tag, {int maxLen = 4}) {
  final count = random.nextInt(maxLen + 1);
  return [for (var i = 0; i < count; i++) '$tag-$i-${random.nextInt(1 << 20)}'];
}

/// Builds a varied scenario. One in five personalizations is forced to the
/// canonical empty instance so the skeleton-only fallback (Requirement 3.6) is
/// exercised directly, not just approached by chance.
_Scenario _generateScenario(Random random) {
  final skeleton = StepSkeleton(
    objectives: _items(random, 'obj'),
    examples: _items(random, 's-ex'),
    practice: _items(random, 's-pr'),
  );

  final StepPersonalization personalization;
  if (random.nextInt(5) == 0) {
    personalization = StepPersonalization.empty;
  } else {
    personalization = StepPersonalization(
      examples: _items(random, 'ai-ex'),
      practice: _items(random, 'ai-pr'),
    );
  }

  return _Scenario(skeleton: skeleton, personalization: personalization);
}

void main() {
  const iterations = 300;

  test(
    'Property 7: the authored skeleton is always present regardless of AI '
    'personalization',
    () {
      // Fixed seed => reproducible iterations; any counterexample is printed.
      final random = Random(3051);

      for (var i = 0; i < iterations; i++) {
        final scenario = _generateScenario(random);
        final reason = 'iteration $i, $scenario';

        final content = StepContent(
          stepId: 'step-$i',
          title: 'Step $i',
          skeleton: scenario.skeleton,
          personalization: scenario.personalization,
        );

        // The invariant in its testable form: for every personalization the
        // combined content contains the full authored skeleton as a prefix.
        expect(content.containsSkeleton, isTrue, reason: reason);

        // Objectives are skeleton-only — never touched by personalization.
        expect(content.objectives, scenario.skeleton.objectives,
            reason: reason);

        // Every authored skeleton item appears, in authored order, as the
        // leading prefix of the rendered lists (AI content is appended after).
        expect(
          content.examples.take(scenario.skeleton.examples.length).toList(),
          scenario.skeleton.examples,
          reason: reason,
        );
        expect(
          content.practice.take(scenario.skeleton.practice.length).toList(),
          scenario.skeleton.practice,
          reason: reason,
        );

        // AI content is strictly additive: the combined lists are exactly the
        // skeleton followed by the personalization, so nothing is dropped or
        // reordered and the rendered length is the sum of both.
        expect(
          content.examples,
          [
            ...scenario.skeleton.examples,
            ...scenario.personalization.examples,
          ],
          reason: reason,
        );
        expect(
          content.practice,
          [
            ...scenario.skeleton.practice,
            ...scenario.personalization.practice,
          ],
          reason: reason,
        );
      }
    },
  );

  test(
    'Property 7 (fallback): the empty personalization renders the skeleton '
    'alone (Requirement 3.6)',
    () {
      final random = Random(8820);

      for (var i = 0; i < iterations; i++) {
        final skeleton = StepSkeleton(
          objectives: _items(random, 'obj'),
          examples: _items(random, 's-ex'),
          practice: _items(random, 's-pr'),
        );
        final reason = 'iteration $i, skeleton=$skeleton';

        // A failed or moderation-withheld personalizeLesson call maps to the
        // canonical empty personalization; the default also models absence.
        final content = StepContent(
          stepId: 'step-$i',
          title: 'Step $i',
          skeleton: skeleton,
          personalization: StepPersonalization.empty,
        );

        expect(content.containsSkeleton, isTrue, reason: reason);
        expect(content.hasPersonalization, isFalse, reason: reason);
        // With no AI content the rendered lists equal the skeleton exactly.
        expect(content.objectives, skeleton.objectives, reason: reason);
        expect(content.examples, skeleton.examples, reason: reason);
        expect(content.practice, skeleton.practice, reason: reason);
      }
    },
  );
}
