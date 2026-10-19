import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import 'consent_repository.dart';

/// Riverpod provider wiring the [ConsentRepository] to the shared Firestore
/// client.
///
/// The application layer (`ConsentController`) depends on this provider; tests
/// override [firebaseFirestoreProvider] (or this provider directly) with a
/// fake Firestore.
final consentRepositoryProvider = Provider<ConsentRepository>(
  (ref) => ConsentRepository(
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
  name: 'consentRepositoryProvider',
);
