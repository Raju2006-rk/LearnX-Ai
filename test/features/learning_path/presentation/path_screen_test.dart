// Widget test for the home learning-path screen: it renders each step as a
// circle in its locked / available / completed state, opens an available
// step's detail on tap, and refuses to start a locked step.
// (Requirements 3.2, 3.3, 3.4)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/ai/ai_function_client.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/learning_path/domain/learning_path.dart';
import 'package:learnx/features/learning_path/presentation/path_screen.dart';

import '../learning_path_test_support.dart';

void main() {
  const uid = 'learner-1';
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> seedPath({int stepCount = 3}) async {
    await firestore.doc(FirestorePaths.sectionDoc(kDefaultPathId, 'sec1')).set(
      <String, dynamic>{'title': 'Section 1', 'order': 0},
    );
    await firestore
        .doc(FirestorePaths.weekDoc(kDefaultPathId, 'sec1', 'wk1'))
        .set(<String, dynamic>{'title': 'Week 1', 'order': 0});
    for (var i = 1; i <= stepCount; i++) {
      await firestore
          .doc(FirestorePaths.stepDoc(kDefaultPathId, 'sec1', 'wk1', 's$i'))
          .set(<String, dynamic>{
            'title': 'Step $i',
            'order': i,
            'type': 'lesson',
          });
    }
  }

  /// A minimal two-route router so tapping an available step can navigate to a
  /// recognizable step-detail stub without pulling in the whole app shell.
  /// The stub records the stepId it was routed to so the test can assert the
  /// navigation target. (The real StepDetailScreen owns completion; see
  /// step_detail_controller/screen.)
  GoRouter buildRouter() => GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const PathScreen()),
      GoRoute(
        path: '/step/:stepId',
        builder: (context, state) => Scaffold(
          body: Text('step-detail:${state.pathParameters['stepId']}'),
        ),
      ),
    ],
  );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(firestore),
          aiFunctionClientProvider.overrideWithValue(FakeAiFunctionClient()),
          authStateProvider.overrideWithValue(const AuthState(uid: uid)),
        ],
        child: MaterialApp.router(routerConfig: buildRouter()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Finds the [PathStepCircle] for a step by its title.
  Finder circleForTitle(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(PathStepCircle),
  );

  testWidgets(
    'renders a circle per step with the right state icons (Req 3.2)',
    (tester) async {
      await seedPath(stepCount: 3);
      await pumpScreen(tester);

      expect(find.byType(PathStepCircle), findsNWidgets(3));
      // First step available (play), the rest locked (lock).
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
      expect(find.byIcon(Icons.check), findsNothing);
    },
  );

  testWidgets('tapping an available step opens its detail screen (Req 3.4)', (
    tester,
  ) async {
    await seedPath(stepCount: 3);
    await pumpScreen(tester);

    await tester.tap(circleForTitle('Step 1'));
    await tester.pumpAndSettle();

    // The path screen routes to the available step's detail, where the
    // skeleton + personalization render and the learner marks it complete.
    expect(find.text('step-detail:s1'), findsOneWidget);
  });

  testWidgets('tapping a locked step does not start it (Req 3.3)', (
    tester,
  ) async {
    await seedPath(stepCount: 3);
    await pumpScreen(tester);

    await tester.tap(circleForTitle('Step 2'));
    await tester.pump(); // let the snackbar appear

    // No navigation happened: the path screen is still shown and the locked
    // step surfaced an explanation instead of opening.
    expect(find.text('step-detail:s2'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNWidgets(2));
    expect(
      find.text('Finish the previous step to unlock this one.'),
      findsOneWidget,
    );
  });
}
