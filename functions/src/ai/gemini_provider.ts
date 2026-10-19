/**
 * Default {@link AiProvider} implementation backed by Google Gemini via
 * Firebase AI Logic / Vertex AI.
 *
 * The provider depends on a small {@link GenerativeModelClient} seam rather
 * than the Vertex AI SDK directly. This keeps the proxy contract testable
 * (tests inject a fake client) while the production path lazily constructs a
 * real Vertex AI adapter on first use. Either way, the provider normalizes the
 * underlying model output to {@link AiResult} so downstream code (moderation,
 * persistence, client contract) stays provider-agnostic. (Req 11.2)
 */
import { AiProvider, AiRequest, AiResult, JsonSchema } from "./types";
import { registerProvider } from "./provider";

/** Stable id of the default provider. Mirrors {@link DEFAULT_PROVIDER_ID}. */
export const GEMINI_PROVIDER_ID = "gemini-1.5";

/** A single-shot response from the underlying generative model. */
export interface GenerativeModelResponse {
  /** Free-form text produced by the model. */
  text: string;
  /** Parsed structured output when the model was asked for JSON. */
  structured?: object;
}

/**
 * Minimal seam over a generative model. The Vertex AI SDK is adapted to this
 * shape by {@link createDefaultModelClient}; tests provide their own
 * implementation. Kept intentionally narrow so providers stay substitutable.
 */
export interface GenerativeModelClient {
  /** Single-shot generation. */
  generateContent(req: AiRequest): Promise<GenerativeModelResponse>;
  /** Streaming generation yielding incremental text tokens. */
  generateContentStream(req: AiRequest): AsyncIterable<string>;
}

/** A factory that lazily produces a {@link GenerativeModelClient}. */
export type ModelClientFactory = () => GenerativeModelClient;

/**
 * Returns true when the request asks for structured (JSON) output, i.e. its
 * `responseSchema` carries any schema keys.
 */
function wantsStructured(schema: JsonSchema): boolean {
  return schema != null && Object.keys(schema).length > 0;
}

/**
 * Best-effort JSON parse used to normalize a text response into a `structured`
 * result when the model returned JSON text but no parsed object. Returns
 * `undefined` when the text is not valid JSON.
 */
function tryParseStructured(text: string): object | undefined {
  const trimmed = text.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) {
    return undefined;
  }
  try {
    const parsed = JSON.parse(trimmed);
    return typeof parsed === "object" && parsed !== null
      ? (parsed as object)
      : undefined;
  } catch {
    return undefined;
  }
}

export class GeminiProvider implements AiProvider {
  public readonly id: string = GEMINI_PROVIDER_ID;

  /** Cached client instance; created on first use via {@link factory}. */
  private client: GenerativeModelClient | undefined;
  private readonly factory: ModelClientFactory;

  /**
   * @param client Optional pre-built client (used by tests) or a factory. When
   *   omitted, a real Vertex AI adapter is constructed lazily on first call.
   */
  constructor(client?: GenerativeModelClient | ModelClientFactory) {
    if (typeof client === "function") {
      this.factory = client as ModelClientFactory;
    } else if (client) {
      this.client = client;
      this.factory = () => client;
    } else {
      this.factory = createDefaultModelClient;
    }
  }

  private getClient(): GenerativeModelClient {
    if (!this.client) {
      this.client = this.factory();
    }
    return this.client;
  }

  async generate(req: AiRequest): Promise<AiResult> {
    const response = await this.getClient().generateContent(req);
    const result: AiResult = { text: response.text };
    if (response.structured) {
      result.structured = response.structured;
    } else if (wantsStructured(req.responseSchema)) {
      const parsed = tryParseStructured(response.text);
      if (parsed) {
        result.structured = parsed;
      }
    }
    return result;
  }

  async *generateStream(req: AiRequest): AsyncIterable<AiResult> {
    for await (const token of this.getClient().generateContentStream(req)) {
      yield { text: token };
    }
  }
}

/**
 * Constructs the production Vertex AI adapter. The Vertex AI SDK is loaded via
 * `require` at call time (never at module load) so the provider can be
 * registered and unit-tested without the SDK present or credentials
 * configured. Throws a clear error if the SDK is unavailable.
 */
export function createDefaultModelClient(): GenerativeModelClient {
  const project = process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT;
  const location = process.env.VERTEX_LOCATION ?? "us-central1";
  const modelId = process.env.GEMINI_MODEL ?? "gemini-1.5-flash";

  let sdk: { VertexAI: new (opts: object) => unknown };
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
    sdk = require("@google-cloud/vertexai");
  } catch {
    throw new Error(
      "GeminiProvider requires the '@google-cloud/vertexai' package. " +
        "Install it in functions/ or inject a GenerativeModelClient for tests.",
    );
  }

  const vertex = new sdk.VertexAI({ project, location }) as {
    getGenerativeModel: (opts: object) => VertexGenerativeModel;
  };

  const buildModel = (req: AiRequest): VertexGenerativeModel =>
    vertex.getGenerativeModel({
      model: modelId,
      generationConfig: wantsStructured(req.responseSchema)
        ? { responseMimeType: "application/json" }
        : {},
    });

  const buildRequest = (req: AiRequest): VertexRequest => ({
    contents: [{ role: "user", parts: [{ text: JSON.stringify(req.payload) }] }],
  });

  const extractText = (resp: VertexResponse): string =>
    resp.response?.candidates?.[0]?.content?.parts
      ?.map((p) => p.text ?? "")
      .join("") ?? "";

  return {
    async generateContent(req: AiRequest): Promise<GenerativeModelResponse> {
      const model = buildModel(req);
      const resp = await model.generateContent(buildRequest(req));
      const text = extractText(resp);
      return { text };
    },
    async *generateContentStream(req: AiRequest): AsyncIterable<string> {
      const model = buildModel(req);
      const streaming = await model.generateContentStream(buildRequest(req));
      for await (const chunk of streaming.stream) {
        const token = chunk.candidates?.[0]?.content?.parts
          ?.map((p) => p.text ?? "")
          .join("");
        if (token) {
          yield token;
        }
      }
    },
  };
}

/** Local structural types mirroring the Vertex AI SDK surface we consume. */
interface VertexPart {
  text?: string;
}
interface VertexContent {
  parts?: VertexPart[];
}
interface VertexCandidate {
  content?: VertexContent;
}
interface VertexResponse {
  response?: { candidates?: VertexCandidate[] };
}
interface VertexRequest {
  contents: { role: string; parts: VertexPart[] }[];
}
interface VertexGenerativeModel {
  generateContent(req: VertexRequest): Promise<VertexResponse>;
  generateContentStream(
    req: VertexRequest,
  ): Promise<{ stream: AsyncIterable<{ candidates?: VertexCandidate[] }> }>;
}

// Register the default provider at module load so config-driven resolution can
// find it. Construction is cheap; the real SDK client is built lazily on use.
registerProvider(new GeminiProvider());
