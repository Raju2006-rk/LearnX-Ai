/**
 * Emulator-based security-rules tests for LearnX `firestore.rules`.
 *
 * Task 2.3 — Write security-rules emulator tests. Covers:
 *   - Per-user isolation (uid A cannot read/write uid B's tree).
 *   - Client cannot write `usage` or `reports`; can read own `usage`.
 *   - Enum validation on profile writes
 *     (nativeLanguage / goal / englishLevel; badge.tier discussed below).
 *   - Property 2  — Native language accepted only from the allowed set (Req 2.3).
 *   - Property 21 — Processing is gated on recorded consent: feature writes are
 *                   blocked until `consent.dpdpAccepted == true` (Req 10.3).
 *
 * Requirements: 2.3, 10.3, 11.3, 11.4
 *
 * Run against the Firestore emulator, e.g.:
 *   npm run test:emulator      # wraps jest in `firebase emulators:exec`
 * or, with an emulator already running:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npm test
 *
 * NOTE: the Firestore emulator requires a Java runtime. Without Java on PATH
 * these tests cannot execute locally.
 */

const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
} = require("firebase/firestore");

const PROJECT_ID = "learnx-rules-test";
const RULES_PATH = path.resolve(__dirname, "..", "firestore.rules");

// Two distinct learners used throughout to exercise per-user isolation.
const UID_A = "user-alice";
const UID_B = "user-bob";

// Allowed enum sets, mirroring firestore.rules / the design data model.
const ALLOWED_NATIVE_LANGUAGES = ["hi", "ta", "te", "bn", "mr"];
const ALLOWED_GOALS = ["speaking", "job", "both"];
const ALLOWED_CEFR = ["A1", "A2", "B1", "B2", "C1"];

// Values that must be rejected by the enum validators.
const DISALLOWED_NATIVE_LANGUAGES = ["en", "fr", "es", "HI", "hindi", "", "xx"];

/** A profile document that passes every enum validator. */
function validProfile(overrides = {}) {
  return {
    nativeLanguage: "hi",
    goal: "speaking",
    englishLevel: "A1",
    placementLevel: "A2",
    onboarded: false,
    ...overrides,
  };
}

let testEnv;

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
    },
  });
});

afterAll(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/**
 * Seed the parent user doc (rules bypassed) so consent-gated / owned-doc
 * reads have a parent to resolve. `dpdpAccepted` controls the consent gate.
 */
async function seedUser(uid, { dpdpAccepted = true } = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users", uid), {
      createdAt: Date.now(),
      accountTier: "free",
      consent: { dpdpAccepted, acceptedAt: Date.now() },
    });
  });
}

/** Seed a document with rules disabled (simulating a server/Admin-SDK write). */
async function seedDoc(pathSegments, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, ...pathSegments), data);
  });
}

function aliceDb() {
  return testEnv.authenticatedContext(UID_A).firestore();
}

function bobDb() {
  return testEnv.authenticatedContext(UID_B).firestore();
}

// ---------------------------------------------------------------------------
// Per-user isolation (Requirement 11.3, 11.4 — tamper-proofing / isolation)
// ---------------------------------------------------------------------------

describe("per-user isolation", () => {
  beforeEach(async () => {
    await seedUser(UID_A, { dpdpAccepted: true });
    await seedUser(UID_B, { dpdpAccepted: true });
    await seedDoc(["users", UID_B, "profile", "main"], validProfile());
    await seedDoc(["users", UID_B, "pathProgress", "step1"], { completed: true });
  });

  test("owner can read their own user doc", async () => {
    await assertSucceeds(getDoc(doc(aliceDb(), "users", UID_A)));
  });

  test("owner can write their own pathProgress", async () => {
    await assertSucceeds(
      setDoc(doc(aliceDb(), "users", UID_A, "pathProgress", "step1"), {
        completed: true,
      })
    );
  });

  test("uid A cannot read uid B's user doc", async () => {
    await assertFails(getDoc(doc(aliceDb(), "users", UID_B)));
  });

  test("uid A cannot read uid B's profile", async () => {
    await assertFails(getDoc(doc(aliceDb(), "users", UID_B, "profile", "main")));
  });

  test("uid A cannot read uid B's pathProgress", async () => {
    await assertFails(
      getDoc(doc(aliceDb(), "users", UID_B, "pathProgress", "step1"))
    );
  });

  test("uid A cannot write into uid B's pathProgress", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "users", UID_B, "pathProgress", "step2"), {
        completed: true,
      })
    );
  });

  test("uid A cannot write into uid B's profile", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "users", UID_B, "profile", "main"), validProfile())
    );
  });

  test("unauthenticated user cannot read any user doc", async () => {
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, "users", UID_A)));
  });
});

// ---------------------------------------------------------------------------
// Server-only collections: usage & reports (Requirements 11.3, 11.4)
// ---------------------------------------------------------------------------

describe("server-only collections (usage / reports)", () => {
  const DAY = "2024-01-01";
  const REPORT_ID = "report-1";

  beforeEach(async () => {
    await seedUser(UID_A, { dpdpAccepted: true });
    await seedUser(UID_B, { dpdpAccepted: true });
    // Server (Admin SDK) writes these; seed with rules disabled.
    await seedDoc(["users", UID_A, "usage", DAY], { chatCount: 3 });
    await seedDoc(["users", UID_A, "reports", REPORT_ID], {
      context: "snapshot",
    });
  });

  test("owner can read their own usage", async () => {
    await assertSucceeds(getDoc(doc(aliceDb(), "users", UID_A, "usage", DAY)));
  });

  test("client cannot write their own usage", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "users", UID_A, "usage", DAY), { chatCount: 0 })
    );
  });

  test("another user cannot read someone else's usage", async () => {
    await assertFails(getDoc(doc(bobDb(), "users", UID_A, "usage", DAY)));
  });

  test("owner can read their own reports", async () => {
    await assertSucceeds(
      getDoc(doc(aliceDb(), "users", UID_A, "reports", REPORT_ID))
    );
  });

  test("client cannot write reports", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "users", UID_A, "reports", "report-2"), {
        context: "tampered",
      })
    );
  });

  test("another user cannot read someone else's reports", async () => {
    await assertFails(
      getDoc(doc(bobDb(), "users", UID_A, "reports", REPORT_ID))
    );
  });
});

// ---------------------------------------------------------------------------
// Enum validation on profile writes (Requirements 2.3, 2.5)
// ---------------------------------------------------------------------------

describe("profile enum validation", () => {
  beforeEach(async () => {
    // Consent must be present so writes are rejected for enum reasons only.
    await seedUser(UID_A, { dpdpAccepted: true });
  });

  test("valid profile is accepted", async () => {
    await assertSucceeds(
      setDoc(doc(aliceDb(), "users", UID_A, "profile", "main"), validProfile())
    );
  });

  test("invalid nativeLanguage is rejected", async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), "users", UID_A, "profile", "main"),
        validProfile({ nativeLanguage: "fr" })
      )
    );
  });

  test("invalid goal is rejected", async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), "users", UID_A, "profile", "main"),
        validProfile({ goal: "leisure" })
      )
    );
  });

  test("invalid englishLevel is rejected", async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), "users", UID_A, "profile", "main"),
        validProfile({ englishLevel: "Z9" })
      )
    );
  });

  test("invalid placementLevel is rejected", async () => {
    await assertFails(
      setDoc(
        doc(aliceDb(), "users", UID_A, "profile", "main"),
        validProfile({ placementLevel: "D3" })
      )
    );
  });

  test("each allowed goal value is accepted", async () => {
    for (const goal of ALLOWED_GOALS) {
      await assertSucceeds(
        setDoc(
          doc(aliceDb(), "users", UID_A, "profile", "main"),
          validProfile({ goal })
        )
      );
    }
  });

  test("each allowed CEFR level is accepted for englishLevel", async () => {
    for (const englishLevel of ALLOWED_CEFR) {
      await assertSucceeds(
        setDoc(
          doc(aliceDb(), "users", UID_A, "profile", "main"),
          validProfile({ englishLevel })
        )
      );
    }
  });

  // badge.tier: progress/main stores `badges` as a list of maps. The Rules
  // language cannot iterate a list to enum-check each element's `tier`, so the
  // rules enforce that `badges` (when present) is a list; the concrete tier
  // enum {bronze,silver,gold} is enforced client-side (see the note at the
  // bottom of firestore.rules). These tests pin the rules-level behavior.
  describe("progress badges shape (badge.tier note)", () => {
    test("progress write with badges as a list is accepted", async () => {
      await assertSucceeds(
        setDoc(doc(aliceDb(), "users", UID_A, "progress", "main"), {
          currentStreak: 1,
          badges: [{ tier: "bronze", awardedAt: Date.now(), milestone: "d1" }],
        })
      );
    });

    test("progress write with badges as a non-list is rejected", async () => {
      await assertFails(
        setDoc(doc(aliceDb(), "users", UID_A, "progress", "main"), {
          currentStreak: 1,
          badges: "bronze",
        })
      );
    });
  });
});

// ---------------------------------------------------------------------------
// Property 2: Native language is accepted only from the allowed set (Req 2.3)
// ---------------------------------------------------------------------------

describe("Property 2: native language accepted only from the allowed set", () => {
  beforeEach(async () => {
    await seedUser(UID_A, { dpdpAccepted: true });
  });

  test("every allowed native language is accepted", async () => {
    for (const nativeLanguage of ALLOWED_NATIVE_LANGUAGES) {
      await assertSucceeds(
        setDoc(
          doc(aliceDb(), "users", UID_A, "profile", "main"),
          validProfile({ nativeLanguage })
        )
      );
    }
  });

  test("every disallowed native language is rejected", async () => {
    for (const nativeLanguage of DISALLOWED_NATIVE_LANGUAGES) {
      await assertFails(
        setDoc(
          doc(aliceDb(), "users", UID_A, "profile", "main"),
          validProfile({ nativeLanguage })
        )
      );
    }
  });
});

// ---------------------------------------------------------------------------
// Property 21: Processing is gated on recorded consent (Req 10.3)
//
// Rules-level manifestation: feature-data writes are blocked until the parent
// user doc records `consent.dpdpAccepted == true`.
// ---------------------------------------------------------------------------

describe("Property 21: processing is gated on recorded consent", () => {
  // Feature collections that the rules gate behind hasConsent(uid). Each entry
  // is [collectionPath..., docId, data] plus whether validProfile-style
  // constraints also apply (only `profile` needs enum-valid data).
  const featureWrites = [
    {
      name: "profile",
      pathFor: (uid) => ["users", uid, "profile", "main"],
      data: validProfile(),
    },
    {
      name: "pathProgress",
      pathFor: (uid) => ["users", uid, "pathProgress", "step1"],
      data: { completed: true },
    },
    {
      name: "progress",
      pathFor: (uid) => ["users", uid, "progress", "main"],
      data: { currentStreak: 1 },
    },
    {
      name: "chatSessions",
      pathFor: (uid) => ["users", uid, "chatSessions", "s1"],
      data: { startedAt: Date.now() },
    },
    {
      name: "reviewQueue",
      pathFor: (uid) => ["users", uid, "reviewQueue", "item1"],
      data: { intervalIndex: 0 },
    },
    {
      name: "quizSessions",
      pathFor: (uid) => ["users", uid, "quizSessions", "q1"],
      data: { score: 0 },
    },
  ];

  describe("without recorded consent, feature writes are blocked", () => {
    beforeEach(async () => {
      await seedUser(UID_A, { dpdpAccepted: false });
    });

    for (const { name, pathFor, data } of featureWrites) {
      test(`${name} write is blocked without consent`, async () => {
        await assertFails(setDoc(doc(aliceDb(), ...pathFor(UID_A)), data));
      });
    }
  });

  describe("with recorded consent, feature writes are allowed", () => {
    beforeEach(async () => {
      await seedUser(UID_A, { dpdpAccepted: true });
    });

    for (const { name, pathFor, data } of featureWrites) {
      test(`${name} write is allowed with consent`, async () => {
        await assertSucceeds(setDoc(doc(aliceDb(), ...pathFor(UID_A)), data));
      });
    }
  });

  test("consent gate holds even for a valid-enum profile", async () => {
    await seedUser(UID_A, { dpdpAccepted: false });
    // Data is enum-valid; the write must still fail purely on the consent gate.
    await assertFails(
      setDoc(doc(aliceDb(), "users", UID_A, "profile", "main"), validProfile())
    );
  });
});
