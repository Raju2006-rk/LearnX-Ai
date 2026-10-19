import {
  LessonProfile,
  PersonalizeLessonContext,
  PersonalizeLessonDeps,
  personalizeLessonCore,
} from "./personalize_lesson";
import { MeteredAiDeps } from "../ai/metered";
import {
  ModerationOutcome,
  SAFE_INPUT_REFUSAL,
  SAFE_OUTPUT_REFUSAL,
} from "../ai/moderation";
import { AccountTier, TierLimits, UsageKind } from "../ai/usage";
import { FakeAiProvider } from "../ai/testing/fake_provider";
import { AiProvider } from "../ai/types";

const PROFILE: LessonProfile = { cefrLevel: "B1", goal: "job", nativeLanguage: "hi" };

const STRUCTURED = {
  examples: ["I scheduled the meeting for Monday.", "Could you send me the report?"],
  practice: ["Write an email requesting leave.", "Introduce yourself to a new colleague."],
};

/** Builds injectable metered-AI seams over an in-memory usage store. */
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
  const provider =
    overrides?.provider ?? new FakeAiProvider({ structured: () => STRUCTURED });

  const meteredDeps: MeteredAiDeps = {
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
      usage[kind] += 1;
    },
    resolveProvider() {
      return provider;
    },
    async moderate(content: string, direction: "input" | "output"): Promise<ModerationOutcome> {
      const safe =
        direction === "input" ? overrides?.inputSafe ?? true : overrides?.outputSafe ?? true;
      if (safe) {
        return { safe: true, content };
      }
      return {
        safe: false,
        safeMessage: direction === "input" ? SAFE_INPUT_REFUSAL : SAFE_OUTPUT_REFUSAL,
        categories: ["fake"],
      };
    },
  };

  return { meteredDeps, usage, provider };
}

/** Builds full deps with valid profile/step by default. */
function makeDeps(overrides?: {
  profile?: LessonProfile | null;
  step?: { title: string; objectives: string[] } | null;
  metered?: ReturnType<typeof makeMeteredDeps>;
}): { deps: PersonalizeLessonDeps; usage: Record<UsageKind, number> } {
  const metered = overrides?.metered ?? makeMeteredDeps();
  const profile = overrides?.profile === undefined ? PROFILE : overrides.profile;
  const step =
    overrides?.step === undefined
      ? { title: "Emails at work", objectives: ["Write a professional email"] }
      : overrides.step;

  const deps: PersonalizeLessonDeps = {
    async getProfile() {
      return profile;
    },
    async getStep() {
      return step;
    },
    meteredDeps: metered.meteredDeps,
  };
  return { deps, usage: metered.usage };
}

const context: PersonalizeLessonContext = {
  auth: { uid: "user-1" },
  data: { stepId: "step-1" },
};

describe("personalizeLessonCore", () => {
  it("returns CEFR/goal-tagged examples and practice on the happy path", async () => {
    const { deps, usage } = makeDeps();

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toEqual({
      cefrLevel: "B1",
      goal: "job",
      examples: STRUCTURED.examples,
      practice: STRUCTURED.practice,
    });
    // Usage counter is incremented on success.
    expect(usage.lessonPersonalization).toBe(1);
  });

  it("passes lessonPersonalization request context to the provider", async () => {
    const provider = new FakeAiProvider({ structured: () => STRUCTURED });
    const { deps } = makeDeps({ metered: makeMeteredDeps({ provider }) });

    await personalizeLessonCore(context, deps);

    expect(provider.requests).toHaveLength(1);
    const req = provider.requests[0];
    expect(req.kind).toBe("lessonPersonalization");
    expect(req.cefrLevel).toBe("B1");
    expect(req.nativeLanguage).toBe("hi");
    expect(req.payload).toMatchObject({ stepId: "step-1", goal: "job" });
  });

  it("falls back to null when the request is unauthenticated", async () => {
    const { deps } = makeDeps();
    const res = await personalizeLessonCore({ auth: null, data: { stepId: "step-1" } }, deps);
    expect(res.personalization).toBeNull();
  });

  it("falls back to null when stepId is missing", async () => {
    const { deps } = makeDeps();
    const res = await personalizeLessonCore({ auth: { uid: "user-1" }, data: {} }, deps);
    expect(res.personalization).toBeNull();
  });

  it("falls back to null when the profile is missing", async () => {
    const { deps } = makeDeps({ profile: null });
    const res = await personalizeLessonCore(context, deps);
    expect(res.personalization).toBeNull();
  });

  it("falls back to null when the step is not found", async () => {
    const { deps } = makeDeps({ step: null });
    const res = await personalizeLessonCore(context, deps);
    expect(res.personalization).toBeNull();
  });

  it("falls back to null (no error) when the usage limit is reached", async () => {
    const metered = makeMeteredDeps({
      limits: { lessonPersonalization: 3 },
      initialUsage: { lessonPersonalization: 3 },
    });
    const { deps, usage } = makeDeps({ metered });

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toBeNull();
    // Provider not called; counter unchanged.
    expect(metered.provider).toBeInstanceOf(FakeAiProvider);
    expect((metered.provider as FakeAiProvider).requests).toHaveLength(0);
    expect(usage.lessonPersonalization).toBe(3);
  });

  it("falls back to null on an input moderation refusal", async () => {
    const metered = makeMeteredDeps({ inputSafe: false });
    const { deps } = makeDeps({ metered });

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toBeNull();
    expect((metered.provider as FakeAiProvider).requests).toHaveLength(0);
  });

  it("falls back to null on an output moderation refusal", async () => {
    const metered = makeMeteredDeps({ outputSafe: false });
    const { deps, usage } = makeDeps({ metered });

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toBeNull();
    // Provider was called but the counter is not incremented on refusal.
    expect(usage.lessonPersonalization).toBe(0);
  });

  it("falls back to null when the provider throws", async () => {
    const throwing: AiProvider = {
      id: "throwing",
      async generate() {
        throw new Error("provider exploded");
      },
      // eslint-disable-next-line require-yield
      async *generateStream() {
        throw new Error("provider exploded");
      },
    };
    const { deps } = makeDeps({ metered: makeMeteredDeps({ provider: throwing }) });

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toBeNull();
  });

  it("falls back to null when the provider output fails schema validation", async () => {
    const badProvider = new FakeAiProvider({ structured: () => ({ examples: [], practice: [] }) });
    const { deps } = makeDeps({ metered: makeMeteredDeps({ provider: badProvider }) });

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toBeNull();
  });

  it("falls back to null when the provider returns no structured output", async () => {
    const noStructured = new FakeAiProvider({ text: "just text, no json" });
    const { deps } = makeDeps({ metered: makeMeteredDeps({ provider: noStructured }) });

    const res = await personalizeLessonCore(context, deps);

    expect(res.personalization).toBeNull();
  });
});
