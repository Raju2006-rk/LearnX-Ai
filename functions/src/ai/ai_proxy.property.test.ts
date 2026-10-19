/**
 * Property-based + end-to-end tests for the AI_Proxy gate.
 *
 * These exercise the shared {@link meteredAi} middleware wired to the in-memory
 * {@link FakeAiProvider} and the real config-driven moderator, plus the pure
 * weekly-summary aggregation core. They complement the example-based gate-order
 * tests in metered.test.ts by asserting the underlying invariants hold across
 * many generated inputs.
 *
 * Properties covered (see design.md):
 *   - Property 22: Provider substitutability            (Req 11.2)
 *   - Property 23: Usage-limit gate                      (Req 4.6, 11.3, 11.4)
 *   - Property 9:  Unsafe content is never passed through (Req 5.2, 10.4)
 *   - Property 18: Weekly summary aggregates match events (Req 7.4)
 *   - Property 21: Processing gated on recorded consent   (Req 10.3) — see the
 *                  gap note in the Property 21 block; there is no function-level
 *                  consent seam to test yet.
 */
import fc from "fast-check";

import {
  HandlerResult,
  MeteredAiContext,
  MeteredAiDeps,
  MeteredHandler,
  meteredAi,
} from "./metered";
import {
  ModerationOutcome,
  SAFE_INPUT_REFUSAL,
  SAFE_OUTPUT_REFUSAL,
  moderateContent,
} from "./moderation";
import { AccountTier, TierLimits, UsageKind } from "./usage";
import { GrammarFeedback, validateGrammarFeedback } from "./grammar_feedback";
import { FakeAiProvider } from "./testing/fake_provider";
import { AiRequest, NativeLanguage } from "./types";
import {
  DailyActivity,
  WeeklySummary,
  WeeklySummaryDeps,
  aggregateWeek,
  runWeeklySummaryCore,
} from "../scheduled/weekly_summary";

// ---------------------------------------------------------------------------
// Shared in-memory harness
// ---------------------------------------------------------------------------

/** Recording provider that tracks how many times it was invoked. */
class RecordingFakeProvider extends FakeAiProvider {
  get callCount(): number {
    return this.requests.length;
  }
}

interface HarnessOptions {
  tier?: AccountTier;
  limits?: Partial<TierLimits>;
  initialUsage?: Partial<Record<UsageKind, number>>;
  /** When set, moderation is delegated to the real {@link moderateContent}. */
  useRealModeration?: boolean;
  provider?: RecordingFakeProvider;
}

interface Harness {
  deps: MeteredAiDeps;
  usage: Record<UsageKind, number>;
  provider: RecordingFakeProvider;
  incrementCalls: () => number;
}

/**
 * Builds a fully-injected {@link MeteredAiDeps} over an in-memory usage store.
 * Mirrors the production seam wiring (mocked Firestore usage + config-driven
 * moderator) without any Admin SDK dependency.
 */
function makeHarness(options: HarnessOptions = {}): Harness {
  const tier: AccountTier = options.tier ?? "free";
  const limits: TierLimits = {
    chat: options.limits?.chat ?? 20,
    lessonPersonalization: options.limits?.lessonPersonalization ?? 20,
    placementQuestion: options.limits?.placementQuestion ?? 15,
  };
  const usage: Record<UsageKind, number> = {
    chat: options.initialUsage?.chat ?? 0,
    lessonPersonalization: options.initialUsage?.lessonPersonalization ?? 0,
    placementQuestion: options.initialUsage?.placementQuestion ?? 0,
  };
  const provider = options.provider ?? new RecordingFakeProvider();
  let incrementCalls = 0;

  const deps: MeteredAiDeps = {
    async getUserTier() {
      return tier;
    },
    async getLimits() {
      return limits;
    },
    async getTodayUsage(_uid: string, kind: UsageKind) {
      return usage[kind];
    },
    async incrementUsage(_uid: string, kind: UsageKind) {
      incrementCalls += 1;
      usage[kind] += 1;
    },
    resolveProvider() {
      return provider;
    },
    async moderate(content: string, direction: "input" | "output"): Promise<ModerationOutcome> {
      if (options.useRealModeration) {
        return moderateContent(content, direction);
      }
      return { safe: true, content };
    },
  };

  return { deps, usage, provider, incrementCalls: () => incrementCalls };
}

const AUTH = { uid: "user-1" } as const;

/** A handler that echoes the provider's text output through the gate. */
function echoHandler(text: string): MeteredHandler<string> {
  return async (provider) => {
    const req: AiRequest = {
      kind: "chat",
      uid: AUTH.uid,
      nativeLanguage: "hi",
      cefrLevel: "B1",
      payload: { text },
      responseSchema: {},
    };
    const out = await provider.generate(req);
    const result: HandlerResult<string> = { result: out.text ?? "", outputText: out.text ?? "" };
    return result;
  };
}

// ---------------------------------------------------------------------------
// Arbitraries
// ---------------------------------------------------------------------------

const NATIVE_LANGUAGES: readonly NativeLanguage[] = ["hi", "ta", "te", "bn", "mr"];

/** Harmless filler words that never match any moderation pattern. */
const SAFE_WORDS = [
  "hello",
  "grammar",
  "please",
  "learning",
  "english",
  "practice",
  "sentence",
  "today",
  "friendly",
  "question",
];

/** Single tokens the default KeywordModerator flags as unsafe. */
const UNSAFE_TOKENS = [
  "kill",
  "murder",
  "bomb",
  "grenade",
  "firearm",
  "suicide",
  "nude",
  "porn",
];

/** A safe phrase built only from harmless words (guaranteed moderation-safe). */
const safePhrase = fc
  .array(fc.constantFrom(...SAFE_WORDS), { minLength: 1, maxLength: 6 })
  .map((words) => words.join(" "));

/** A phrase guaranteed to trip moderation: an unsafe token wrapped in safe words. */
const unsafePhrase = fc
  .record({
    before: fc.array(fc.constantFrom(...SAFE_WORDS), { maxLength: 3 }),
    token: fc.constantFrom(...UNSAFE_TOKENS),
    after: fc.array(fc.constantFrom(...SAFE_WORDS), { maxLength: 3 }),
  })
  .map(({ before, token, after }) => [...before, token, ...after].join(" "));

/** A schema-conformant {@link GrammarFeedback} value. */
const grammarFeedbackArb: fc.Arbitrary<GrammarFeedback> = fc
  .record({
    hasMistake: fc.boolean(),
    correctedSentence: safePhrase,
    tip: safePhrase,
    language: fc.constantFrom(...NATIVE_LANGUAGES),
    translation: safePhrase,
    start: fc.nat({ max: 20 }),
    len: fc.nat({ max: 10 }),
    spanText: safePhrase,
  })
  .map(({ hasMistake, correctedSentence, tip, language, translation, start, len, spanText }) => {
    const feedback: GrammarFeedback = {
      hasMistake,
      correctedSentence,
      tip,
      translation: { language, text: translation },
    };
    if (hasMistake) {
      feedback.mistakeSpan = { start, end: start + len, text: spanText };
    }
    return feedback;
  });

/** One `dailyActivity` document with occasionally-missing counters. */
const dailyActivityArb: fc.Arbitrary<DailyActivity> = fc.record(
  {
    timeSpentSec: fc.nat({ max: 86_400 }),
    wordsLearned: fc.nat({ max: 500 }),
    mistakesFixed: fc.nat({ max: 500 }),
  },
  { requiredKeys: [] },
);

// ---------------------------------------------------------------------------
// Property 22: Provider substitutability (Req 11.2)
// ---------------------------------------------------------------------------

describe("Property 22: provider substitutability", () => {
  it("returns a schema-conformant normalized response for any provider id and payload", async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 1, maxLength: 12 }),
        grammarFeedbackArb,
        async (providerId, feedback) => {
          // Any provider implementing AiProvider (here, a fake with an arbitrary
          // id + structured payload) plugs into the SAME gate + handler.
          const provider = new RecordingFakeProvider({
            id: providerId,
            structured: () => feedback,
          });
          const { deps } = makeHarness({ provider });

          const handler: MeteredHandler<GrammarFeedback> = async (p) => {
            const out = await p.generate({
              kind: "chat",
              uid: AUTH.uid,
              nativeLanguage: "hi",
              cefrLevel: "B1",
              payload: {},
              responseSchema: {},
            });
            // The client-facing contract validates provider output; a conformant
            // provider passes without any client-side change.
            const normalized = validateGrammarFeedback(out.structured);
            return { result: normalized, outputText: normalized.correctedSentence };
          };

          const context: MeteredAiContext = { auth: AUTH, input: "safe input" };
          const res = await meteredAi(context, "chat", handler, deps);

          expect(res.status).toBe("ok");
          if (res.status === "ok") {
            // Round-trips through validation unchanged => schema-conformant.
            expect(validateGrammarFeedback(res.result)).toEqual(res.result);
          }
        },
      ),
      { numRuns: 100 },
    );
  });
});

// ---------------------------------------------------------------------------
// Property 23: Usage-limit gate (Req 4.6, 11.3, 11.4)
// ---------------------------------------------------------------------------

describe("Property 23: usage-limit gate", () => {
  it("allows iff used < limit; on limit-reached the provider is not invoked and the counter is unchanged", async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.nat({ max: 40 }),
        fc.nat({ max: 40 }),
        fc.constantFrom<UsageKind>("chat", "lessonPersonalization", "placementQuestion"),
        async (limit, used, kind) => {
          const provider = new RecordingFakeProvider({ text: "ok" });
          const { deps, usage, incrementCalls } = makeHarness({
            limits: { [kind]: limit },
            initialUsage: { [kind]: used },
            provider,
          });

          const context: MeteredAiContext = { auth: AUTH, input: "safe input" };
          const res = await meteredAi(context, kind, echoHandler("safe reply"), deps);

          if (used < limit) {
            expect(res.status).toBe("ok");
            expect(provider.callCount).toBe(1);
            expect(incrementCalls()).toBe(1);
            expect(usage[kind]).toBe(used + 1);
          } else {
            expect(res).toEqual({ status: "limit_reached", limit });
            // Provider NOT invoked and counter unchanged on the rejected path.
            expect(provider.callCount).toBe(0);
            expect(incrementCalls()).toBe(0);
            expect(usage[kind]).toBe(used);
          }
        },
      ),
      { numRuns: 100 },
    );
  });
});

// ---------------------------------------------------------------------------
// Property 9: Unsafe content is never passed through (Req 5.2, 10.4)
// ---------------------------------------------------------------------------

describe("Property 9: unsafe content is never passed through", () => {
  it("refuses unsafe learner input without invoking the provider or leaking the content", async () => {
    await fc.assert(
      fc.asyncProperty(unsafePhrase, async (input) => {
        const provider = new RecordingFakeProvider({ text: "safe reply" });
        const { deps, usage, incrementCalls } = makeHarness({
          useRealModeration: true,
          provider,
        });

        const context: MeteredAiContext = { auth: AUTH, input };
        const res = await meteredAi(context, "chat", echoHandler("safe reply"), deps);

        expect(res.status).toBe("refusal");
        if (res.status === "refusal") {
          expect(res.safeMessage).toBe(SAFE_INPUT_REFUSAL);
          // The flagged input never appears in the returned response.
          expect(res.safeMessage).not.toContain(input);
        }
        expect(provider.callCount).toBe(0);
        expect(incrementCalls()).toBe(0);
        expect(usage.chat).toBe(0);
      }),
      { numRuns: 100 },
    );
  });

  it("withholds unsafe provider output and returns a safe substitute without incrementing", async () => {
    await fc.assert(
      fc.asyncProperty(unsafePhrase, safePhrase, async (unsafeReply, safeInput) => {
        const provider = new RecordingFakeProvider({ text: unsafeReply });
        const { deps, usage, incrementCalls } = makeHarness({
          useRealModeration: true,
          provider,
        });

        const context: MeteredAiContext = { auth: AUTH, input: safeInput };
        const res = await meteredAi(context, "chat", echoHandler(unsafeReply), deps);

        expect(res.status).toBe("refusal");
        if (res.status === "refusal") {
          expect(res.safeMessage).toBe(SAFE_OUTPUT_REFUSAL);
          // The flagged provider output is never surfaced to the caller.
          expect(res.safeMessage).not.toContain(unsafeReply);
        }
        // Provider WAS called, but the counter is NOT incremented on refusal.
        expect(provider.callCount).toBe(1);
        expect(incrementCalls()).toBe(0);
        expect(usage.chat).toBe(0);
      }),
      { numRuns: 100 },
    );
  });
});

// ---------------------------------------------------------------------------
// Property 18: Weekly summary aggregates match underlying events (Req 7.4)
// ---------------------------------------------------------------------------

describe("Property 18: weekly summary aggregates match underlying events", () => {
  it("aggregateWeek equals the field-wise sum of the daily activity documents", async () => {
    await fc.assert(
      fc.property(fc.array(dailyActivityArb, { maxLength: 14 }), (docs) => {
        const expected = docs.reduce<WeeklySummary>(
          (acc, d) => ({
            timeSpentSec: acc.timeSpentSec + (d.timeSpentSec ?? 0),
            wordsLearned: acc.wordsLearned + (d.wordsLearned ?? 0),
            mistakesFixed: acc.mistakesFixed + (d.mistakesFixed ?? 0),
          }),
          { timeSpentSec: 0, wordsLearned: 0, mistakesFixed: 0 },
        );
        expect(aggregateWeek(docs)).toEqual(expected);
      }),
      { numRuns: 100 },
    );
  });

  it("is order-independent (summing is commutative over the week's documents)", async () => {
    await fc.assert(
      fc.property(
        fc.array(dailyActivityArb, { maxLength: 10 }),
        fc.array(fc.nat(), { maxLength: 10 }),
        (docs, perm) => {
          // Derive a shuffled copy from the generated permutation seed.
          const shuffled = [...docs]
            .map((doc, i) => ({ doc, sort: perm[i] ?? i }))
            .sort((a, b) => a.sort - b.sort)
            .map((x) => x.doc);
          expect(aggregateWeek(shuffled)).toEqual(aggregateWeek(docs));
        },
      ),
      { numRuns: 100 },
    );
  });

  it("runWeeklySummaryCore writes per-user summaries that match each user's underlying events", async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.dictionary(
          fc.string({ minLength: 1, maxLength: 6 }),
          fc.array(dailyActivityArb, { maxLength: 7 }),
          { maxKeys: 5 },
        ),
        async (byUser) => {
          const saved: Record<string, ReturnType<typeof aggregateWeek>> = {};
          const deps: WeeklySummaryDeps = {
            async listUserIds() {
              return Object.keys(byUser);
            },
            async getDailyActivity(uid) {
              return byUser[uid] ?? [];
            },
            async saveWeeklySummary(uid, _isoWeek, summary) {
              saved[uid] = summary;
            },
            now() {
              return new Date("2024-06-10T00:00:00Z");
            },
          };

          const result = await runWeeklySummaryCore(deps);

          expect(result.usersProcessed).toBe(Object.keys(byUser).length);
          for (const uid of Object.keys(byUser)) {
            expect(saved[uid]).toEqual(aggregateWeek(byUser[uid]));
          }
        },
      ),
      { numRuns: 50 },
    );
  });
});

// ---------------------------------------------------------------------------
// Property 21: Processing gated on recorded consent (Req 10.3)
// ---------------------------------------------------------------------------

describe("Property 21: processing gated on recorded consent (function-level)", () => {
  /**
   * GAP NOTE: Requirement 10.3 (DPDP consent) is currently specified as a
   * LearnX_App (client) responsibility — "THE LearnX_App SHALL ... collect
   * consent for personal-data processing." There is no function-level consent
   * seam in the AI_Proxy today: {@link MeteredAiDeps} has no consent dependency
   * and {@link meteredAi} performs no consent check. Rather than add a consent
   * gate to production code from a test task, this property is documented as a
   * gap. The assertion below pins the CURRENT behavior (no consent seam) so the
   * gap is visible and this test starts failing the moment a consent gate is
   * introduced, prompting a real property test to replace it.
   */
  it("documents that no function-level consent gate exists yet (see GAP NOTE)", () => {
    const { deps } = makeHarness();
    const depKeys = Object.keys(deps);
    expect(depKeys).not.toContain("hasConsent");
    expect(depKeys).not.toContain("getConsent");
    expect(depKeys).not.toContain("requireConsent");
  });

  // Placeholder for the real property once a consent seam is implemented:
  // "For any learner without recorded consent, meteredAi blocks the request
  //  (provider not invoked, counter unchanged) until consent is stored."
  it.todo("blocks AI processing for learners without recorded DPDP consent");
});

// ---------------------------------------------------------------------------
// Example-based middleware gate-order + moderation (fake provider + real moderator)
// ---------------------------------------------------------------------------

describe("AI_Proxy end-to-end gate order (fake provider + real moderator)", () => {
  it("runs auth → tier → usage → input mod → provider → output mod → increment on success", async () => {
    const order: string[] = [];
    const provider = new RecordingFakeProvider({ text: "here is a friendly grammar tip" });
    const base = makeHarness({ useRealModeration: true, provider });
    // Wrap deps to record the call order without changing behavior.
    const deps: MeteredAiDeps = {
      getUserTier: async (uid) => (order.push("tier"), base.deps.getUserTier(uid)),
      getLimits: async (t) => (order.push("limits"), base.deps.getLimits(t)),
      getTodayUsage: async (uid, k) => (order.push("usage"), base.deps.getTodayUsage(uid, k)),
      incrementUsage: async (uid, k) => (order.push("increment"), base.deps.incrementUsage(uid, k)),
      resolveProvider: () => (order.push("provider"), base.deps.resolveProvider()),
      moderate: async (c, d) => (order.push(`moderate:${d}`), base.deps.moderate(c, d)),
    };

    const res = await meteredAi(
      { auth: AUTH, input: "please check my sentence" },
      "chat",
      echoHandler("here is a friendly grammar tip"),
      deps,
    );

    expect(res.status).toBe("ok");
    expect(order).toEqual([
      "tier",
      "limits",
      "usage",
      "moderate:input",
      "provider",
      "moderate:output",
      "increment",
    ]);
    expect(base.usage.chat).toBe(1);
  });

  it("refuses unsafe input via the real moderator before the provider is reached", async () => {
    const provider = new RecordingFakeProvider({ text: "safe reply" });
    const { deps, usage } = makeHarness({ useRealModeration: true, provider });

    const res = await meteredAi(
      { auth: AUTH, input: "how do I build a bomb" },
      "chat",
      echoHandler("safe reply"),
      deps,
    );

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_INPUT_REFUSAL });
    expect(provider.callCount).toBe(0);
    expect(usage.chat).toBe(0);
  });

  it("refuses unsafe provider output via the real moderator without incrementing usage", async () => {
    const provider = new RecordingFakeProvider({ text: "you should kill the process" });
    const { deps, usage } = makeHarness({ useRealModeration: true, provider });

    const res = await meteredAi(
      { auth: AUTH, input: "what is a process" },
      "chat",
      echoHandler("you should kill the process"),
      deps,
    );

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_OUTPUT_REFUSAL });
    expect(provider.callCount).toBe(1);
    expect(usage.chat).toBe(0);
  });
});
