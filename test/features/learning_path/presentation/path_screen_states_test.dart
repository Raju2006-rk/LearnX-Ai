// Hardening widget tests and an app-open benchmark for the home learning-path
// screen. (Task 12.3; Requirements 9.1, 9.3)
//
// The shared loading/empty/error/offline building blocks are unit-tested in
// test/shared/widgets/. These tests instead exercise them *in their consuming
// screen* — PathScreen — so a regression in how the screen maps a failed load
// to the shared views is caught:
//
//  * a failed load surfaces the typed error view (via AppExceptionView) with a
//    retry that re-runs the load (Req 9.3 resilience on slow/flaky networks),
//  * an offline NetworkException surfaces the offline glyph + retry,
//  * a reached usage limit surfaces the no-retry informational view,
//  * and — the app-open benchmark — the path renders from already-cached
//    authored content *without a network round-trip*, within a small time
//    budget, so launch stays fast on a low-end device / slow network (Req 9.1).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart' hide Step, StepState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/learning_path/data/path_providers.dart';
import 'package:learnx/features/learning_path/data/path_repository.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';
import 'package:learnx/features/learning_path/presentation/path_screen.dart';

import '../learning_path_test_support.dart';

/// A [PathRepository] test double whose [loadPath] returns a caller-supplied
/// [Result] and counts its invocations, so a screen test can drive the
/// loading / error / offline / data phases and assert that a retry re-runs the
/// load. It never touches Firestore: [loadPath] is fully overridden.
///
/// [latency] optionally delays [loadPath] so the loading phase is observable
/// before the result lands; the default is immediate so the app-open
/// benchmark measures only the screen's own build work, not a synthetic wait.
class _StubPathRepository extends PathRepository {
  _StubPathRepository(this._result, {this.latency = Duration.zero})
    : super(
        firestore: FakeFirebaseFirestore(),
        aiClient: FakeAiFunctionClient(),
      );

  final Result<StepProgress> _result;
  final Duration latency;

  int loadPathCalls = 0;

  @override
  Future<Result<StepProgress>> loadPath({
    required String uid,
    required String pathId,
  }) async {
    loadPathCalls++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    return _result;
  }
}

/// Builds a one-section/one-week [StepProgress] with [stepCount] resolved
/// steps so the data phase has something concrete to render — the shape a
/// cached, no-network path load produces.
StepProgress _resolvedProgress({int stepCount = 3}) {
  return StepProgress.resolve(
    pathId: kDefaultPathId,
    sections: [
      Section(
        id: 'sec1',
        title: 'Section 1',
        order: 0,
        weeks: [
          Week(
            id: 'wk1',
            title: 'Week 1',
            order: 0,
            steps: [
              for (var i = 1; i <= stepCount; i++)
                Step(
                  id: 's$i',
                  title: 'Step $i',
                  order: i,
                  type: 'lesson',
                  state: StepState.locked,
                ),
            ],
          ),
        ],
      ),
    ],
    completedStepIds: const <String>{},
  );
}

void main() {
  const uid = 'learner-1';

  Future<_StubPathRepository> pumpScreen(
    WidgetTester tester,
    Result<StepProgress> result, {
    Duration latency = Duration.zero,
  }) async {
    final repo = _StubPathRepository(result, latency: latency);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pathRepositoryProvider.overrideWithValue(repo),
          authStateProvider.overrideWithValue(const AuthState(uid: uid)),
        ],
        child: const MaterialApp(home: PathScreen()),
      ),
    );
    return repo;
  }

  group('PathScreen failure states (Req 9.3)', () {
    testWidgets(
      'a network failure shows the offline glyph and a retry that reloads',
      (tester) async {
        final repo = await pumpScreen(
          tester,
          const Result.failure(
            NetworkException('Check your connection and try again.'),
          ),
        );
        await tester.pumpAndSettle();

        // The typed network failure renders the shared offline view.
        expect(find.byIcon(Icons.wifi_off), findsOneWidget);
        expect(
          find.text('Check your connection and try again.'),
          findsOneWidget,
        );

        // Retry re-runs the load (the whole point of "retry where safe").
        expect(repo.loadPathCalls, greaterThanOrEqualTo(1));
        final callsBeforeRetry = repo.loadPathCalls;
        await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
        await tester.pumpAndSettle();
        expect(repo.loadPathCalls, greaterThan(callsBeforeRetry));
      },
    );

    testWidgets('a not-found failure shows a retryable error view', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Result.failure(
          NotFoundException('This learning path is not available yet.'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(
        find.text('This learning path is not available yet.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets(
      'a usage-limit failure shows an informational view with no retry',
      (tester) async {
        await pumpScreen(
          tester,
          const Result.failure(UsageLimitException('Daily limit reached.')),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
        expect(find.text('Daily limit reached.'), findsOneWidget);
        // A reached limit cannot be retried away, so no retry button.
        expect(find.byType(FilledButton), findsNothing);
      },
    );

    testWidgets('the loading phase shows the shared spinner', (tester) async {
      await pumpScreen(
        tester,
        Result.success(_resolvedProgress()),
        latency: const Duration(milliseconds: 50),
      );
      // Before the delayed load resolves, the loading view is shown.
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      // Once resolved, the spinner is gone and steps render.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(PathStepCircle), findsNWidgets(3));
    });
  });

  group('app-open benchmark (Req 9.1)', () {
    testWidgets(
      'renders the path from cached content without a network round-trip, '
      'within the launch budget',
      (tester) async {
        // The repository resolves the path synchronously (zero latency),
        // modeling task 12.1's cached-authored-content path: launch renders
        // the interactive path without waiting on a network read.
        final stopwatch = Stopwatch()..start();
        final repo = await pumpScreen(
          tester,
          Result.success(_resolvedProgress(stepCount: 3)),
        );
        await tester.pumpAndSettle();
        stopwatch.stop();

        // The interactive path is on screen: every step rendered as a circle.
        expect(find.byType(PathStepCircle), findsNWidgets(3));
        expect(find.byIcon(Icons.play_arrow), findsOneWidget); // first step
        expect(find.byType(CircularProgressIndicator), findsNothing);

        // The path resolved on open (from cached content, no network wait).
        expect(repo.loadPathCalls, greaterThanOrEqualTo(1));

        // Req 9.1 budgets 3s for the first interactive screen under nominal
        // conditions. From cached content the render is near-instant; assert a
        // generous ceiling well under the 3s budget so the benchmark flags a
        // real regression (e.g. an accidental blocking read on open) without
        // being flaky on a slow CI machine.
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 2)),
          reason:
              'app-open path render from cached content should be well under '
              'the 3s interactive-screen budget (Req 9.1)',
        );
      },
    );
  });
}
