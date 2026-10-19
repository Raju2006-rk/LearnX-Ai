/**
 * `Grammar_Feedback` structured-output contract and validation for the
 * AI_Proxy chat flow.
 *
 * The provider is prompted with the JSON schema exported here as
 * {@link GRAMMAR_FEEDBACK_SCHEMA}; before a chat reply's structured feedback is
 * returned to the client (and persisted), it is validated against that schema
 * by {@link validateGrammarFeedback}. This mirrors the "Grammar_Feedback
 * Response Schema" section of the LearnX design. (Req 4.2, 4.3)
 *
 * Rendering contract enforced here so the client can render safely:
 * - The client renders `mistakeSpan.text` in red and `correctedSentence` in
 *   green, shows `tip`, and shows `translation.text` in the learner's native
 *   language.
 * - When `hasMistake` is false, `mistakeSpan` is omitted and no red styling is
 *   applied. This validator normalizes that case by dropping any `mistakeSpan`
 *   present when `hasMistake` is false, matching the design's "omit" wording.
 */
import { JsonSchema, NativeLanguage } from "./types";

/** Native languages a translation may target (matches {@link NativeLanguage}). */
export const TRANSLATION_LANGUAGES: readonly NativeLanguage[] = [
  "hi",
  "ta",
  "te",
  "bn",
  "mr",
];

/**
 * Highlighted span of the learner's original sentence that contains a mistake.
 * Present only when {@link GrammarFeedback.hasMistake} is true.
 */
export interface MistakeSpan {
  /** Inclusive start index of the mistake within the original text. */
  start: number;
  /** Exclusive end index of the mistake within the original text. */
  end: number;
  /** The exact substring flagged as a mistake (rendered in red). */
  text: string;
}

/** Native-language translation of the feedback shown to the learner. */
export interface FeedbackTranslation {
  /** Target native language of the translation. */
  language: NativeLanguage;
  /** Translated feedback text. */
  text: string;
}

/**
 * Normalized, schema-conformant grammar feedback for a single chat turn.
 * `mistakeSpan` is present if and only if `hasMistake` is true.
 */
export interface GrammarFeedback {
  /** Whether the learner's sentence contained a grammar mistake. */
  hasMistake: boolean;
  /** The flagged span; present only when `hasMistake` is true. */
  mistakeSpan?: MistakeSpan;
  /** The corrected sentence (rendered in green). */
  correctedSentence: string;
  /** A short teaching tip explaining the correction. */
  tip: string;
  /** Native-language translation of the feedback. */
  translation: FeedbackTranslation;
}

/**
 * The structured-output JSON schema the provider is prompted with, copied from
 * the design's "Grammar_Feedback Response Schema". `mistakeSpan` is optional at
 * the schema level (only the four core fields are required); the conditional
 * "present iff hasMistake" invariant is enforced by
 * {@link validateGrammarFeedback}.
 */
export const GRAMMAR_FEEDBACK_SCHEMA: JsonSchema = {
  type: "object",
  properties: {
    hasMistake: { type: "boolean" },
    mistakeSpan: {
      type: "object",
      properties: {
        start: { type: "integer" },
        end: { type: "integer" },
        text: { type: "string" },
      },
      required: ["start", "end", "text"],
    },
    correctedSentence: { type: "string" },
    tip: { type: "string" },
    translation: {
      type: "object",
      properties: {
        language: { type: "string", enum: [...TRANSLATION_LANGUAGES] },
        text: { type: "string" },
      },
      required: ["language", "text"],
    },
  },
  required: ["hasMistake", "correctedSentence", "tip", "translation"],
};

/**
 * Raised when a provider's structured output does not conform to the
 * `Grammar_Feedback` schema. The message names the offending field/reason so
 * misbehaving providers fail loudly rather than sending malformed feedback to
 * the client.
 */
export class GrammarFeedbackValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GrammarFeedbackValidationError";
  }
}

/** Type guard: a non-null, non-array plain object. */
function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Type guard: a finite integer number. */
function isInteger(value: unknown): value is number {
  return typeof value === "number" && Number.isInteger(value);
}

function validateMistakeSpan(value: unknown): MistakeSpan {
  if (!isRecord(value)) {
    throw new GrammarFeedbackValidationError(
      "mistakeSpan must be an object when present.",
    );
  }
  if (!isInteger(value.start)) {
    throw new GrammarFeedbackValidationError(
      "mistakeSpan.start must be an integer.",
    );
  }
  if (!isInteger(value.end)) {
    throw new GrammarFeedbackValidationError(
      "mistakeSpan.end must be an integer.",
    );
  }
  if (typeof value.text !== "string") {
    throw new GrammarFeedbackValidationError(
      "mistakeSpan.text must be a string.",
    );
  }
  return { start: value.start, end: value.end, text: value.text };
}

function validateTranslation(value: unknown): FeedbackTranslation {
  if (!isRecord(value)) {
    throw new GrammarFeedbackValidationError("translation must be an object.");
  }
  if (typeof value.language !== "string") {
    throw new GrammarFeedbackValidationError(
      "translation.language must be a string.",
    );
  }
  if (!TRANSLATION_LANGUAGES.includes(value.language as NativeLanguage)) {
    throw new GrammarFeedbackValidationError(
      `translation.language must be one of ${TRANSLATION_LANGUAGES.join(", ")}.`,
    );
  }
  if (typeof value.text !== "string") {
    throw new GrammarFeedbackValidationError(
      "translation.text must be a string.",
    );
  }
  return { language: value.language as NativeLanguage, text: value.text };
}

/**
 * Validates and normalizes provider structured output against the
 * `Grammar_Feedback` schema, returning a typed {@link GrammarFeedback}.
 *
 * Enforces the four required fields (`hasMistake`, `correctedSentence`, `tip`,
 * `translation`) and the conditional `mistakeSpan` invariant:
 * - When `hasMistake` is true, `mistakeSpan` is required and validated.
 * - When `hasMistake` is false, `mistakeSpan` is omitted from the result
 *   (dropped if the provider included it), per the design's "omit" wording.
 *
 * Throws {@link GrammarFeedbackValidationError} on any invalid input.
 * (Req 4.2, 4.3)
 */
export function validateGrammarFeedback(input: unknown): GrammarFeedback {
  if (!isRecord(input)) {
    throw new GrammarFeedbackValidationError(
      "Grammar_Feedback must be a JSON object.",
    );
  }

  if (typeof input.hasMistake !== "boolean") {
    throw new GrammarFeedbackValidationError("hasMistake must be a boolean.");
  }
  if (typeof input.correctedSentence !== "string") {
    throw new GrammarFeedbackValidationError(
      "correctedSentence is required and must be a string.",
    );
  }
  if (typeof input.tip !== "string") {
    throw new GrammarFeedbackValidationError(
      "tip is required and must be a string.",
    );
  }

  const translation = validateTranslation(input.translation);

  const result: GrammarFeedback = {
    hasMistake: input.hasMistake,
    correctedSentence: input.correctedSentence,
    tip: input.tip,
    translation,
  };

  if (input.hasMistake) {
    // A flagged mistake must carry the span the client renders in red.
    if (input.mistakeSpan === undefined || input.mistakeSpan === null) {
      throw new GrammarFeedbackValidationError(
        "mistakeSpan is required when hasMistake is true.",
      );
    }
    result.mistakeSpan = validateMistakeSpan(input.mistakeSpan);
  }
  // When hasMistake is false, any provided mistakeSpan is intentionally
  // omitted from the normalized result (no red styling is applied).

  return result;
}
