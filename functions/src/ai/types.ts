/**
 * Server-side provider abstraction contract for the AI_Proxy.
 *
 * These types mirror the "Provider Abstraction Interface" section of the
 * LearnX design. Every provider normalizes its output to {@link AiResult} so
 * downstream code (moderation, persistence, client contract) stays
 * provider-agnostic. (Req 11.1, 11.2)
 */

/** Learner native languages supported by LearnX (ISO 639-1 subset). */
export type NativeLanguage = "hi" | "ta" | "te" | "bn" | "mr";

/** CEFR proficiency levels used across placement and personalization. */
export type CefrLevel = "A1" | "A2" | "B1" | "B2" | "C1";

/** Kind of generation being requested from the provider. */
export type AiRequestKind = "chat" | "lessonPersonalization" | "placementQuestion";

/**
 * A minimal JSON Schema description used as the structured-output contract for
 * a request. Kept intentionally loose; individual functions validate results
 * against their concrete schema.
 */
export type JsonSchema = Record<string, unknown>;

/** A single, provider-agnostic generation request. */
export interface AiRequest {
  kind: AiRequestKind;
  uid: string;
  nativeLanguage: NativeLanguage;
  cefrLevel: CefrLevel;
  /** Kind-specific payload (e.g. chat text, step id, session state). */
  payload: object;
  /** Structured-output contract the provider is expected to conform to. */
  responseSchema: JsonSchema;
}

/**
 * Normalized generation result. A provider may return free-form `text`,
 * schema-conformant `structured` JSON, and/or an incremental token `stream`.
 */
export interface AiResult {
  /** Free-form reply text (chat). */
  text?: string;
  /** Schema-conformant JSON (feedback, questions). */
  structured?: object;
  /** Incremental token stream for streaming responses. */
  stream?: AsyncIterable<string>;
}

/**
 * Provider abstraction. The default implementation is Google Gemini via
 * Firebase AI Logic / Vertex AI; swapping providers is a server-only change
 * with no client impact. (Req 11.2)
 */
export interface AiProvider {
  /** Stable provider identifier, e.g. "gemini-1.5". */
  readonly id: string;
  /** Single-shot generation returning a normalized result. */
  generate(req: AiRequest): Promise<AiResult>;
  /** Streaming generation yielding incremental normalized results. */
  generateStream(req: AiRequest): AsyncIterable<AiResult>;
}
