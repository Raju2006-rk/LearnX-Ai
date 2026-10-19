# LearnX Firestore security-rules tests

Emulator-based tests for the root `firestore.rules`, built with
[`@firebase/rules-unit-testing`](https://firebase.google.com/docs/rules/unit-tests)
and Jest.

## What is covered (task 2.3)

- **Per-user isolation** — uid A cannot read or write uid B's `users/{uid}/**` tree.
- **Server-only collections** — clients cannot write `usage` or `reports`; owners can read their own `usage`/`reports`; other users cannot.
- **Profile enum validation** — invalid `nativeLanguage` / `goal` / `englishLevel` / `placementLevel` are rejected, valid values accepted. `badges` shape (the `badge.tier` note) is pinned at the rules level.
- **Property 2** — native language accepted only from `{hi, ta, te, bn, mr}` (Req 2.3).
- **Property 21** — feature-data writes are blocked until `consent.dpdpAccepted == true` (Req 10.3).

## Prerequisites

- Node.js 18+
- **A Java runtime (JDK 11+)** — the Firestore emulator is a Java process. Without `java` on `PATH` the emulator (and therefore these tests) cannot run.
- `firebase-tools` (for `test:emulator`): `npm i -g firebase-tools`

## Install

```
cd firestore-tests
npm install
```

## Run

Let the Firebase CLI start/stop the emulator around the test run (uses ports in the repo `firebase.json`):

```
npm run test:emulator
```

Or, with a Firestore emulator already running:

```
# PowerShell
$env:FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080"; npm test
```

```
# bash
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm test
```
