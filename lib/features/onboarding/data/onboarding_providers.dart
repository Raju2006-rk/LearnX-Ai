import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/ai/ai_function_client.dart';
import '../../../core/firebase/firebase_providers.dart';
import '../domain/learner_profile.dart';
import 'onboarding_repository.dart';
import 'placement_repository.dart';

/// Riverpod provider wiring the [OnboardingRepository] to the shared
/// Firestore client.
///
/// The application layer (`OnboardingController`) depends on this provider;
/// tests override [firebaseFirestoreProvider] (or this provider directly)
/// with a fake Firestore.
final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) =>
      OnboardingRepository(firestore: ref.watch(firebaseFirestoreProvider)),
  name: 'onboardingRepositoryProvider',
);

/// Riverpod provider wiring the [PlacementRepository] to the shared
/// [AiFunctionClient] (for the `generatePlacementQuestion` callable) and the
/// Firestore client (for persisting the placement result).
///
/// The application layer (`PlacementController`) depends on this provider;
/// tests override [aiFunctionClientProvider]/[firebaseFirestoreProvider] (or
/// this provider directly) with fakes.
final placementRepositoryProvider = Provider<PlacementRepository>(
  (ref) => PlacementRepository(
    aiClient: ref.watch(aiFunctionClientProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
  ),
  name: 'placementRepositoryProvider',
);

/// The signed-in learner's fully-restored [LearnerProfile], streamed from
/// their persisted `users/{uid}/profile/main` document. (Requirement 8.3)
///
/// This is the profile half of cross-device restore. It keys off the
/// [authStateProvider] uid seam, so the moment a returning learner's session
/// is established on a new device — whether from a cached session on launch or
/// a fresh sign-in — their complete profile (self-selected level/goal/native
/// language, placement level, onboarded flag) is read back from Firestore and
/// rehydrated here for app-wide consumers (e.g. the AI Teacher's
/// native-language translation, Requirement 4.3).
///
/// Mirrors [streakProvider]/[currentWeekSummaryProvider]: it emits
/// [LearnerProfile.none] while no learner is signed in so consumers always
/// have a safe, non-null value without special-casing the signed-out state.
/// The streak and progress halves of restore are already covered by those
/// `progress/main`-watching providers; together they rehydrate profile and
/// progress on the new device. Tests override [firebaseFirestoreProvider] /
/// [authStateProvider] (or this provider directly) with fakes.
final learnerProfileProvider = StreamProvider<LearnerProfile>((ref) {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return Stream<LearnerProfile>.value(LearnerProfile.none);
  return ref.watch(onboardingRepositoryProvider).watchProfile(uid);
}, name: 'learnerProfileProvider');
