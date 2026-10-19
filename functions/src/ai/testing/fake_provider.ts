/**
 * In-memory fake {@link AiProvider} for tests.
 *
 * Produces deterministic outputs and supports injectable streams so tests can
 * exercise the proxy contract (moderation, persistence, streaming, usage
 * gates) without a real AI provider. Also records received requests for
 * assertions. This is the substitute used to verify provider substitutability
 * (Property 22 / Req 11.2).
 */
import { AiProvider, AiRequest, AiResult } from "../types";

/** Configuration for {@link FakeAiProvider}. All fields are optional. */
export interface FakeAiProviderOptions {
  /** Provider id; defaults to "fake". */
  id?: string;
  /**
   * Deterministic single-shot text. A string is returned verbatim; a function
   * derives text from the request. Defaults to a stable encoding of the
   * request kind + payload.
   */
  text?: string | ((req: AiRequest) => string);
  /**
   * Optional structured output. A function derives it from the request. When
   * omitted, no `structured` field is set.
   */
  structured?: object | ((req: AiRequest) => object | undefined);
  /**
   * Injectable stream tokens. An array is replayed for every request; a
   * function derives per-request tokens. When omitted, the deterministic text
   * is streamed as a single token.
   */
  stream?: string[] | ((req: AiRequest) => string[]);
}

/** Stable default text derived deterministically from the request. */
function defaultText(req: AiRequest): string {
  return `fake:${req.kind}:${JSON.stringify(req.payload)}`;
}

export class FakeAiProvider implements AiProvider {
  public readonly id: string;

  /** Requests observed by this provider, in call order. */
  public readonly requests: AiRequest[] = [];

  private readonly options: FakeAiProviderOptions;

  constructor(options: FakeAiProviderOptions = {}) {
    this.options = options;
    this.id = options.id ?? "fake";
  }

  private resolveText(req: AiRequest): string {
    const { text } = this.options;
    if (typeof text === "function") {
      return text(req);
    }
    if (typeof text === "string") {
      return text;
    }
    return defaultText(req);
  }

  private resolveStructured(req: AiRequest): object | undefined {
    const { structured } = this.options;
    if (typeof structured === "function") {
      return structured(req);
    }
    return structured;
  }

  private resolveStreamTokens(req: AiRequest): string[] {
    const { stream } = this.options;
    if (typeof stream === "function") {
      return stream(req);
    }
    if (Array.isArray(stream)) {
      return stream;
    }
    return [this.resolveText(req)];
  }

  async generate(req: AiRequest): Promise<AiResult> {
    this.requests.push(req);
    const result: AiResult = { text: this.resolveText(req) };
    const structured = this.resolveStructured(req);
    if (structured) {
      result.structured = structured;
    }
    return result;
  }

  async *generateStream(req: AiRequest): AsyncIterable<AiResult> {
    this.requests.push(req);
    for (const token of this.resolveStreamTokens(req)) {
      yield { text: token };
    }
  }
}
