// Widget tests for the shared loading / empty / error state views. These are
// the presentation-only building blocks every feature composes for consistent
// error/empty/loading states. (Design "Error Handling")

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/shared/widgets/app_state_view.dart';

Future<void> pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  group('LoadingStateView', () {
    testWidgets('shows a centered progress indicator', (tester) async {
      await pump(tester, const LoadingStateView());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('EmptyStateView', () {
    testWidgets('renders the message and default icon, no action', (
      tester,
    ) async {
      await pump(
        tester,
        const EmptyStateView(message: 'Nothing here yet.'),
      );

      expect(find.text('Nothing here yet.'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      // An empty state without an action shows no button.
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('renders a provided icon and action', (tester) async {
      var tapped = false;
      await pump(
        tester,
        EmptyStateView(
          message: 'All caught up.',
          icon: Icons.check_circle_outline,
          action: FilledButton(
            onPressed: () => tapped = true,
            child: const Text('Refresh'),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
      expect(tapped, isTrue);
    });
  });

  group('ErrorStateView', () {
    testWidgets('shows a retry button and invokes onRetry when safe', (
      tester,
    ) async {
      var retried = false;
      await pump(
        tester,
        ErrorStateView(
          message: 'Something broke.',
          onRetry: () => retried = true,
        ),
      );

      expect(find.text('Something broke.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      expect(retried, isTrue);
    });

    testWidgets('omits the retry button when onRetry is null', (tester) async {
      await pump(
        tester,
        const ErrorStateView(message: 'No retry here.'),
      );

      expect(find.text('No retry here.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('uses a custom icon and retry label', (tester) async {
      await pump(
        tester,
        ErrorStateView(
          message: 'Offline.',
          icon: Icons.wifi_off,
          retryLabel: 'Reconnect',
          onRetry: () {},
        ),
      );

      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Reconnect'), findsOneWidget);
    });
  });
}
