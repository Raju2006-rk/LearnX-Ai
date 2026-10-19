// Widget test for the home streak flame indicator: it renders the learner's
// current streak from the progress provider, lights the flame when the streak
// is active, and stays muted with a zero when there is no streak yet.
// (Requirement 3.7)

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/app/router.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/firebase/firestore_paths.dart';
import 'package:learnx/features/progress/presentation/streak_flame_indicator.dart';

void main() {
  const uid = 'learner-1';
  late FakeFirebaseFirestore firestore;

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  Future<void> pump(WidgetTester tester, {String? signedInUid = uid}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseFirestoreProvider.overrideWithValue(firestore),
          authStateProvider.overrideWithValue(AuthState(uid: signedInUid)),
        ],
        child: const MaterialApp(
          home: Scaffold(
            appBar: null,
            body: Center(child: StreakFlameIndicator()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a muted zero when there is no streak yet', (tester) async {
    await pump(tester);

    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsNothing);
  });

  testWidgets('lights the flame with the current streak count', (tester) async {
    await firestore.doc(FirestorePaths.progressDoc(uid)).set(<String, dynamic>{
      'currentStreak': 5,
      'longestStreak': 8,
    });

    await pump(tester);

    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsNothing);
  });

  testWidgets('shows a zero when signed out', (tester) async {
    await pump(tester, signedInUid: null);

    expect(find.text('0'), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
  });
}
