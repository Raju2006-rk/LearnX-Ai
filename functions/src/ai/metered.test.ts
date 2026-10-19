import {
  AuthRequiredError,
  HandlerResult,
  MeteredAiContext,
  MeteredAiDeps,
  MeteredHandler,
  meteredAi,
} from "./metered";
import { ModerationOutcome, SAFE_INPUT_REFUSAL, SAFE_OUTPUT_REFUSAL } from "./moderation";
import { AccountTier, TierLimits, UsageKind } from "./usage";
import { FakeAiProvider } from "./testing/fake_provider";
import { AiProvider } from "./types";

/**
 * Builds a fully-injected {@link MeteredAiDeps} over an in-memory usage store,
 * recording an ordered call log so tests can assert the gate order and, in
 * particular, that the provider is never called and the counter never mutated
 * on the limit-reached and refusal paths.
 */
function makeHarness(overrides?: {
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
  const provider = overrides?.provider ?? new FakeAiProvider();
  const calls: string[] = [];
  let providerResolveCount = 0;

  const deps: MeteredAiDeps = {
    async getUserTier() {
      calls.push("getUserTier");
      return tier;
    },
    async getLimits(t: AccountTier) {
      calls.push("getLimits");
      expect(t).toBe(tier);
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
      providerResolveCount += 1;
      return provider;
    },
    async moderate(content: string, direction: "input" | "output"): Promise<ModerationOutcome> {
      calls.push(`moderate:${direction}`);
      const safe = direction === "input" ? overrides?.inputSafe ?? true : overrides?.outputSafe ?? true;
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

  return { deps, usage, calls, provider, getProviderResolveCount: () => providerResolveCount };
}

const authedContext: MeteredAiContext = {
  auth: { uid: "user-1" },
  input: "How do I use the present perfect?",
  nativeLanguage: "hi",
  cefrLevel: "B1",
};

/** Handler that records whether it ran and returns a deterministic result. */
function makeHandler(): { handler: MeteredHandler<string>; ran: () => boolean } {
  let ran = false;
  const handler: MeteredHandler<string> = async (provider) => {
    ran = true;
    const out = await provider.generate({
      kind: "chat",
      uid: "user-1",
      nativeLanguage: "hi",
      cefrLevel: "B1",
      payload: { text: "hi" },
      responseSchema: {},
    });
    const result: HandlerResult<string> = {
      result: out.text ?? "",
      outputText: out.text ?? "",
    };
    return result;
  };
  return { handler, ran: () => ran };
}

describe("meteredAi gate order", () => {
  it("requires authentication before any other step", async () => {
    const { deps, calls } = makeHarness();
    const { handler, ran } = makeHandler();
    const unauth: MeteredAiContext = { auth: null, input: "hi" };

    await expect(meteredAi(unauth, "chat", handler, deps)).rejects.toBeInstanceOf(
      AuthRequiredError,
    );
    expect(ran()).toBe(false);
    expect(calls).toEqual([]);
  });

  it("returns ok, increments the counter, and runs the full gate order on success", async () => {
    const { deps, usage, calls, getProviderResolveCount } = makeHarness();
    const { handler, ran } = makeHandler();

    const res = await meteredAi(authedContext, "chat", handler, deps);

    expect(res).toEqual({ status: "ok", result: expect.any(String) });
    expect(ran()).toBe(true);
    expect(getProviderResolveCount()).toBe(1);
    expect(usage.chat).toBe(1);
    // Exact gate order: auth is implicit (no dep call); then tier → limits →
    // usage → input moderation → provider → output moderation → increment.
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

  it("returns limit_reached WITHOUT calling the provider or changing the counter", async () => {
    const { deps, usage, calls, getProviderResolveCount } = makeHarness({
      limits: { chat: 3 },
      initialUsage: { chat: 3 },
    });
    const { handler, ran } = makeHandler();

    const res = await meteredAi(authedContext, "chat", handler, deps);

    expect(res).toEqual({ status: "limit_reached", limit: 3 });
    expect(ran()).toBe(false);
    expect(getProviderResolveCount()).toBe(0);
    expect(usage.chat).toBe(3); // unchanged
    expect(calls).not.toContain("resolveProvider");
    expect(calls).not.toContain("moderate:input");
    expect(calls).not.toContain("incrementUsage");
  });

  it("allows the request when usage is exactly one below the limit", async () => {
    const { deps, usage } = makeHarness({ limits: { chat: 3 }, initialUsage: { chat: 2 } });
    const { handler } = makeHandler();

    const res = await meteredAi(authedContext, "chat", handler, deps);

    expect(res.status).toBe("ok");
    expect(usage.chat).toBe(3);
  });

  it("refuses on unsafe input WITHOUT calling the provider or changing the counter", async () => {
    const { deps, usage, calls, getProviderResolveCount } = makeHarness({ inputSafe: false });
    const { handler, ran } = makeHandler();

    const res = await meteredAi(authedContext, "chat", handler, deps);

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_INPUT_REFUSAL });
    expect(ran()).toBe(false);
    expect(getProviderResolveCount()).toBe(0);
    expect(usage.chat).toBe(0);
    expect(calls).not.toContain("incrementUsage");
  });

  it("refuses on unsafe output AFTER calling the provider but WITHOUT incrementing", async () => {
    const { deps, usage, calls } = makeHarness({ outputSafe: false });
    const { handler, ran } = makeHandler();

    const res = await meteredAi(authedContext, "chat", handler, deps);

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_OUTPUT_REFUSAL });
    expect(ran()).toBe(true); // provider WAS called
    expect(usage.chat).toBe(0); // but the counter is NOT incremented
    expect(calls).toContain("resolveProvider");
    expect(calls).not.toContain("incrementUsage");
  });

  it("meters each kind against its own counter and limit", async () => {
    const { deps, usage } = makeHarness({ limits: { lessonPersonalization: 2 } });
    const { handler } = makeHandler();

    await meteredAi(authedContext, "lessonPersonalization", handler, deps);
    expect(usage.lessonPersonalization).toBe(1);
    expect(usage.chat).toBe(0);
  });

  it("passes the resolved provider to the handler", async () => {
    const provider = new FakeAiProvider({ id: "fake-metered", text: "resolved-output" });
    const { deps } = makeHarness({ provider });
    const handler: MeteredHandler<string> = async (p) => {
      const out = await p.generate({
        kind: "chat",
        uid: "user-1",
        nativeLanguage: "hi",
        cefrLevel: "B1",
        payload: {},
        responseSchema: {},
      });
      return { result: out.text ?? "", outputText: out.text ?? "" };
    };

    const res = await meteredAi(authedContext, "chat", handler, deps);

    expect(res).toEqual({ status: "ok", result: "resolved-output" });
    expect(provider.requests).toHaveLength(1);
  });
});
