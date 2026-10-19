/// Base type for all domain-level failures surfaced by repositories.
///
/// Repositories normalize data-source errors into one of the concrete
/// subtypes so the application and presentation layers can branch on a
/// known, exhaustive set of failures instead of inspecting raw SDK
/// exceptions. See the design's Error Handling section.
sealed class AppException implements Exception {
  const AppException(this.message, [this.cause]);

  /// Human-readable description safe to surface in logs and, where
  /// appropriate, to the UI.
  final String message;

  /// The originating error, when one is available (e.g. a platform
  /// exception). Useful for logging and debugging.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// The device is offline or a network-required operation failed to reach
/// the backend. Network-required features should fail fast with a clear
/// message rather than hanging.
final class NetworkException extends AppException {
  const NetworkException([
    super.message =
        'A network error occurred. Check your connection and try again.',
    super.cause,
  ]);
}

/// Authentication or authorization failed (e.g. invalid credentials, an
/// expired session, or an unauthenticated request to a protected resource).
final class AuthException extends AppException {
  const AuthException([
    super.message = 'Authentication failed. Please sign in and try again.',
    super.cause,
  ]);
}

/// A per-user usage limit was reached (e.g. the free-tier AI quota). Maps
/// to the `limit_reached` status returned by AI functions.
final class UsageLimitException extends AppException {
  const UsageLimitException([
    super.message =
        'You have reached your usage limit. Try again later or upgrade.',
    super.cause,
  ]);
}

/// The request was refused by content moderation. Maps to the `refusal`
/// status returned by AI functions.
final class ModerationRefusalException extends AppException {
  const ModerationRefusalException([
    super.message = 'This request was blocked by content moderation.',
    super.cause,
  ]);
}

/// The requested resource does not exist.
final class NotFoundException extends AppException {
  const NotFoundException([
    super.message = 'The requested resource was not found.',
    super.cause,
  ]);
}
