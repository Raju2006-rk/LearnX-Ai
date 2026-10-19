import 'errors/app_exception.dart';

/// A discriminated union representing either a successful value of type [T]
/// ([Success]) or a typed failure ([Failure]) carrying an [AppException].
///
/// Repositories return `Result<T>` so callers handle success and failure
/// explicitly without try/catch at every call site. See the design's
/// Error Handling section.
sealed class Result<T> {
  const Result();

  /// Creates a successful result wrapping [value].
  const factory Result.success(T value) = Success<T>;

  /// Creates a failed result wrapping [exception].
  const factory Result.failure(AppException exception) = Failure<T>;

  /// Whether this result represents success.
  bool get isSuccess => this is Success<T>;

  /// Whether this result represents failure.
  bool get isFailure => this is Failure<T>;

  /// The success value, or `null` when this is a [Failure].
  T? get valueOrNull => switch (this) {
        Success<T>(:final value) => value,
        Failure<T>() => null,
      };

  /// The failure exception, or `null` when this is a [Success].
  AppException? get exceptionOrNull => switch (this) {
        Success<T>() => null,
        Failure<T>(:final exception) => exception,
      };

  /// Transforms the success value with [transform], preserving a failure
  /// unchanged.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
        Success<T>(:final value) => Success<R>(transform(value)),
        Failure<T>(:final exception) => Failure<R>(exception),
      };

  /// Chains a computation that itself returns a [Result], preserving a
  /// failure unchanged. Also known as `andThen`/`bind`.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) =>
      switch (this) {
        Success<T>(:final value) => transform(value),
        Failure<T>(:final exception) => Failure<R>(exception),
      };

  /// Collapses this result into a single value of type [R] by applying
  /// [onSuccess] to a success value or [onFailure] to a failure exception.
  R fold<R>(
    R Function(T value) onSuccess,
    R Function(AppException exception) onFailure,
  ) =>
      switch (this) {
        Success<T>(:final value) => onSuccess(value),
        Failure<T>(:final exception) => onFailure(exception),
      };
}

/// A successful [Result] carrying a [value].
final class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  bool operator ==(Object other) =>
      other is Success<T> && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'Success($value)';
}

/// A failed [Result] carrying an [exception].
final class Failure<T> extends Result<T> {
  const Failure(this.exception);

  final AppException exception;

  @override
  bool operator ==(Object other) =>
      other is Failure<T> && other.exception == exception;

  @override
  int get hashCode => exception.hashCode;

  @override
  String toString() => 'Failure($exception)';
}
