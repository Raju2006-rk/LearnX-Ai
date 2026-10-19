// Widget tests for the DPDP consent screen: the learner must agree before the
// action is enabled, accepting records consent via the repository, and a
// failure surfaces an error while keeping the learner on the screen.
// (Requirement 10.3)

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/firebase/firebase_providers.dart';
import 'package:learnx/core/result.dart';
import 'package:learnx/features/account/data/consent_providers.dart';
import 'package:learnx/features/account/data/consent_repository.dart';
import 'package:learnx/features/account/presentation/consent_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockConsentRepository extends Mock implements ConsentRepository {}

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

void main() {
  late MockConsentRepository repository;
  late MockFirebaseAuth auth;

  const uid = 'user-123';

  setUp(() {
    repository = MockConsentRepository();
    auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
  });

  Future<void> pumpConsent(WidgetTester tester) {
    return tester.pumpWidget(
      ProviderScope(
        overrides: [
          consentRepositoryProvider.overrideWithValue(repository),
          firebaseAuthProvider.overrideWithValue(auth),
        ],
        child: const MaterialApp(home: ConsentScreen()),
      ),
    );
  }

  testWidgets('renders the DPDP notice and policy version', (tester) async {
    await pumpConsent(tester);

    expect(find.text('How LearnX uses your data'), findsOneWidget);
    expect(find.text('Policy version v1'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
  });

  testWidgets('the action is disabled until the learner agrees',
      (tester) async {
    await pumpConsent(tester);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Agree and continue'),
    );
    expect(button.onPressed, isNull);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();

    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Agree and continue'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('agreeing records consent via the repository', (tester) async {
    when(() => repository.acceptDpdp(uid: any(named: 'uid')))
        .thenAnswer((_) async => const Result<void>.success(null));

    await pumpConsent(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Agree and continue'));
    await tester.pumpAndSettle();

    verify(() => repository.acceptDpdp(uid: uid)).called(1);
  });

  testWidgets('a failure shows an error and keeps the learner on the screen',
      (tester) async {
    const message = 'Could not record your consent. Please try again.';
    when(() => repository.acceptDpdp(uid: any(named: 'uid'))).thenAnswer(
      (_) async => const Result<void>.failure(AuthException(message)),
    );

    await pumpConsent(tester);

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Agree and continue'));
    await tester.pumpAndSettle();

    expect(find.text(message), findsOneWidget);
    expect(find.byType(ConsentScreen), findsOneWidget);
  });
}
