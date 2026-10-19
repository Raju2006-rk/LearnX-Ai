import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_function_client.dart';
import '../../../core/firebase/firebase_providers.dart';
import 'content_cache_data_source.dart';
import 'path_repository.dart';

/// Riverpod provider for the app-lifetime authored-content offline cache.
///
/// Held as its own provider so it is a single shared instance across every
/// step open (the cache only helps if it outlives individual reads) and so
/// tests can seed or inspect it by overriding this provider. (Requirement 8.1)
final contentCacheDataSourceProvider = Provider<ContentCacheDataSource>(
  (ref) => ContentCacheDataSource(),
  name: 'contentCacheDataSourceProvider',
);

/// Riverpod provider wiring the [PathRepository] to the shared Firestore
/// client, the [AiFunctionClient] used for lesson personalization, and the
/// authored-content offline cache.
///
/// The application layer (`PathController`, `StepDetailController`) depends on
/// this provider; tests override [firebaseFirestoreProvider] /
/// [aiFunctionClientProvider] / [contentCacheDataSourceProvider] (or this
/// provider directly) with fakes.
final pathRepositoryProvider = Provider<PathRepository>(
  (ref) => PathRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
    aiClient: ref.watch(aiFunctionClientProvider),
    contentCache: ref.watch(contentCacheDataSourceProvider),
  ),
  name: 'pathRepositoryProvider',
);
