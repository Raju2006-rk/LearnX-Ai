import 'package:flutter_test/flutter_test.dart';
import 'package:learnx/core/errors/app_exception.dart';
import 'package:learnx/core/result.dart';

void main() {
  group('Result construction and predicates', () {
    test('Result.success creates a Success carrying the value', () {
      const Result<int> result = Result.success(42);

      expect(result, isA<Success<int>>());
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.valueOrNull, 42);
      expect(result.exceptionOrNull, isNull);
    });

    test('Result.failure creates a Failure carrying the exception', () {
      const exception = NetworkException();
      const Result<int> result = Result.failure(exception);

      expect(result, isA<Failure<int>>());
      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.exceptionOrNull, same(exception));
    });

    test('Success with a null value is still a success', () {
      const Result<int?> result = Result.success(null);

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isNull);
      expect(result.exceptionOrNull, isNull);
    });
  });

  group('map', () {
    test('transforms the value of a Success', () {
      const Result<int> result = Result.success(21);

      final mapped = result.map((v) => v * 2);

      expect(mapped, isA<Success<int>>());
      expect(mapped.valueOrNull, 42);
    });

    test('can change the value type', () {
      const Result<int> result = Result.success(7);

      final mapped = result.map((v) => 'count=$v');

      expect(mapped, const Success<String>('count=7'));
    });

    test('preserves the exception of a Failure without invoking transform', () {
      const exception = AuthException();
      const Result<int> result = Result.failure(exception);
      var invoked = false;

      final mapped = result.map<int>((v) {
        invoked = true;
        return v * 2;
      });

      expect(invoked, isFalse);
      expect(mapped, isA<Failure<int>>());
      expect(mapped.exceptionOrNull, same(exception));
    });
  });

  group('flatMap', () {
    test('chains into the returned Result on Success', () {
      const Result<int> result = Result.success(10);

      final chained = result.flatMap((v) => Result.success(v + 5));

      expect(chained, const Success<int>(15));
    });

    test('propagates a failure produced by the transform', () {
      const Result<int> result = Result.success(10);
      const exception = NotFoundException();

      final chained = result.flatMap<int>((v) => const Result.failure(exception));

      expect(chained, isA<Failure<int>>());
      expect(chained.exceptionOrNull, same(exception));
    });

    test('preserves the original failure without invoking transform', () {
      const exception = UsageLimitException();
      const Result<int> result = Result.failure(exception);
      var invoked = false;

      final chained = result.flatMap<int>((v) {
        invoked = true;
        return Result.success(v);
      });

      expect(invoked, isFalse);
      expect(chained.exceptionOrNull, same(exception));
    });

    test('supports composing multiple chained steps', () {
      const Result<int> result = Result.success(2);

      final chained = result
          .flatMap((v) => Result.success(v + 3))
          .flatMap((v) => Result<int>.success(v * 4));

      expect(chained, const Success<int>(20));
    });
  });

  group('fold', () {
    test('applies onSuccess for a Success', () {
      const Result<int> result = Result.success(9);

      final folded = result.fold(
        (v) => 'ok:$v',
        (e) => 'err:${e.message}',
      );

      expect(folded, 'ok:9');
    });

    test('applies onFailure for a Failure', () {
      const exception = ModerationRefusalException('blocked');
      const Result<int> result = Result.failure(exception);

      final folded = result.fold(
        (v) => 'ok:$v',
        (e) => 'err:${e.message}',
      );

      expect(folded, 'err:blocked');
    });

    test('does not invoke the branch for the opposite case', () {
      const Result<int> success = Result.success(1);
      var failureInvoked = false;
      success.fold((v) => v, (e) {
        failureInvoked = true;
        return -1;
      });
      expect(failureInvoked, isFalse);

      const Result<int> failure = Result.failure(NetworkException());
      var successInvoked = false;
      failure.fold((v) {
        successInvoked = true;
        return v;
      }, (e) => -1);
      expect(successInvoked, isFalse);
    });
  });

  group('equality and toString', () {
    test('Success equals another Success with the same value', () {
      expect(const Success<int>(5), const Success<int>(5));
      expect(const Success<int>(5).hashCode, const Success<int>(5).hashCode);
      expect(const Success<int>(5), isNot(const Success<int>(6)));
    });

    test('Failure equals another Failure with the same exception', () {
      const a = Failure<int>(NetworkException('x'));
      const b = Failure<int>(NetworkException('x'));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('Success and Failure are never equal', () {
      expect(
        const Success<int>(1),
        isNot(const Failure<int>(NetworkException())),
      );
    });

    test('toString reflects the variant', () {
      expect(const Success<int>(3).toString(), 'Success(3)');
      expect(
        const Failure<int>(NotFoundException('gone')).toString(),
        contains('Failure('),
      );
    });
  });
}
