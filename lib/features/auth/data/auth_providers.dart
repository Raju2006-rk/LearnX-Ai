import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import 'auth_data_source.dart';
import 'auth_repository.dart';

/// Riverpod providers wiring the auth data source and repository to the
/// shared Firebase clients.
///
/// The application layer (task 5.2's `AuthController`) depends on
/// [authRepositoryProvider]; tests override [firebaseAuthProvider] /
/// [firebaseFirestoreProvider] (or these providers directly) with fakes.

/// Exposes the [AuthDataSource] backed by the app's [FirebaseAuth] instance.
final authDataSourceProvider = Provider<AuthDataSource>(
  (ref) => AuthDataSource(ref.watch(firebaseAuthProvider)),
  name: 'authDataSourceProvider',
);

/// Exposes the [AuthRepository] backed by the auth data source and the app's
/// [FirebaseFirestore] instance.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    dataSource: ref.watch(authDataSourceProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
  name: 'authRepositoryProvider',
);
