import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Riverpod providers exposing the core Firebase SDK singletons.
///
/// These are the single source of truth for the [FirebaseAuth],
/// [FirebaseFirestore], and [FirebaseFunctions] instances used across the
/// app. Data sources depend on these providers instead of reaching for the
/// SDK singletons directly, which keeps the dependency graph compile-safe and
/// lets tests override them with fakes/emulator-backed instances.
///
/// See the design's "Data source" layer responsibility and
/// "Client Components" table. (Requirements 10.1)

/// The app's [FirebaseAuth] instance.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
  name: 'firebaseAuthProvider',
);

/// The app's [FirebaseFirestore] instance.
///
/// Offline persistence is configured once at startup by the Firebase
/// initializer; this provider simply exposes the shared instance.
final firebaseFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
  name: 'firebaseFirestoreProvider',
);

/// The app's [FirebaseFunctions] instance.
///
/// All AI generation is routed through Cloud Functions (the `AI_Proxy`), so
/// this instance backs the [AiFunctionClient] and any other callable-function
/// data sources. (Requirements 11.1)
final firebaseFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instance,
  name: 'firebaseFunctionsProvider',
);
