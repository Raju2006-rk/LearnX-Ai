import { AiRequest } from "./types";
import {
  GEMINI_PROVIDER_ID,
  GeminiProvider,
  GenerativeModelClient,
  GenerativeModelResponse,
} from "./gemini_provider";
import { providerRegistry } from "./provider";

/** Builds a representative request; overrides merge onto a valid default. */
function makeRequest(overrides: Partial<AiRequest> = {}): AiRequest {
  return {
    kind: "chat",
    uid: "user-1",
    nativeLanguage: "hi",
    cefrLevel: "A2",
    payload: { text: "hello" },
    responseSchema: {},
    ...overrides,
  };
}

/** A stub model client with configurable single-shot and stream behavior. */
function makeClient(
  response: GenerativeModelResponse,
  tokens: string[] = [],
): GenerativeModelClient {
  return {
    async generateContent(): Promise<GenerativeModelResponse> {
      return response;
    },
    async *generateContentStream(): AsyncIterable<string> {
      for (const token of tokens) {
        yield token;
      }
    },
  };
}

describe("GeminiProvider", () => {
  it("registers itself under the gemini id at module load", () => {
    expect(providerRegistry[GEMINI_PROVIDER_ID]).toBeInstanceOf(GeminiProvider);
    expect(providerRegistry[GEMINI_PROVIDER_ID].id).toBe(GEMINI_PROVIDER_ID);
  });

  it("normalizes single-shot text into an AiResult", async () => {
    const provider = new GeminiProvider(makeClient({ text: "hi there" }));
    const result = await provider.generate(makeRequest());
    expect(result.text).toBe("hi there");
    expect(result.structured).toBeUndefined();
  });

  it("passes through structured output when the client provides it", async () => {
    const structured = { hasMistake: false };
    const provider = new GeminiProvider(makeClient({ text: "{}", structured }));
    const result = await provider.generate(
      makeRequest({ responseSchema: { type: "object" } }),
    );
    expect(result.structured).toEqual(structured);
  });

  it("parses JSON text into structured when a response schema is requested", async () => {
    const provider = new GeminiProvider(
      makeClient({ text: '{"correctedSentence":"I am fine"}' }),
    );
    const result = await provider.generate(
      makeRequest({ responseSchema: { type: "object" } }),
    );
    expect(result.structured).toEqual({ correctedSentence: "I am fine" });
  });

  it("does not fabricate structured output when no schema is requested", async () => {
    const provider = new GeminiProvider(makeClient({ text: '{"a":1}' }));
    const result = await provider.generate(makeRequest({ responseSchema: {} }));
    expect(result.structured).toBeUndefined();
    expect(result.text).toBe('{"a":1}');
  });

  it("normalizes streamed tokens into a sequence of AiResults", async () => {
    const provider = new GeminiProvider(
      makeClient({ text: "" }, ["Hel", "lo", " world"]),
    );
    const chunks: string[] = [];
    for await (const part of provider.generateStream(makeRequest())) {
      expect(part.text).toBeDefined();
      chunks.push(part.text as string);
    }
    expect(chunks).toEqual(["Hel", "lo", " world"]);
  });

  it("lazily builds its client from the factory only when first used", async () => {
    let built = 0;
    const provider = new GeminiProvider(() => {
      built += 1;
      return makeClient({ text: "lazy" });
    });
    expect(built).toBe(0);
    await provider.generate(makeRequest());
    await provider.generate(makeRequest());
    expect(built).toBe(1);
  });
});
