import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';

void main() {
  group('AppException hierarchy', () {
    test('every concrete exception is an AppException and an Exception', () {
      final exceptions = <AppException>[
        const NetworkException(),
        const AuthException(),
        const UsageLimitException(),
        const ModerationRefusalException(),
        const NotFoundException(),
      ];

      for (final e in exceptions) {
        expect(e, isA<AppException>());
        expect(e, isA<Exception>());
      }
    });

    test('each subtype exposes a non-empty default message', () {
      expect(const NetworkException().message, isNotEmpty);
      expect(const AuthException().message, isNotEmpty);
      expect(const UsageLimitException().message, isNotEmpty);
      expect(const ModerationRefusalException().message, isNotEmpty);
      expect(const NotFoundException().message, isNotEmpty);
    });

    test('custom message overrides the default', () {
      const e = NetworkException('offline right now');
      expect(e.message, 'offline right now');
    });

    test('cause is retained when provided', () {
      final cause = StateError('boom');
      final e = AuthException('failed', cause);

      expect(e.cause, same(cause));
    });

    test('cause defaults to null', () {
      expect(const NotFoundException().cause, isNull);
    });

    test('toString includes the runtime type and the message', () {
      const e = UsageLimitException('quota gone');
      final text = e.toString();

      expect(text, contains('UsageLimitException'));
      expect(text, contains('quota gone'));
    });
  });

  group('exhaustive switch over AppException', () {
    // Exercises the sealed nature: a switch mapping each subtype to a code
    // must compile without a default clause, and route each value correctly.
    String code(AppException e) => switch (e) {
          NetworkException() => 'network',
          AuthException() => 'auth',
          UsageLimitException() => 'limit',
          ModerationRefusalException() => 'refusal',
          NotFoundException() => 'not_found',
        };

    test('maps each subtype to its code', () {
      expect(code(const NetworkException()), 'network');
      expect(code(const AuthException()), 'auth');
      expect(code(const UsageLimitException()), 'limit');
      expect(code(const ModerationRefusalException()), 'refusal');
      expect(code(const NotFoundException()), 'not_found');
    });
  });
}
