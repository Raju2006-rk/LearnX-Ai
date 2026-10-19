# Implementation Plan: LearnX MVP

## Overview

This plan builds LearnX bottom-up so the app stays runnable at every checkpoint: scaffolding and the core layer first, then the data model and security rules, then the server-side AI_Proxy (with a fake provider for tests), and finally the client features (auth/onboarding, navigation + learning path, chat, quizzes, progress, offline sync) followed by cross-cutting hardening.

The client is Flutter/Dart (mobile, web, desktop) with Riverpod + go_router; Cloud Functions are TypeScript. Property-based tests from the design's Correctness Properties section (Properties 1–24) are wired in next to the features they validate. Test sub-tasks are marked optional with `*`; core implementation tasks are required.

## Tasks

- [x] 1. Project scaffolding and core layer
  - [x] 1.1 Create the Flutter app and platform targets
    - Initialize the Flutter project for mobile, web, and desktop targets
    - Add dependencies: `flutter_riverpod`/`riverpod_annotation`, `go_router`, `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions`, `firebase_remote_config`, `flutter_secure_storage`, `connectivity_plus`, and test deps (`mocktail`, `fake_cloud_firestore` where useful)
    - Create the feature-first folder structure under `lib/` per the design (`app/`, `core/`, `features/{auth,onboarding,learning_path,chat,quiz,progress,account,shell}/{presentation,application,data,domain}`, `shared/`)
    - _Requirements: 9.3_
  - [x] 1.2 Wire Firebase into the client
    - Add FlutterFire configuration (`firebase_options.dart`) and initialize `Firebase.initializeApp` in `main.dart`
    - Enable Firestore offline persistence on mobile targets
    - _Requirements: 10.1, 8.2_
  - [x] 1.3 Implement the `core` layer primitives
    - Add `core/result.dart` with `Result<T>` (success/failure)
    - Add `core/errors/` with the `AppException` hierarchy: `NetworkException`, `AuthException`, `UsageLimitException`, `ModerationRefusalException`, `NotFoundException`
    - _Requirements: 9.3_
  - [x] 1.4 Implement core infrastructure providers
    - Add `core/firebase/firebase_providers.dart` exposing `FirebaseAuth`, `FirebaseFirestore`, `FirebaseFunctions` as Riverpod providers
    - Add `core/network/connectivity.dart` with an online/offline stream provider
    - Add `core/storage/secure_storage.dart` wrapping platform secure storage for tokens
    - Add `core/config/remote_config.dart` exposing tier usage limits and feature flags
    - Add `core/ai/ai_function_client.dart` with `httpsCallable` + streaming wrappers
    - _Requirements: 10.1, 11.3_
  - [x] 1.5 Write unit tests for the core layer
    - Test `Result<T>` map/fold and exception mapping helpers
    - Test the connectivity stream and remote-config limit lookups with fakes
    - _Requirements: 9.3_
  - [x] 1.6 Set up Riverpod root and app shell entry
    - Wrap the app in `ProviderScope` and create `app/app.dart` (MaterialApp.router + theme)
    - _Requirements: 12.1_
  - [x] 1.7 Configure go_router with auth and onboarding guards
    - Add `app/router.dart` with routes for sign-in, onboarding, and the main shell
    - Add redirect guards: unauthenticated → sign-in; authenticated but not onboarded → onboarding; onboarded → home
    - Use cached auth session for instant routing on launch
    - _Requirements: 1.6, 2.6, 9.1_

- [x] 2. Firestore data model and security rules
  - [x] 2.1 Define Firestore collection constants and DTO mappers
    - Add path/collection helpers and DTO ⇄ domain mappers for `users`, `profile`, `content` (paths/sections/weeks/steps), `pathProgress`, `chatSessions`, `reports`, `quizItems`, `reviewQueue`, `quizSessions`, `progress`, `weeklySummaries`, `usage` per the design data model
    - _Requirements: 3.1_
  - [x] 2.2 Author Firestore security rules
    - Default-deny; per-user isolation on `users/{uid}/**` (`request.auth.uid == uid`)
    - Deny client writes to `usage/**` and `reports/**` write is server-only; allow client read of own `usage`
    - Make `accountTier` and `consent.policyVersion` read-only to clients
    - `content/**` and `quizItems/**` read-only to authenticated users
    - Enum validation on write for `nativeLanguage`, `goal`, `englishLevel`, `placementLevel`, `badge.tier`
    - Consent gate: feature-data writes require `consent.dpdpAccepted == true`
    - _Requirements: 2.3, 2.5, 10.3, 11.3, 11.4_
  - [x] 2.3 Write security-rules emulator tests
    - Per-user isolation (cannot read/write another uid)
    - Client cannot write `usage` or `reports`; can read own `usage`
    - Enum validation rejects invalid `nativeLanguage`/`goal`/`englishLevel`/`badge.tier`
    - **Property 2: Native language accepted only from the allowed set** — Validates Requirements 2.3
    - **Property 21: Processing is gated on recorded consent** (rules-level: feature write blocked without consent) — Validates Requirements 10.3
    - _Requirements: 2.3, 10.3, 11.3, 11.4_

- [x] 3. Cloud Functions AI_Proxy
  - [x] 3.1 Scaffold the Functions project and provider abstraction
    - Initialize `functions/` (TypeScript), configure emulator, add lint/test tooling
    - Define `AiRequest`, `AiResult`, and the `AiProvider` interface per the design
    - Implement `resolveProvider()` config-driven selection and a `providerRegistry`
    - _Requirements: 10.2, 11.1, 11.2_
  - [x] 3.2 Implement `GeminiProvider` and a fake `AiProvider`
    - Implement `GeminiProvider` (Firebase AI Logic / Vertex AI) for `generate` and `generateStream`, normalizing to `AiResult`
    - Implement an in-memory fake `AiProvider` for tests (deterministic outputs, injectable streams)
    - _Requirements: 11.2_
  - [x] 3.3 Implement the moderation service
    - Add a swappable `moderate()` step applied to both input and output
    - On unsafe verdict, withhold flagged content and return a safe substitute/refusal
    - _Requirements: 5.1, 5.2, 10.4_
  - [x] 3.4 Implement the metered AI middleware
    - Implement `meteredAi(context, kind, handler)` with gate order: require auth → read tier → read today's usage → limit check (provider NOT called on limit) → input moderation → provider call → output moderation → increment usage only on success
    - Read limits from Remote Config; write counters to `users/{uid}/usage/{yyyy-mm-dd}` via Admin SDK
    - _Requirements: 4.6, 5.1, 5.2, 11.3, 11.4_
  - [x] 3.5 Implement `chatWithTeacher` (streaming callable)
    - Input `{ sessionId, text }`; stream reply tokens as soon as the provider streams
    - Return a `Grammar_Feedback` object; persist message + feedback to `chatSessions/{sessionId}/messages`
    - _Requirements: 4.1, 4.2, 4.3, 4.4_
  - [x] 3.6 Implement `Grammar_Feedback` schema validation
    - Validate provider structured output against the design JSON schema before returning
    - Omit `mistakeSpan` when `hasMistake` is false; require `correctedSentence`, `tip`, `translation`
    - _Requirements: 4.2, 4.3_
  - [x] 3.7 Implement `personalizeLesson` with skeleton fallback
    - Input `{ stepId }`; return CEFR/goal-tagged examples/practice
    - On any failure or moderation refusal, return empty/`null` personalization so the client falls back to authored skeleton
    - _Requirements: 3.5, 3.6_
  - [x] 3.8 Implement `generatePlacementQuestion`
    - Input `{ sessionState }` (difficulty band + prior answers); return the next adaptive question with server-held answer key
    - _Requirements: 2.4_
  - [x] 3.9 Implement `deleteMyData` callable
    - Remove `users/{uid}/**` subtree and associated `reports`, revoke the auth user
    - _Requirements: 10.3_
  - [x] 3.10 Implement the scheduled weekly-summary function
    - Aggregate `dailyActivity/*` into `weeklySummaries/{isoWeek}` (time spent, words learned, mistakes fixed)
    - _Requirements: 7.4_
  - [x] 3.11 Write function emulator + property tests for the AI_Proxy
    - Middleware gate-order tests with the fake provider and mocked Firestore
    - Moderation refusal path (input and output) and usage-counter increment behavior
    - **Property 22: Provider substitutability** (fake provider yields schema-conformant response, no client change) — Validates Requirements 11.2
    - **Property 23: Usage-limit gate** (allow iff u < L; on limit-reached provider not invoked and counter unchanged) — Validates Requirements 4.6, 11.3, 11.4
    - **Property 9: Unsafe content is never passed through** — Validates Requirements 5.2, 10.4
    - **Property 21: Processing gated on recorded consent** (function-level check) — Validates Requirements 10.3
    - **Property 18: Weekly summary aggregates match underlying events** — Validates Requirements 7.4
    - _Requirements: 4.6, 5.2, 7.4, 10.3, 10.4, 11.2, 11.3, 11.4_

- [x] 4. Checkpoint - backend and scaffolding
  - Ensure all tests pass (core, rules emulator, function emulator), ask the user if questions arise.

- [x] 5. Authentication and onboarding
  - [x] 5.1 Implement auth domain, data source, and repository
    - Add `AuthSession`, `AuthMethod` domain types
    - Implement `AuthDataSource` (phone OTP, Google, email/password) and `AuthRepository` returning `Result<AuthSession>`; create-or-restore account and profile on success
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6_
  - [x] 5.2 Implement `AuthController` and sign-in UI
    - Riverpod `Notifier` mapping exceptions to states; sign-in screen with method selection
    - On failure, show an error and keep the learner on the sign-in screen
    - _Requirements: 1.1, 1.2, 1.3, 1.5_
  - [x] 5.3 Write auth tests
    - Widget test: sign-in error handling keeps user on screen
    - **Property 1: Successful authentication yields a signed-in session with a profile** — Validates Requirements 1.4
    - _Requirements: 1.4, 1.5_
  - [x] 5.4 Implement consent capture
    - On first run after auth, present a DPDP consent screen; record `consent.dpdpAccepted`, `acceptedAt`, `policyVersion` on the user doc
    - _Requirements: 10.3_
  - [x] 5.5 Implement onboarding selections (level, goal, native language)
    - `OnboardingController` + screens for English level, goal (Speaking/Job/Both), and Native_Language (Hindi/Tamil/Telugu/Bengali/Marathi)
    - Persist a profile draft via `OnboardingRepository`
    - _Requirements: 2.1, 2.2, 2.3_
  - [x] 5.6 Implement the adaptive placement engine and UI
    - `PlacementEngine` band ladder (A1–C1) that steps up on correct/down on wrong within bounds; `settleIndex` for final level
    - `PlacementController` driving `generatePlacementQuestion`; placement screen rendering questions
    - Store `placementLevel`; mark profile `onboarded` and route to home when level+goal+language+placement are set
    - _Requirements: 2.4, 2.5, 2.6_
  - [x] 5.7 Write onboarding and placement property tests
    - **Property 3: Placement difficulty steps within bounds** — Validates Requirements 2.4
    - **Property 4: Placement always assigns a valid CEFR level** — Validates Requirements 2.5
    - **Property 5: Onboarding completion transition** — Validates Requirements 2.6
    - Widget tests for onboarding step screens
    - _Requirements: 2.4, 2.5, 2.6_

- [x] 6. Navigation shell and home learning path
  - [x] 6.1 Implement the bottom navigation shell
    - `shell` scaffold with Home, AI, Account destinations plus a Premium placeholder screen
    - Wire destinations to screens via go_router nested routes
    - _Requirements: 12.1, 12.2, 12.3_
  - [x] 6.2 Write navigation widget/property tests
    - **Property 24: Navigation maps destinations to screens** — Validates Requirements 12.2
    - Widget test: Premium destination renders the placeholder
    - _Requirements: 12.2, 12.3_
  - [x] 6.3 Implement learning-path domain and repository
    - Add `Section`, `Week`, `Step`, `StepState`, `StepProgress` domain types
    - `PathRepository` reads authored path from `content/**` and per-user `pathProgress`; computes locked/available/completed state (first step available; a step available iff preceding completed)
    - _Requirements: 3.1, 3.2, 3.3, 3.4_
  - [x] 6.4 Implement path rendering UI
    - `PathController` + path screen rendering each step as a circle in locked/available/completed state; prevent starting locked steps
    - On step completion, mark completed and unlock the next step
    - _Requirements: 3.2, 3.3, 3.4_
  - [x] 6.5 Write path unlock property test
    - **Property 6: Path unlock invariant** — Validates Requirements 3.2, 3.3, 3.4
    - _Requirements: 3.2, 3.3, 3.4_
  - [x] 6.6 Implement step detail with AI personalization + skeleton fallback
    - Step detail screen combines authored skeleton with `personalizeLesson` output; skeleton always rendered, AI content strictly additive; on no/failed personalization show skeleton only
    - _Requirements: 3.5, 3.6_
  - [x] 6.7 Write step-content property test
    - **Property 7: Skeleton content is always present regardless of AI personalization** — Validates Requirements 3.5, 3.6
    - _Requirements: 3.5, 3.6_
  - [x] 6.8 Implement the streak flame indicator on home
    - Display the streak flame; increment on the first qualifying activity of a calendar day (wired to Progress in task 9)
    - _Requirements: 3.7_

- [x] 7. AI Teacher chat
  - [x] 7.1 Implement chat domain and repository
    - Add `ChatMessage`, `GrammarFeedback`, `Report` domain types
    - `ChatRepository` calling the streaming `chatWithTeacher` client wrapper; map `status` (ok/limit_reached/refusal/error) to domain results
    - _Requirements: 4.1, 4.6_
  - [x] 7.2 Implement the streaming chat UI
    - `ChatController` consuming the token stream; render message bubbles as tokens arrive (time-to-first-token target)
    - _Requirements: 4.1, 4.4_
  - [x] 7.3 Implement the Grammar_Feedback card
    - Render `mistakeSpan.text` in red and `correctedSentence` in green (omit red styling when no mistake), show `tip`, and show `translation.text` in the learner's native language
    - _Requirements: 4.2, 4.3_
  - [x] 7.4 Write feedback rendering property tests
    - **Property 8: Grammar feedback rendering completeness** — Validates Requirements 4.2, 4.3
    - _Requirements: 4.2, 4.3_
  - [x] 7.5 Implement report-a-wrong-correction
    - Add a report control on each Grammar_Feedback item; persist to `reports/{reportId}` with full context snapshot and confirm receipt
    - _Requirements: 5.3, 5.4_
  - [x] 7.6 Write report property tests
    - **Property 10: Every feedback item exposes a report control** — Validates Requirements 5.3
    - **Property 11: Reports preserve context (round-trip)** — Validates Requirements 5.4
    - _Requirements: 5.3, 5.4_
  - [x] 7.7 Implement network-required and free-tier limit handling in chat
    - When offline, inform the learner chat requires a network connection and do not queue silently
    - On `limit_reached`, show a clear limit-reached message
    - _Requirements: 4.5, 4.6, 8.4_
  - [x] 7.8 Write chat handling widget tests
    - Offline message shown; limit-reached message shown
    - _Requirements: 4.5, 4.6_

- [x] 8. Checkpoint - core learning flows
  - Ensure all tests pass, ask the user if questions arise.

- [x] 9. Daily quizzes and spaced repetition
  - [x] 9.1 Implement quiz domain and repository
    - Add `Question`, `Answer`, `ReviewItem`, `SpacedRepetition` domain types and `INTERVALS_DAYS = [1,3,7,16,35]`
    - `QuizRepository` loads `quizItems` and due `reviewQueue` items; `ReviewQueueDataSource` for upsert/read
    - _Requirements: 6.1, 6.3, 6.4_
  - [x] 9.2 Implement quiz UI and scoring
    - `QuizController` + quiz screen for fill-in-the-blank and choose-the-right-word questions; results view shows correct and wrong counts
    - _Requirements: 6.1, 6.2_
  - [x] 9.3 Write quiz scoring property tests
    - **Property 12: Quiz answer counts are consistent** — Validates Requirements 6.2
    - _Requirements: 6.2_
  - [x] 9.4 Implement the review queue with the Leitner interval ladder
    - On wrong answer, add item to `reviewQueue` at `intervalIndex 0`; surface only due items at quiz start; on correct review answer advance to a strictly longer interval (clamped), on wrong reset to shortest
    - _Requirements: 6.3, 6.4, 6.5_
  - [x] 9.5 Write spaced-repetition property tests
    - **Property 13: Every wrong answer enters the review queue** — Validates Requirements 6.3
    - **Property 14: Only due review items are presented** — Validates Requirements 6.4
    - **Property 15: Correct review answers lengthen the interval** — Validates Requirements 6.5
    - _Requirements: 6.3, 6.4, 6.5_
  - [x] 9.6 Implement quiz network-required handling
    - When offline, inform the learner that quizzes require a network connection
    - _Requirements: 6.6, 8.4_

- [x] 10. Progress and rewards
  - [x] 10.1 Implement progress domain and streak computation
    - Add `Streak`, `Badge`, `WeeklySummary` domain types
    - Transactional streak update: same-day no-op, consecutive-day increment, gap reset; maintain `longestStreak = max(longest, current)`
    - _Requirements: 7.1, 7.5, 3.7_
  - [x] 10.2 Implement daily goal tracker and progress UI
    - `ProgressController` + screen showing current/longest streak and a Day 1–15 (and beyond) daily goal tracker
    - Update streak, goal tracker, and weekly metrics on qualifying activity
    - _Requirements: 7.1, 7.2, 7.5_
  - [x] 10.3 Implement badge awarding against config thresholds
    - Award Bronze/Silver/Gold on crossing configured milestones; record `badges` on `progress/main`
    - _Requirements: 7.3_
  - [x] 10.4 Implement the weekly summary view
    - Render `weeklySummaries/{isoWeek}` (time spent, words learned, mistakes fixed) with a live current-week fallback from `dailyActivity`
    - _Requirements: 7.4_
  - [x] 10.5 Write progress/reward property tests
    - **Property 16: Longest streak dominates current streak** — Validates Requirements 7.1
    - **Property 19: Current streak equals the current consecutive-day run** — Validates Requirements 3.7, 7.5
    - **Property 17: Badge award matches milestone thresholds** — Validates Requirements 7.3
    - _Requirements: 3.7, 7.1, 7.3, 7.5_

- [x] 11. Offline caching and sync
  - [x] 11.1 Implement the authored-content offline cache
    - `ContentCacheDataSource` caching authored step skeletons keyed by `contentVersion`; serve cached steps for offline read/practice on mobile
    - _Requirements: 8.1_
  - [x] 11.2 Implement offline progress writes and last-write-wins sync
    - Ensure `pathProgress`, `progress/main`, and quiz results queue via Firestore offline persistence and replay on reconnect; carry `updatedAt`; use transactional read-modify-write for increments
    - _Requirements: 8.2_
  - [x] 11.3 Implement cross-device restore
    - On sign-in, read `users/{uid}/**` to rehydrate profile and progress on the new device
    - _Requirements: 8.3_
  - [x] 11.4 Write offline-sync property test
    - **Property 20: Offline progress writes survive sync** (last-write-wins by timestamp) — Validates Requirements 8.2
    - _Requirements: 8.2, 8.3_

- [x] 12. Cross-cutting hardening
  - [x] 12.1 Implement performance optimizations
    - Deferred/lazy provider initialization, cached auth session for instant routing, cached authored content so the path renders without a network round-trip (app-open < 3s)
    - Ensure chat streaming renders first tokens promptly (< 2s time-to-first-token); paginate chat history; minimize main-thread work for low-end devices
    - _Requirements: 9.1, 9.2, 9.3_
  - [x] 12.2 Implement consistent error/empty/loading states
    - Map `AppException`s to shared error/empty views with retry where safe; branch on AI `status` without inspecting free-form text; fail fast on offline via the connectivity stream
    - _Requirements: 4.5, 6.6_
  - [x] 12.3 Write hardening tests and benchmarks
    - Widget tests for error/empty/offline views; app-open and time-to-first-token benchmarks; offline read of cached content
    - _Requirements: 9.1, 9.2, 9.3_

- [x] 13. Final checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional test/polish sub-tasks and can be skipped for a faster MVP; every core-path task is required.
- Each task references the specific requirement clauses it satisfies for traceability.
- Property-based tests (Properties 1–24) are placed next to the features they validate so correctness issues surface early; each references its property number and the requirement clause it checks.
- Checkpoints (tasks 4, 8, 13) provide incremental validation points across the backend, core learning flows, and the full build.
- The AI_Proxy is built before client AI features so the streaming/limit/moderation contract is stable when the chat and step-detail UIs consume it.

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1"] },
    { "id": 1, "tasks": ["1.2", "1.3", "3.1"] },
    { "id": 2, "tasks": ["1.4", "1.5", "3.2", "3.3"] },
    { "id": 3, "tasks": ["1.6", "1.7", "2.1", "3.4"] },
    { "id": 4, "tasks": ["2.2", "3.6", "3.7", "3.8", "3.9", "3.10"] },
    { "id": 5, "tasks": ["2.3", "3.5", "3.11", "5.1"] },
    { "id": 6, "tasks": ["5.2", "5.4", "5.5", "6.1"] },
    { "id": 7, "tasks": ["5.3", "5.6", "6.2", "6.3"] },
    { "id": 8, "tasks": ["5.7", "6.4", "6.6", "7.1"] },
    { "id": 9, "tasks": ["6.5", "6.7", "6.8", "7.2", "7.5"] },
    { "id": 10, "tasks": ["7.3", "7.7", "9.1"] },
    { "id": 11, "tasks": ["7.4", "7.6", "7.8", "9.2", "9.4"] },
    { "id": 12, "tasks": ["9.3", "9.5", "9.6", "10.1"] },
    { "id": 13, "tasks": ["10.2", "10.3", "10.4", "11.1"] },
    { "id": 14, "tasks": ["10.5", "11.2", "11.3"] },
    { "id": 15, "tasks": ["11.4", "12.1", "12.2"] },
    { "id": 16, "tasks": ["12.3"] }
  ]
}
```
