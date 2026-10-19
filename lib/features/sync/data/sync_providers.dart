import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/restored_state.dart';
import 'restore_repository.dart';

/// Riverpod provider wiring the [RestoreRepository] to the shared Firestore
/// client. Tests override [firebaseFirestoreProvider] (or this provider
/// directly) with a fake.
final restoreRepositoryProvider = Provider<RestoreRepository>(
  (ref) => RestoreRepository(firestore: ref.watch(firebaseFirestoreProvider)),
  name: 'restoreRepositoryProvider',
);

/// The signed-in learner's one-shot cross-device [RestoredState], read from
/// `users/{uid}/**` when they sign in. (Requirement 8.3)
///
/// Resolves to [RestoredState.none] while signed out so consumers always have
/// a safe, non-null value without special-casing the signed-out state. When a
/// learner is signed in it reads the whole user tree once and rehydrates their
/// account, profile, streak, and completed-step set — so a learner arriving on
/// a new device recovers their state immediately rather than stitching several
/// reactive reads together.
///
/// Keyed on the uid via [authStateProvider]: signing in or out re-runs the
/// read against the current learner, and a failed restore surfaces as the
/// provider's error state for the caller to retry.
final restoredStateProvider = FutureProvider<RestoredState>((ref) async {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return RestoredState.none;
  final result = await ref.watch(restoreRepositoryProvider).restore(uid);
  return result.fold(
    (state) => state,
    (exception) => throw exception,
  );
}, name: 'restoredStateProvider');
