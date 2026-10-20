import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/firebase/firebase_providers.dart';
import '../features/account/application/consent_controller.dart';
import '../features/account/data/consent_providers.dart';
import '../features/account/presentation/consent_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/onboarding/data/onboarding_providers.dart';
import '../features/onboarding/presentation/onboarding_flow_screen.dart';
import '../features/shell/presentation/account_screen.dart';
import '../features/shell/presentation/home_screen.dart';
import '../features/shell/presentation/premium_screen.dart';
import '../features/learning_path/presentation/step_detail_screen.dart';
import '../features/shell/presentation/shell_screen.dart';

/// Route path constants for the app.
///
/// Centralized so redirect guards and navigation callers reference the same
/// strings instead of hand-writing paths.
abstract final class Routes {
  const Routes._();

  /// The main authenticated shell (home learning path). (Requirement 2.6)
  static const String home = '/';

  /// The AI destination of the navigation shell. (Requirement 12.1)
  static const String ai = '/ai';

  /// The Account destination of the navigation shell. (Requirement 12.1)
  static const String account = '/account';

  /// The Premium placeholder screen shown in the MVP. (Requirement 12.3)
  static const String premium = '/premium';

  /// The step-detail route, nested under home, parameterized by `stepId`.
  /// Combines the authored skeleton with AI personalization. (Req 3.5, 3.6)
  static String stepDetail(String stepId) => '/step/$stepId';

  /// The sign-in screen shown to unauthenticated learners. (Requirement 1.x)
  static const String signIn = '/sign-in';

  /// The DPDP consent screen shown on first run after auth, before onboarding.
  /// (Requirement 10.3)
  static const String consent = '/consent';

  /// The onboarding flow shown to authenticated-but-not-onboarded learners.
  /// (Requirement 2.x)
  static const String onboarding = '/onboarding';
}

/// A snapshot of the learner's authentication session.
///
/// This is the seam the router reads to decide routing. The default
/// [authStateProvider] derives it from the cached Firebase user for instant
/// launch routing; the auth feature (task 5.x) overrides the provider with a
/// controller-backed implementation.
@immutable
class AuthState {
  /// Creates an auth state for a signed-in learner identified by [uid].
  const AuthState({required this.uid});

  /// Creates the signed-out auth state.
  const AuthState.signedOut() : uid = null;

  /// The signed-in learner's uid, or `null` when signed out.
  final String? uid;

  /// Whether a learner is currently signed in.
  bool get isSignedIn => uid != null;

  @override
  bool operator ==(Object other) => other is AuthState && other.uid == uid;

  @override
  int get hashCode => uid.hashCode;
}

/// Exposes the current [AuthState], seeded synchronously from the cached
/// Firebase user so routing on launch has no async gap that would flash the
/// wrong screen. (Requirements 1.6, 9.1)
///
/// The provider seeds from [FirebaseAuth.currentUser] (available synchronously
/// once Firebase is initialized) and invalidates itself when the auth state
/// changes, so redirect guards always read a fresh value. The auth feature
/// (task 5.x) can override this provider with a richer, controller-backed
/// implementation without touching the router.
final authStateProvider = Provider<AuthState>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  final subscription = auth.authStateChanges().listen(
    (_) => ref.invalidateSelf(),
  );
  ref.onDispose(subscription.cancel);
  return AuthState(uid: auth.currentUser?.uid);
}, name: 'authStateProvider');

/// Streams the persisted DPDP consent flag for the signed-in learner,
/// `users/{uid}.consent.dpdpAccepted`.
///
/// Watches the user root document so recorded consent is reflected the moment
/// it is persisted and on a returning/other device (cross-device restore).
/// Emits `false` while signed out, before the first snapshot arrives, or when
/// no consent block exists yet. (Requirement 10.3)
///
/// [consentProvider] combines this persisted value with the in-session
/// [consentControllerProvider] acceptance, so the router advances without
/// waiting for the write to round-trip. Tests override [consentProvider]
/// directly.
final recordedConsentProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return Stream<bool>.value(false);
  // A Firestore read that is rejected (rules), unreachable (offline), or slow
  // must not surface as an uncaught provider error that the router treats as a
  // dead loading state. Map any stream error to `false` ("not consented yet"),
  // so the learner is routed to the consent screen to retry rather than a
  // blank/spinning screen. `consentProvider` already treats loading as `false`.
  return ref
      .watch(consentRepositoryProvider)
      .watchDpdpAccepted(uid)
      .handleError((Object error, StackTrace _) {});
}, name: 'recordedConsentProvider');

/// Whether the signed-in learner has recorded DPDP consent.
///
/// The seam consumed by the router's redirect guard. It is `true` when either
/// the in-session consent flow recorded acceptance
/// ([consentControllerProvider]) or the persisted
/// `users/{uid}.consent.dpdpAccepted` flag ([recordedConsentProvider]) is set,
/// so the router advances the learner immediately on accept and also honors
/// consent recorded on a previous session/device. Consent gates onboarding
/// because the security rules require recorded consent before any
/// profile/feature write succeeds. (Requirement 10.3)
///
/// Tests override this provider directly to drive the redirect guard.
final consentProvider = Provider<bool>((ref) {
  final acceptedThisSession = ref.watch(
    consentControllerProvider.select((s) => s.accepted),
  );
  final persisted = ref.watch(recordedConsentProvider).asData?.value ?? false;
  return acceptedThisSession || persisted;
}, name: 'consentProvider');

/// Streams the persisted `onboarded` flag for the signed-in learner from
/// `users/{uid}/profile/main`.
///
/// Watches the profile document so the router advances to home the moment
/// placement marks the profile onboarded, and reflects an already-onboarded
/// profile on a returning/other device. Emits `false` while signed out, before
/// the first snapshot arrives, or when no profile exists yet. (Requirement 2.6)
final recordedOnboardedProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(authStateProvider).uid;
  if (uid == null) return Stream<bool>.value(false);
  // Same resilience as the consent gate: a rejected/slow/unreachable profile
  // read must resolve to `false` (not onboarded yet) and emit immediately,
  // never leaving the router pinned on a loading state. (See
  // [recordedConsentProvider].)
  // Same resilience as the consent gate: a rejected/slow/unreachable profile
  // read maps to `false` (not onboarded yet) instead of an uncaught provider
  // error, so the router never hangs. (See [recordedConsentProvider].)
  return ref
      .watch(onboardingRepositoryProvider)
      .watchOnboarded(uid)
      .handleError((Object error, StackTrace _) {});
}, name: 'recordedOnboardedProvider');

/// Whether the signed-in learner has completed onboarding.
///
/// The seam consumed by the router's redirect guard. It reflects the persisted
/// `profile/main.onboarded` flag ([recordedOnboardedProvider]), which the
/// adaptive placement flow sets once the learner has a level, goal, native
/// language, and placement result â€” so completing placement routes the learner
/// to home, and a returning onboarded learner skips onboarding. Defaults to
/// `false` (not onboarded) until the first snapshot arrives. Tests override
/// this provider directly to drive the redirect guard. (Requirement 2.6)
final onboardedProvider = Provider<bool>(
  (ref) => ref.watch(recordedOnboardedProvider).asData?.value ?? false,
  name: 'onboardedProvider',
);

/// The app's [GoRouter], wired with sign-in, onboarding, and main-shell
/// routes plus redirect guards.
///
/// Guard logic (evaluated on every navigation and whenever the auth, consent,
/// or onboarding seams change):
/// - unauthenticated â†’ sign-in
/// - authenticated but consent not recorded â†’ consent (Requirement 10.3)
/// - authenticated and consented but not onboarded â†’ onboarding (Requirement
///   2.6)
/// - authenticated, consented, and onboarded â†’ home, and kept away from the
///   sign-in, consent, and onboarding routes
///
/// Consent is checked before onboarding because the security rules gate every
/// profile/feature write on recorded consent, so it must be captured first.
///
/// The router reads the [authStateProvider], [consentProvider], and
/// [onboardedProvider] seams via `ref.read` inside the redirect so it
/// re-evaluates against current state without rebuilding the whole router
/// (which would drop navigation state). A refresh listenable, driven by
/// changes to those seams, triggers re-evaluation. (Requirements 1.6, 2.6,
/// 9.1, 10.3)
final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier();
  ref.listen<AuthState>(authStateProvider, (previous, next) {
    refresh.notify();
  });
  ref.listen<bool>(consentProvider, (previous, next) {
    refresh.notify();
  });
  ref.listen<bool>(onboardedProvider, (previous, next) {
    refresh.notify();
  });
  ref.onDispose(refresh.dispose);

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final consented = ref.read(consentProvider);
      final onboarded = ref.read(onboardedProvider);

      final location = state.matchedLocation;
      final atSignIn = location == Routes.signIn;
      final atConsent = location == Routes.consent;
      final atOnboarding = location == Routes.onboarding;

      // Unauthenticated learners can only be on the sign-in screen.
      if (!auth.isSignedIn) {
        return atSignIn ? null : Routes.signIn;
      }

      // Signed in but no consent recorded â†’ capture consent first, since
      // the rules gate every profile/feature write on it. (Requirement 10.3)
      if (!consented) {
        return atConsent ? null : Routes.consent;
      }

      // Signed in and consented but not onboarded â†’ send to onboarding.
      // (Requirement 2.6)
      if (!onboarded) {
        return atOnboarding ? null : Routes.onboarding;
      }

      // Signed in, consented, and onboarded â†’ keep away from the
      // auth/consent/onboarding flows.
      if (atSignIn || atConsent || atOnboarding) {
        return Routes.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: Routes.signIn,
        name: 'signIn',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.consent,
        name: 'consent',
        builder: (context, state) => const ConsentScreen(),
      ),
      GoRoute(
        path: Routes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingFlowScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            ShellScreen(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                name: 'home',
                builder: (context, state) => const HomeScreen(),
                routes: [
                  GoRoute(
                    path: 'premium',
                    name: 'premium',
                    builder: (context, state) => const PremiumScreen(),
                  ),
                  GoRoute(
                    path: 'step/:stepId',
                    name: 'stepDetail',
                    builder: (context, state) => StepDetailScreen(
                      stepId: state.pathParameters['stepId']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.ai,
                name: 'ai',
                builder: (context, state) => const ChatScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.account,
                name: 'account',
                builder: (context, state) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
}, name: 'appRouterProvider');

/// A [ChangeNotifier] the router uses as its `refreshListenable`.
///
/// Notified whenever the auth or onboarding seams change so the router
/// re-runs its redirect guard without a full rebuild.
class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}




