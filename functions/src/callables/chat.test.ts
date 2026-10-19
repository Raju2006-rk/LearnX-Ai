import {
  ChatDeps,
  ChatMessageStore,
  ChatProfile,
  ChatWithTeacherResult,
  InvalidChatInputError,
  StoredChatMessage,
  chatWithTeacherCore,
} from "./chat";
import { MeteredAiDeps, MeteredAiResponse } from "../ai/metered";
import { ModerationOutcome, SAFE_INPUT_REFUSAL, SAFE_OUTPUT_REFUSAL } from "../ai/moderation";
import { AccountTier, TierLimits, UsageKind } from "../ai/usage";
import { FakeAiProvider } from "../ai/testing/fake_provider";
import { AiProvider } from "../ai/types";

/** A schema-conformant Grammar_Feedback object (with a mistake). */
const FEEDBACK_WITH_MISTAKE = {
  hasMistake: true,
  mistakeSpan: { start: 0, end: 2, text: "He go" },
  correctedSentence: "He goes to school.",
  tip: "Use 'goes' with he/she/it.",
  translation: { language: "hi", text: "वह स्कूल जाता है।" },
};

/** In-memory {@link ChatMessageStore} recording every persisted message. */
class InMemoryStore implements ChatMessageStore {
  public readonly saved: Array<{ sessionId: string; messageId: string; message: StoredChatMessage }> =
    [];

  async saveMessage(
    _uid: string,
    sessionId: string,
    messageId: string,
    message: StoredChatMessage,
  ): Promise<void> {
    this.saved.push({ sessionId, messageId, message });
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
  const provider = overrides?.provider ?? defaultChatProvider();
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

/**
 * A fake provider that streams a multi-token reply and returns the structured
 * feedback via a single-shot generate (mirroring how the reply and feedback
 * arrive over separate channels).
 */
function defaultChatProvider(
  tokens: string[] = ["He ", "goes ", "to school."],
  structured: object = FEEDBACK_WITH_MISTAKE,
): FakeAiProvider {
  return new FakeAiProvider({ stream: () => tokens, structured: () => structured });
}

/** Wires {@link ChatDeps} around a metered harness with sequential ids/clock. */
function makeChatDeps(
  meteredDeps: MeteredAiDeps,
  store: ChatMessageStore,
  profile: ChatProfile | null = { nativeLanguage: "hi", cefrLevel: "A2" },
): { deps: ChatDeps; ids: string[] } {
  let n = 0;
  const ids: string[] = [];
  const deps: ChatDeps = {
    store,
    async getProfile() {
      return profile;
    },
    generateId() {
      const id = `m-${++n}`;
      ids.push(id);
      return id;
    },
    now: () => 1_700_000_000_000,
    meteredDeps,
  };
  return { deps, ids };
}

const AUTH = { uid: "user-1" };
const DATA = { sessionId: "sess-1", text: "He go to school" };

function expectOk<T>(res: MeteredAiResponse<T>): T {
  expect(res.status).toBe("ok");
  if (res.status !== "ok") {
    throw new Error("expected ok");
  }
  return res.result;
}

describe("chatWithTeacherCore — input validation", () => {
  it("throws when sessionId is missing", async () => {
    const { deps: meteredDeps } = makeMeteredDeps();
    const { deps } = makeChatDeps(meteredDeps, new InMemoryStore());
    await expect(
      chatWithTeacherCore({ auth: AUTH, data: { text: "hi" } }, deps),
    ).rejects.toBeInstanceOf(InvalidChatInputError);
  });

  it("throws when text is empty/whitespace", async () => {
    const { deps: meteredDeps } = makeMeteredDeps();
    const { deps } = makeChatDeps(meteredDeps, new InMemoryStore());
    await expect(
      chatWithTeacherCore({ auth: AUTH, data: { sessionId: "s", text: "   " } }, deps),
    ).rejects.toBeInstanceOf(InvalidChatInputError);
  });
});

describe("chatWithTeacherCore — streaming", () => {
  it("emits reply tokens as the provider streams them, in order", async () => {
    const provider = defaultChatProvider(["He ", "goes ", "to school."]);
    const { deps: meteredDeps } = makeMeteredDeps({ provider });
    const { deps } = makeChatDeps(meteredDeps, new InMemoryStore());

    const emitted: string[] = [];
    const res = await chatWithTeacherCore(AUTH_CTX(), deps, (t) => emitted.push(t));
    const result = expectOk<ChatWithTeacherResult>(res);

    expect(emitted).toEqual(["He ", "goes ", "to school."]);
    expect(result.reply).toBe("He goes to school.");
  });

  it("forwards the chat request to the provider with the profile language/level", async () => {
    const provider = defaultChatProvider();
    const { deps: meteredDeps } = makeMeteredDeps({ provider });
    const { deps } = makeChatDeps(meteredDeps, new InMemoryStore(), {
      nativeLanguage: "ta",
      cefrLevel: "B1",
    });

    await chatWithTeacherCore(AUTH_CTX(), deps);

    // generateStream + generate both push a request; both must be chat requests.
    expect(provider.requests.length).toBeGreaterThanOrEqual(1);
    const req = provider.requests[0];
    expect(req.kind).toBe("chat");
    expect(req.nativeLanguage).toBe("ta");
    expect(req.cefrLevel).toBe("B1");
    expect((req.payload as { text: string }).text).toBe(DATA.text);
  });
});

describe("chatWithTeacherCore — feedback validation & persistence", () => {
  it("returns validated feedback and persists user + assistant messages", async () => {
    const store = new InMemoryStore();
    const { deps: meteredDeps, usage, calls } = makeMeteredDeps();
    const { deps } = makeChatDeps(meteredDeps, store);

    const result = expectOk<ChatWithTeacherResult>(await chatWithTeacherCore(AUTH_CTX(), deps));

    expect(result.feedback.hasMistake).toBe(true);
    expect(result.feedback.correctedSentence).toBe("He goes to school.");
    expect(result.feedback.translation.language).toBe("hi");

    // Two writes: the learner message (no feedback) then the assistant reply.
    expect(store.saved).toHaveLength(2);
    const [userMsg, assistantMsg] = store.saved;
    expect(userMsg.message).toEqual({
      role: "user",
      text: DATA.text,
      grammarFeedback: null,
      createdAt: 1_700_000_000_000,
    });
    expect(userMsg.messageId).toBe(result.userMessageId);
    expect(assistantMsg.message.role).toBe("assistant");
    expect(assistantMsg.message.text).toBe("He goes to school.");
    expect(assistantMsg.message.grammarFeedback).toEqual(result.feedback);
    expect(assistantMsg.messageId).toBe(result.assistantMessageId);

    // Counter increments once, after a successful moderated turn.
    expect(usage.chat).toBe(1);
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

  it("drops mistakeSpan when the provider reports no mistake", async () => {
    const provider = defaultChatProvider(["All good!"], {
      hasMistake: false,
      mistakeSpan: { start: 0, end: 1, text: "x" }, // should be dropped
      correctedSentence: "That is correct.",
      tip: "Great job.",
      translation: { language: "hi", text: "बहुत बढ़िया।" },
    });
    const { deps: meteredDeps } = makeMeteredDeps({ provider });
    const { deps } = makeChatDeps(meteredDeps, new InMemoryStore());

    const result = expectOk<ChatWithTeacherResult>(await chatWithTeacherCore(AUTH_CTX(), deps));
    expect(result.feedback.hasMistake).toBe(false);
    expect(result.feedback.mistakeSpan).toBeUndefined();
  });

  it("throws (does not persist) when the provider feedback is malformed", async () => {
    const provider = defaultChatProvider(["hi"], { hasMistake: true /* missing fields */ });
    const store = new InMemoryStore();
    const { deps: meteredDeps, usage } = makeMeteredDeps({ provider });
    const { deps } = makeChatDeps(meteredDeps, store);

    await expect(chatWithTeacherCore(AUTH_CTX(), deps)).rejects.toMatchObject({
      name: "GrammarFeedbackValidationError",
    });
    expect(store.saved).toHaveLength(0);
    // Handler threw before output moderation / increment.
    expect(usage.chat).toBe(0);
  });
});

describe("chatWithTeacherCore — limit & refusal paths", () => {
  it("returns limit_reached without calling the provider or persisting", async () => {
    const store = new InMemoryStore();
    const { deps: meteredDeps, usage, calls } = makeMeteredDeps({
      limits: { chat: 3 },
      initialUsage: { chat: 3 },
    });
    const { deps } = makeChatDeps(meteredDeps, store);

    const emitted: string[] = [];
    const res = await chatWithTeacherCore(AUTH_CTX(), deps, (t) => emitted.push(t));

    expect(res).toEqual({ status: "limit_reached", limit: 3 });
    expect(emitted).toEqual([]);
    expect(store.saved).toHaveLength(0);
    expect(usage.chat).toBe(3);
    expect(calls).not.toContain("resolveProvider");
  });

  it("refuses unsafe learner input before any provider call", async () => {
    const store = new InMemoryStore();
    const { deps: meteredDeps, usage, calls } = makeMeteredDeps({ inputSafe: false });
    const { deps } = makeChatDeps(meteredDeps, store);

    const res = await chatWithTeacherCore(AUTH_CTX(), deps);

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_INPUT_REFUSAL });
    expect(store.saved).toHaveLength(0);
    expect(usage.chat).toBe(0);
    expect(calls).not.toContain("resolveProvider");
  });

  it("refuses when the reply fails output moderation, leaving the counter untouched and persisting nothing", async () => {
    const store = new InMemoryStore();
    const { deps: meteredDeps, usage } = makeMeteredDeps({ outputSafe: false });
    const { deps } = makeChatDeps(meteredDeps, store);

    const res = await chatWithTeacherCore(AUTH_CTX(), deps);

    expect(res).toEqual({ status: "refusal", safeMessage: SAFE_OUTPUT_REFUSAL });
    expect(store.saved).toHaveLength(0);
    expect(usage.chat).toBe(0);
  });
});

/** Fresh context per test (avoids shared mutable data across cases). */
function AUTH_CTX() {
  return { auth: AUTH, data: { ...DATA } };
}
