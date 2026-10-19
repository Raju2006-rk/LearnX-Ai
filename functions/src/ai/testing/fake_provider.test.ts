import { AiRequest, AiResult } from "../types";
import { FakeAiProvider } from "./fake_provider";
import { registerProvider, resolveProvider } from "../provider";
import { config } from "../../config";

function makeRequest(overrides: Partial<AiRequest> = {}): AiRequest {
  return {
    kind: "chat",
    uid: "user-1",
    nativeLanguage: "ta",
    cefrLevel: "B1",
    payload: { text: "hello" },
    responseSchema: {},
    ...overrides,
  };
}

describe("FakeAiProvider", () => {
  it("produces deterministic default text for identical requests", async () => {
    const provider = new FakeAiProvider();
    const a = await provider.generate(makeRequest());
    const b = await provider.generate(makeRequest());
    expect(a.text).toBe(b.text);
    expect(a.text).toBe('fake:chat:{"text":"hello"}');
  });

  it("returns configured static text and structured output", async () => {
    const structured = { hasMistake: true };
    const provider = new FakeAiProvider({ text: "fixed", structured });
    const result = await provider.generate(makeRequest());
    expect(result.text).toBe("fixed");
    expect(result.structured).toEqual(structured);
  });

  it("derives text and structured from the request via functions", async () => {
    const provider = new FakeAiProvider({
      text: (req) => `reply-to:${(req.payload as { text: string }).text}`,
      structured: (req) => ({ lang: req.nativeLanguage }),
    });
    const result = await provider.generate(makeRequest());
    expect(result.text).toBe("reply-to:hello");
    expect(result.structured).toEqual({ lang: "ta" });
  });

  it("replays injected stream tokens in order", async () => {
    const provider = new FakeAiProvider({ stream: ["a", "b", "c"] });
    const tokens: string[] = [];
    for await (const part of provider.generateStream(makeRequest())) {
      tokens.push((part as AiResult).text as string);
    }
    expect(tokens).toEqual(["a", "b", "c"]);
  });

  it("streams the deterministic text as one token when no stream is injected", async () => {
    const provider = new FakeAiProvider();
    const tokens: string[] = [];
    for await (const part of provider.generateStream(makeRequest())) {
      tokens.push(part.text as string);
    }
    expect(tokens).toEqual(['fake:chat:{"text":"hello"}']);
  });

  it("records received requests for assertions", async () => {
    const provider = new FakeAiProvider();
    await provider.generate(makeRequest({ uid: "a" }));
    await provider.generate(makeRequest({ uid: "b" }));
    expect(provider.requests.map((r) => r.uid)).toEqual(["a", "b"]);
  });

  it("is substitutable via the provider registry (Property 22)", async () => {
    const originalId = config.aiProviderId;
    const fake = new FakeAiProvider({ id: "gemini-1.5", text: "swapped" });
    registerProvider(fake);
    config.aiProviderId = "gemini-1.5";
    try {
      const resolved = resolveProvider();
      const result = await resolved.generate(makeRequest());
      expect(result.text).toBe("swapped");
    } finally {
      config.aiProviderId = originalId;
    }
  });
});
