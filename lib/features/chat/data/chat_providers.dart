import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_function_client.dart';
import '../../../core/firebase/firebase_providers.dart';
import 'chat_repository.dart';

/// Riverpod provider wiring the [ChatRepository] to the shared AI function
/// client and Firestore instance.
///
/// The application layer (`ChatController`, task 7.2) depends on this
/// provider; tests override [aiFunctionClientProvider] /
/// [firebaseFirestoreProvider] (or this provider directly) with fakes.
final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(
    aiClient: ref.watch(aiFunctionClientProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
  name: 'chatRepositoryProvider',
);
