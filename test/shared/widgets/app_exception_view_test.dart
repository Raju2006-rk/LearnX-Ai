// Widget tests for the shared AppException → view mapper and the offline
// view. The mapper is the single place the typed AppException hierarchy turns
// into UI, deciding per failure kind whether an immediate retry is safe; it
// branches on the sealed type (which mirrors the AI `status` enum) rather than
// inspecting free-form message text. (Design "Error Handling"; Req 4.5, 6.6)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/shared/widgets/app_exception_view.dart';

Future<void> pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('AppExceptionView retry-where-safe mapping', () {
    testWidgets('NetworkException shows a retry action and offline glyph', (
      tester,
    ) async {
      var retried = false;
      await pump(
        tester,
        AppExceptionView(
          exception: const NetworkException(),
          onRetry: () => retried = true,
        ),
      );

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      expect(retried, isTrue);
    });

    testWidgets('NotFoundException shows a retry action', (tester) async {
      await pump(
        tester,
        AppExceptionView(
          exception: const NotFoundException(),
          onRetry: () {},
        ),
      );

      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('AuthException shows no retry even when onRetry is provided', (
      tester,
    ) async {
      var retried = false;
      await pump(
        tester,
        AppExceptionView(
          exception: const AuthException(),
          onRetry: () => retried = true,
        ),
      );

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      expect(retried, isFalse);
    });

    testWidgets('UsageLimitException renders an info view without retry', (
      tester,
    ) async {
      await pump(
        tester,
        AppExceptionView(
          exception: const UsageLimitException(),
          onRetry: () {},
        ),
      );

      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
      // A reached limit cannot be retried away, so no retry button is offered.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('ModerationRefusalException shows no retry', (tester) async {
      await pump(
        tester,
        AppExceptionView(
          exception: const ModerationRefusalException(),
          onRetry: () {},
        ),
      );

      expect(find.byIcon(Icons.block), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('surfaces the exception message, not a hardcoded string', (
      tester,
    ) async {
      await pump(
        tester,
        AppExceptionView(
          exception: const UsageLimitException('You hit the daily cap.'),
        ),
      );

      expect(find.text('You hit the daily cap.'), findsOneWidget);
    });
  });

  group('OfflineStateView', () {
    testWidgets('shows the offline glyph, message, and a retry action', (
      tester,
    ) async {
      var retried = false;
      await pump(
        tester,
        OfflineStateView(
          message: 'This feature needs a connection.',
          onRetry: () => retried = true,
        ),
      );

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.text('This feature needs a connection.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      expect(retried, isTrue);
    });
  });
}
