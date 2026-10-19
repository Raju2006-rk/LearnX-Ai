import {
  GeneratePlacementQuestionResult,
  InvalidPlacementStateError,
  PLACEMENT_BANDS,
  PlacementAnswerKey,
  PlacementAnswerKeyStore,
  PlacementDeps,
  PlacementSessionState,
  generatePlacementQuestionCore,
  isPlacementBand,
  parseProviderQuestion,
} from "./placement";
import { MeteredAiDeps, MeteredAiResponse } from "../ai/metered";
import { ModerationOutcome, SAFE_INPUT_REFUSAL, SAFE_OUTPUT_REFUSAL } from "../ai/moderation";
import { AccountTier, TierLimits, UsageKind } from "../ai/usage";
import { FakeAiProvider } from "../ai/testing/fake_provider";
import { AiProvider, CefrLevel } from "../ai/types";

/** In-memory {@link PlacementAnswerKeyStore} for tests. */
class InMemoryStore implements PlacementAnswerKeyStore {
  public readonly saved: PlacementAnswerKey[] = [];
  private readonly byId = new Map<string, PlacementAnswerKey>();

  async saveAnswerKey(uid: string, key: PlacementAnswerKey): Promise<void> {
    this.saved.push(key);
    this.byId.set(`${uid}:${key.questionId}`, key);
  }

  async getAnswerKey(uid: string, questionId: string): Promise<PlacementAnswerKey | null> {
    return this.byId.get(`${uid}:${questionId}`) ?? null;
  }
}

/**
 * Builds injected {@link MeteredAiDeps} over an in-memory usage store, recording
 * the ordered call log so tests can assert the gate order and that the provider
 * is never invoked on the limit-reached / refusal paths.
 */
function makeMeteredDeps(overrides?: {
  tier?: AccountTier;
  limits?: Partial<TierLimits>;
  initialUsage?: Partial<Record<UsageKind, number>>;
  inputSafe?: boolean;
  outputSafe?: boolean;
  provider?: AiProvider;
}) {
  const tier: AccountTier = overrides?.tier ?? "free";
  const limits: TierLimits = {
    chat: overrides?.limits?.chat ?? 5,
    lessonPersonalization: overrides?.limits?.lessonPersonalization ?? 5,
    placementQuestion: overrides?.limits?.placementQuestion ?? 5,
  };
  const usage: Record<UsageKind, number> = {
    chat: overrides?.initialUsage?.chat ?? 0,
    lessonPersonalization: overrides?.initialUsage?.lessonPersonalization ?? 0,
    placementQuestion: overrides?.initialUsage?.placementQuestion ?? 0,
  };
  const provider = overrides?.provider ?? defaultQuestionProvider();
  const calls: string[] = [];

  const deps: MeteredAiDeps = {
    async getUserTier() {
      calls.push("getUserTier");
      return tier;
    },
    async getLimits() {
      calls.push("getLimits");
      return limits;
    },
    async getTodayUsage(_uid: string, kind: UsageKind) {
      calls.push("getTodayUsage");
      return usage[kind];
    },
    async incrementUsage(_uid: string, kind: UsageKind) {
      calls.push("incrementUsage");
      usage[kind] += 1;
    },
    resolveProvider() {
      calls.push("resolveProvider");
      return provider;
    },
    async moderate(content: string, direction: "input" | "output"): Promise<ModerationOutcome> {
      calls.push(`moderate:${direction}`);
      const safe =
        direction === "input" ? overrides?.inputSafe ?? true : overrides?.outputSafe ?? true;
      return safe
        ? { safe: true, content }
        : {
            safe: false,
            safeMessage: direction === "input" ? SAFE_INPUT_REFUSAL : SAFE_OUTPUT_REFUSAL,
            categories: ["fake"],
          };
    },
  };

  return { deps, usage, calls, provider };
}

/** A fake provider that returns a deterministic, schema-valid question. */
function defaultQuestionProvider(correctIndex = 1): FakeAiProvider {
  return new FakeAiProvider({
    structured: (req) => ({
      prompt: `Choose the correct word (${(req.payload as { band: string }).band}).`,
      options: ["go", "goes", "gone"],
      correctIndex,
    }),
  });
}

/** Wires the placement deps around a metered harness with a sequential id gen. */
function makePlacementDeps(
  meteredDeps: MeteredAiDeps,
  store: PlacementAnswerKeyStore,
): { deps: PlacementDeps; ids: string[] } {
  let n = 0;
  const ids: string[] = [];
  const deps: PlacementDeps = {
    store,
    generateId() {
      const id = `q-${++n}`;
      ids.push(id);
      return id;
    },
    meteredDeps,
  };
  return { deps, ids };
}

const AUTH = { uid: "user-1" };
const STATE: PlacementSessionState = { band: "B1", priorAnswers: [] };

function expectOk<T>(res: MeteredAiResponse<T>): T {
  expect(res.status).toBe("ok");
  if (res.status !== "ok") {
    throw new Error("expected ok");
  }
  return res.result;
}

describe("isPlacementBand", () => {
  it("accepts every CEFR band and rejects anything else", () => {
    for (const band of PLACEMENT_BANDS) {
      expect(isPlacementBand(band)).toBe(true);
    }
    expect(isPlacementBand("D1")).toBe(false);
    expect(isPlacementBand("")).toBe(false);
    expect(isPlacementBand(3)).toBe(false);
    expect(isPlacementBand(undefined)).toBe(false);
  });
});

describe("parseProviderQuestion", () => {
  it("returns the validated question when the structured output conforms", () => {
    const parsed = parseProviderQuestion({
      structured: { prompt: "Pick one", options: ["a", "b"], correctIndex: 0 },
    });
    expect(parsed).toEqual({ prompt: "Pick one", options: ["a", "b"], correctIndex: 0 });
  });

  it("throws when structured output is missing", () => {
    expect(() => parseProviderQuestion({ text: "not json" })).toThrow(/no structured question/i);
  });

  it("throws when there are too few options", () => {
    expect(() =>
      parseProviderQuestion({ structured: { prompt: "p", options: ["only"], correctIndex: 0 } }),
    ).toThrow(/options/i);
  });

  it("throws when correctIndex is out of range", () => {
    expect(() =>
      parseProviderQuestion({ structured: { prompt: "p", options: ["a", "b"], correctIndex: 5 } }),
    ).toThrow(/correctIndex/i);
  });

  it("throws when the prompt is empty", () => {
    expect(() =>
      parseProviderQuestion({ structured: { prompt: "   ", options: ["a", "b"], correctIndex: 0 } }),
    ).toThrow(/prompt/i);
  });
});

describe("generatePlacementQuestionCore", () => {
  it("returns a client question at the requested band WITHOUT the answer key", async () => {
    const { deps: meteredDeps } = makeMeteredDeps();
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    const res = await generatePlacementQuestionCore(AUTH, { band: "B2", priorAnswers: [] }, deps);
    const result = expectOk<GeneratePlacementQuestionResult>(res);

    expect(result.question.band).toBe("B2");
    expect(result.question.prompt).toContain("B2");
    expect(result.question.options).toEqual(["go", "goes", "gone"]);
    // The client payload must not carry the correct answer in any form.
    expect(JSON.stringify(result.question)).not.toContain("correctIndex");
    expect((result.question as unknown as Record<string, unknown>).correctIndex).toBeUndefined();
  });

  it("persists the answer key server-side, keyed by the issued question id", async () => {
    const { deps: meteredDeps } = makeMeteredDeps({ provider: defaultQuestionProvider(2) });
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    const res = await generatePlacementQuestionCore(AUTH, STATE, deps);
    const result = expectOk<GeneratePlacementQuestionResult>(res);

    expect(store.saved).toHaveLength(1);
    expect(store.saved[0]).toEqual({
      questionId: result.question.questionId,
      band: "B1",
      correctIndex: 2,
    });
  });

  it("grades prior answers against stored keys, exposing correctness only", async () => {
    const { deps: meteredDeps } = makeMeteredDeps({ provider: defaultQuestionProvider(1) });
    const store = new InMemoryStore();
    await store.saveAnswerKey(AUTH.uid, { questionId: "prev-1", band: "A2", correctIndex: 1 });
    await store.saveAnswerKey(AUTH.uid, { questionId: "prev-2", band: "A2", correctIndex: 0 });
    const { deps } = makePlacementDeps(meteredDeps, store);

    const state: PlacementSessionState = {
      band: "B1",
      priorAnswers: [
        { questionId: "prev-1", selectedIndex: 1 }, // correct
        { questionId: "prev-2", selectedIndex: 2 }, // wrong
        { questionId: "unknown", selectedIndex: 0 }, // unknown → incorrect
      ],
    };

    const result = expectOk<GeneratePlacementQuestionResult>(
      await generatePlacementQuestionCore(AUTH, state, deps),
    );

    expect(result.gradedAnswers).toEqual([
      { questionId: "prev-1", correct: true },
      { questionId: "prev-2", correct: false },
      { questionId: "unknown", correct: false },
    ]);
  });

  it("meters through the placementQuestion counter on success", async () => {
    const { deps: meteredDeps, usage, calls } = makeMeteredDeps();
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    await generatePlacementQuestionCore(AUTH, STATE, deps);

    expect(usage.placementQuestion).toBe(1);
    expect(calls).toEqual([
      "getUserTier",
      "getLimits",
      "getTodayUsage",
      "moderate:input",
      "resolveProvider",
      "moderate:output",
      "incrementUsage",
    ]);
  });

  it("returns limit_reached without generating or storing a question", async () => {
    const { deps: meteredDeps, usage, calls } = makeMeteredDeps({
      limits: { placementQuestion: 2 },
      initialUsage: { placementQuestion: 2 },
    });
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    const res = await generatePlacementQuestionCore(AUTH, STATE, deps);

    expect(res).toEqual({ status: "limit_reached", limit: 2 });
    expect(store.saved).toHaveLength(0);
    expect(usage.placementQuestion).toBe(2);
    expect(calls).not.toContain("resolveProvider");
  });

  it("refuses when the generated question fails output moderation, leaving the counter untouched", async () => {
    const { deps: meteredDeps, usage } = makeMeteredDeps({ outputSafe: false });
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    const res = await generatePlacementQuestionCore(AUTH, STATE, deps);

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_OUTPUT_REFUSAL });
    expect(usage.placementQuestion).toBe(0);
  });

  it("rejects an unknown difficulty band before touching the provider", async () => {
    const { deps: meteredDeps, calls } = makeMeteredDeps();
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    await expect(
      generatePlacementQuestionCore(
        AUTH,
        { band: "Z9" as unknown as CefrLevel, priorAnswers: [] },
        deps,
      ),
    ).rejects.toBeInstanceOf(InvalidPlacementStateError);
    expect(calls).toEqual([]);
  });

  it("forwards the requested band to the provider request", async () => {
    const provider = defaultQuestionProvider();
    const { deps: meteredDeps } = makeMeteredDeps({ provider });
    const store = new InMemoryStore();
    const { deps } = makePlacementDeps(meteredDeps, store);

    await generatePlacementQuestionCore(AUTH, { band: "C1", priorAnswers: [] }, deps);

    expect(provider.requests).toHaveLength(1);
    expect(provider.requests[0].kind).toBe("placementQuestion");
    expect(provider.requests[0].cefrLevel).toBe("C1");
    expect((provider.requests[0].payload as { band: string }).band).toBe("C1");
  });
});
