// Widget test for the sign-in screen's error handling.
//
// Verifies that when a sign-in attempt fails, the error message is displayed
// and the learner stays on the sign-in screen. (Requirement 1.5)

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/auth/data/auth_providers.dart';
import 'package:learnx/features/auth/data/auth_repository.dart';
import 'package:learnx/features/auth/domain/auth_session.dart';
import 'package:learnx/features/auth/presentation/sign_in_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late MockAuthRepository repository;

  setUp(() {
    repository = MockAuthRepository();
  });

  Future<void> pumpSignIn(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
  }

  testWidgets(
    'email sign-in failure shows the error and keeps the learner on the screen',
    (WidgetTester tester) async {
      const message = 'Authentication failed. Please try again.';
      when(
        () => repository.signInWithEmail(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer(
        (_) async => const Result<AuthSession>.failure(AuthException(message)),
      );

      await pumpSignIn(tester);

      // Choose the email method, fill the form, and submit.
      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'learner@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'wrong-password',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
      await tester.pumpAndSettle();

      // The error message is displayed and the sign-in screen is still shown.
      expect(find.text(message), findsOneWidget);
      expect(find.byType(SignInScreen), findsOneWidget);
      verify(
        () => repository.signInWithEmail(
          email: 'learner@example.com',
          password: 'wrong-password',
        ),
      ).called(1);
    },
  );

  testWidgets('Google sign-in failure shows the error message', (
    WidgetTester tester,
  ) async {
    const message = 'A network error occurred.';
    when(repository.signInWithGoogle).thenAnswer(
      (_) async =>
          const Result<AuthSession>.failure(NetworkException(message)),
    );

    await pumpSignIn(tester);

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
