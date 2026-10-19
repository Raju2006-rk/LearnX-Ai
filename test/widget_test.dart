// Smoke test for the LearnX app shell.
//
// Verifies that the root widget boots inside a ProviderScope and that the
// router's redirect guards route a signed-in, onboarded learner to the home
// shell via MaterialApp.router. The auth/onboarding seams are overridden so
// the test boots without a live Firebase instance.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:learnx/app/app.dart';
import 'package:learnx/app/router.dart';

void main() {
  testWidgets('LearnXApp routes a signed-in, onboarded learner to the shell', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWithValue(const AuthState(uid: 'test-uid')),
          consentProvider.overrideWithValue(true),
          onboardedProvider.overrideWithValue(true),
        ],
        child: const LearnXApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The shell boots on the Home branch and shows the bottom navigation with
    // Home / AI / Account destinations. (Requirements 12.1, 12.2)
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('AI'), findsWidgets);
    expect(find.text('Account'), findsWidgets);
  });

  testWidgets('unauthenticated learner is routed to sign-in', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWithValue(const AuthState.signedOut()),
        ],
        child: const LearnXApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('signed-in but not onboarded learner is routed to onboarding', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWithValue(const AuthState(uid: 'test-uid')),
          consentProvider.overrideWithValue(true),
          onboardedProvider.overrideWithValue(false),
        ],
        child: const LearnXApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The onboarding flow opens on its first step (English level selection).
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text("What's your English level?"), findsOneWidget);
  });

  testWidgets('signed-in but not-consented learner is routed to consent', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWithValue(const AuthState(uid: 'test-uid')),
          consentProvider.overrideWithValue(false),
          // Even though onboarded is true, consent must be captured first.
          onboardedProvider.overrideWithValue(true),
        ],
        child: const LearnXApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The DPDP consent screen is shown before onboarding/home. (Req 10.3)
    expect(find.text('How LearnX uses your data'), findsOneWidget);
    expect(find.text('Agree and continue'), findsOneWidget);
  });
}
