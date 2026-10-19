import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A thin wrapper over platform secure storage for sensitive local values
/// such as auth tokens.
///
/// Sensitive values are kept in the OS-backed secure store (Keychain,
/// Keystore, etc.) rather than plain preferences. (Requirements 10.1)
///
/// The wrapper exposes an intent-revealing, token-oriented API and hides the
/// underlying [FlutterSecureStorage] so callers never depend on the plugin
/// directly and tests can substitute a fake.
class SecureStorage {
  const SecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  /// Key under which the auth token is persisted.
  static const String authTokenKey = 'auth_token';

  /// Key under which the refresh token is persisted.
  static const String refreshTokenKey = 'refresh_token';

  /// Reads the stored auth token, or `null` when none is present.
  Future<String?> readAuthToken() => read(authTokenKey);

  /// Persists the auth token.
  Future<void> writeAuthToken(String token) => write(authTokenKey, token);

  /// Removes the stored auth token.
  Future<void> deleteAuthToken() => delete(authTokenKey);

  /// Reads the stored refresh token, or `null` when none is present.
  Future<String?> readRefreshToken() => read(refreshTokenKey);

  /// Persists the refresh token.
  Future<void> writeRefreshToken(String token) =>
      write(refreshTokenKey, token);

  /// Removes the stored refresh token.
  Future<void> deleteRefreshToken() => delete(refreshTokenKey);

  /// Reads an arbitrary secure value by [key].
  Future<String?> read(String key) => _storage.read(key: key);

  /// Writes an arbitrary secure [value] under [key].
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  /// Deletes the secure value stored under [key].
  Future<void> delete(String key) => _storage.delete(key: key);

  /// Clears all secured values. Used on sign-out and account deletion.
  Future<void> clear() => _storage.deleteAll();
}

/// Exposes the platform [FlutterSecureStorage] as a provider.
///
/// Overridable in tests with an in-memory fake.
final flutterSecureStorageProvider = Provider<FlutterSecureStorage>(
  (ref) => const FlutterSecureStorage(),
  name: 'flutterSecureStorageProvider',
);

/// The app-facing [SecureStorage] wrapper.
final secureStorageProvider = Provider<SecureStorage>(
  (ref) => SecureStorage(ref.watch(flutterSecureStorageProvider)),
  name: 'secureStorageProvider',
);
