/**
 * `chatWithTeacher` streaming callable for the AI_Proxy.
 *
 * Input `{ sessionId, text }`. The learner's message is run through the shared
 * {@link meteredAi} gate (auth → tier → usage → input moderation → provider →
 * output moderation → increment) and the provider's reply is streamed token by
 * token as soon as the provider yields it, so the client can render the first
 * tokens well inside the <2s time-to-first-token target. (Req 4.1, 4.4)
 *
 * Alongside the streamed conversational reply the provider returns a structured
 * `Grammar_Feedback` object; it is validated by
 * {@link validateGrammarFeedback} before it is returned to the client and
 * persisted. On success both the learner message and the assistant
 * message+feedback are written to
 * `users/{uid}/chatSessions/{sessionId}/messages/{messageId}`. (Req 4.2, 4.3)
 *
 * Streaming vs. moderation tradeoff: tokens are emitted to the client as the
 * provider yields them (to meet the time-to-first-token target), while the
 * accumulated reply plus feedback still pass through output moderation in the
 * metered gate. Output moderation therefore gates the *returned result and
 * persistence* — an unsafe reply yields a `refusal` status and is never
 * persisted, matching the design's "flagged content never reaches persistence"
 * rule. (Req 5.1, 5.2)
 *
 * All external effects (profile read, message persistence, id/clock, and the
 * metered middleware seams) are injected via {@link ChatDeps} so the core logic
 * is unit testable with in-memory fakes and the fake provider (including
 * injected streams). firebase-admin is loaded behind a lazy `require` in the
 * default deps, matching the placement.ts convention, so tests run without the
 * Admin SDK initialized or credentials present.
 */
import {
  MeteredAiContext,
  MeteredAiDeps,
  MeteredAiResponse,
  MeteredHandler,
  defaultMeteredAiDeps,
  meteredAi,
} from "../ai/metered";
import {
  GRAMMAR_FEEDBACK_SCHEMA,
  GrammarFeedback,
  validateGrammarFeedback,
} from "../ai/grammar_feedback";
import { AiRequest, CefrLevel, NativeLanguage } from "../ai/types";

/** Default native language when the learner profile is missing/unreadable. */
const DEFAULT_NATIVE_LANGUAGE: NativeLanguage = "hi";
/** Default CEFR level when the learner profile is missing/unreadable. */
const DEFAULT_CEFR_LEVEL: CefrLevel = "A1";

/** Learner profile fields the chat request depends on. */
export interface ChatProfile {
  /** Learner native language, used to target the feedback translation. */
  nativeLanguage: NativeLanguage;
  /** Learner CEFR level, forwarded to the provider request. */
  cefrLevel: CefrLevel;
}

/** Role of a persisted chat message. */
export type ChatRole = "user" | "assistant";

/**
 * A chat message as persisted under
 * `users/{uid}/chatSessions/{sessionId}/messages/{messageId}`.
 * `grammarFeedback` is present on assistant messages and `null` on user
 * messages, mirroring the design's chat data model.
 */
export interface StoredChatMessage {
  role: ChatRole;
  text: string;
  grammarFeedback: GrammarFeedback | null;
  createdAt: number;
}

/**
 * Persistence seam for chat messages. The default implementation writes to
 * `users/{uid}/chatSessions/{sessionId}/messages/{messageId}` via the Admin
 * SDK.
 */
export interface ChatMessageStore {
  saveMessage(
    uid: string,
    sessionId: string,
    messageId: string,
    message: StoredChatMessage,
  ): Promise<void>;
}

/** Injectable seams for {@link chatWithTeacherCore}. */
export interface ChatDeps {
  /** Persists chat messages + feedback. */
  store: ChatMessageStore;
  /** Reads the learner profile; returns null when absent/invalid. */
  getProfile(uid: string): Promise<ChatProfile | null>;
  /** Generates a unique message id. */
  generateId(): string;
  /** Current epoch-millis clock (injectable for deterministic tests). */
  now(): number;
  /** Metered-middleware seams (auth/tier/usage/moderation/provider). */
  meteredDeps: MeteredAiDeps;
}

/** Callback used to stream reply tokens to the client as they arrive. */
export type TokenEmitter = (token: string) => void;

/** Minimal callable context: verified auth + request data. */
export interface ChatWithTeacherContext {
  auth?: { uid: string } | null;
  data?: { sessionId?: unknown; text?: unknown };
}

/** Client-facing result of a successful chat turn. */
export interface ChatWithTeacherResult {
  /** The full assistant reply text (also streamed token by token). */
  reply: string;
  /** Validated, schema-conformant grammar feedback for the learner turn. */
  feedback: GrammarFeedback;
  /** Id of the persisted learner message. */
  userMessageId: string;
  /** Id of the persisted assistant message. */
  assistantMessageId: string;
}

/** Reply produced by the metered handler before persistence ids are assigned. */
interface HandlerReply {
  reply: string;
  feedback: GrammarFeedback;
}

/** Thrown when the chat input (sessionId/text) is missing or invalid. */
export class InvalidChatInputError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidChatInputError";
  }
}

/** True when `value` is a non-empty (post-trim) string. */
function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

/**
 * Builds the output text that must pass output moderation: the conversational
 * reply plus every learner-visible surface of the feedback (corrected
 * sentence, tip, and translation), so unsafe content in any field is caught.
 */
function buildOutputText(reply: string, feedback: GrammarFeedback): string {
  return [reply, feedback.correctedSentence, feedback.tip, feedback.translation.text]
    .filter((s) => typeof s === "string" && s.length > 0)
    .join("\n");
}

/**
 * Core chat logic: runs the shared metered gate, streaming reply tokens through
 * `emit` as the provider yields them, validates the structured
 * `Grammar_Feedback`, and — only on a moderated, successful turn — persists the
 * learner message and the assistant message+feedback. Returns the discriminated
 * {@link MeteredAiResponse} so the caller can branch on
 * `ok` | `limit_reached` | `refusal`.
 *
 * The learner's `input` is moderated before any provider call by the metered
 * gate; a refusal (input or output) or a reached limit returns the
 * corresponding status and persists nothing.
 */
export async function chatWithTeacherCore(
  context: ChatWithTeacherContext,
  deps: ChatDeps,
  emit: TokenEmitter = () => {},
): Promise<MeteredAiResponse<ChatWithTeacherResult>> {
  const sessionId = context.data?.sessionId;
  const text = context.data?.text;
  if (!isNonEmptyString(sessionId)) {
    throw new InvalidChatInputError("sessionId is required.");
  }
  if (!isNonEmptyString(text)) {
    throw new InvalidChatInputError("text is required.");
  }

  // Profile drives translation language + CEFR level. It is only needed when
  // auth is present; missing/invalid profiles fall back to safe defaults so a
  // brand-new learner can still chat. Auth itself is enforced by the gate.
  const uid = context.auth?.uid;
  const profile = uid ? await deps.getProfile(uid) : null;
  const nativeLanguage = profile?.nativeLanguage ?? DEFAULT_NATIVE_LANGUAGE;
  const cefrLevel = profile?.cefrLevel ?? DEFAULT_CEFR_LEVEL;

  const meteredContext: MeteredAiContext = {
    auth: context.auth,
    input: text,
    nativeLanguage,
    cefrLevel,
  };

  const handler: MeteredHandler<HandlerReply> = async (provider) => {
    const request: AiRequest = {
      kind: "chat",
      // Auth has passed by the time the handler runs, so uid is present.
      uid: context.auth!.uid,
      nativeLanguage,
      cefrLevel,
      payload: { sessionId, text },
      responseSchema: GRAMMAR_FEEDBACK_SCHEMA,
    };

    // Stream the conversational reply, emitting each token as soon as it is
    // produced (time-to-first-token target). Structured feedback may ride along
    // on a stream chunk; otherwise it is fetched via a single-shot generate.
    let reply = "";
    let structured: object | undefined;
    for await (const chunk of provider.generateStream(request)) {
      if (typeof chunk.text === "string" && chunk.text.length > 0) {
        reply += chunk.text;
        emit(chunk.text);
      }
      if (chunk.structured) {
        structured = chunk.structured;
      }
    }
    if (structured === undefined) {
      const generated = await provider.generate(request);
      structured = generated.structured;
      if (reply.length === 0 && typeof generated.text === "string") {
        reply = generated.text;
      }
    }

    // Validate before returning/persisting; a malformed provider response
    // throws GrammarFeedbackValidationError rather than reaching the client.
    const feedback = validateGrammarFeedback(structured);
    return { result: { reply, feedback }, outputText: buildOutputText(reply, feedback) };
  };

  const response = await meteredAi(meteredContext, "chat", handler, deps.meteredDeps);
  if (response.status === "limit_reached") {
    return { status: "limit_reached", limit: response.limit };
  }
  if (response.status === "refusal") {
    return { status: "refusal", safeMessage: response.safeMessage };
  }

  // Success: persist the learner message then the assistant message+feedback.
  const authedUid = context.auth!.uid;
  const createdAt = deps.now();
  const { reply, feedback } = response.result;

  const userMessageId = deps.generateId();
  await deps.store.saveMessage(authedUid, sessionId, userMessageId, {
    role: "user",
    text,
    grammarFeedback: null,
    createdAt,
  });

  const assistantMessageId = deps.generateId();
  await deps.store.saveMessage(authedUid, sessionId, assistantMessageId, {
    role: "assistant",
    text: reply,
    grammarFeedback: feedback,
    createdAt,
  });

  return {
    status: "ok",
    result: { reply, feedback, userMessageId, assistantMessageId },
  };
}

/**
 * Default {@link ChatMessageStore} backed by the Admin SDK Firestore. `require`
 * is deferred to call time so the module loads without credentials and stays
 * unit-testable with an in-memory store.
 */
export const defaultChatMessageStore: ChatMessageStore = {
  async saveMessage(
    uid: string,
    sessionId: string,
    messageId: string,
    message: StoredChatMessage,
  ): Promise<void> {
    const db = getFirestore();
    await db
      .collection("users")
      .doc(uid)
      .collection("chatSessions")
      .doc(sessionId)
      .collection("messages")
      .doc(messageId)
      .set({
        role: message.role,
        text: message.text,
        grammarFeedback: message.grammarFeedback,
        createdAt: message.createdAt,
      });
  },
};

/**
 * Reads the learner profile from `users/{uid}/profile/main` via the Admin SDK.
 * firebase-admin is required lazily so tests never touch the Admin SDK. Returns
 * null when the doc is missing or fields fail enum validation, which drives the
 * safe language/level defaults.
 */
async function fetchChatProfile(uid: string): Promise<ChatProfile | null> {
  const db = getFirestore();
  const snap = await db.collection("users").doc(uid).collection("profile").doc("main").get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data() ?? {};
  // Placement refines the self-selected level; prefer it when present.
  const level = (data.placementLevel ?? data.englishLevel) as unknown;
  const nativeLanguage = data.nativeLanguage as unknown;
  if (!isCefrLevel(level) || !isNativeLanguage(nativeLanguage)) {
    return null;
  }
  return { cefrLevel: level, nativeLanguage };
}

const CEFR_LEVELS: ReadonlyArray<CefrLevel> = ["A1", "A2", "B1", "B2", "C1"];
const NATIVE_LANGUAGES: ReadonlyArray<NativeLanguage> = ["hi", "ta", "te", "bn", "mr"];

function isCefrLevel(value: unknown): value is CefrLevel {
  return typeof value === "string" && (CEFR_LEVELS as ReadonlyArray<string>).includes(value);
}
function isNativeLanguage(value: unknown): value is NativeLanguage {
  return typeof value === "string" && (NATIVE_LANGUAGES as ReadonlyArray<string>).includes(value);
}

/** Default id generator: a lazily-required UUID, never at module load. */
function defaultGenerateId(): string {
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const { randomUUID } = require("crypto") as { randomUUID(): string };
  return randomUUID();
}

/** Default deps wiring the Admin-backed store/profile and metered middleware. */
export const defaultChatDeps: ChatDeps = {
  store: defaultChatMessageStore,
  getProfile: fetchChatProfile,
  generateId: defaultGenerateId,
  now: () => Date.now(),
  meteredDeps: defaultMeteredAiDeps,
};

/**
 * The `chatWithTeacher` streaming HTTPS callable. Thin wrapper that adapts the
 * callable request to {@link chatWithTeacherCore} using the default (Admin SDK)
 * deps. Reply tokens are forwarded to the client via `response.sendChunk` when
 * the client accepts streaming; the final return value carries the full reply,
 * the validated `Grammar_Feedback`, and the persisted message ids. Clients
 * branch on `status` (`ok` | `limit_reached` | `refusal`); invalid input and
 * provider faults are surfaced as typed `HttpsError`s.
 */
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
const { onCall, HttpsError } = require("firebase-functions/v2/https");
export const chatWithTeacher = onCall(
  async (request: ChatCallableRequest, response?: ChatCallableResponse) => {
    const auth = request.auth ? { uid: request.auth.uid } : null;
    const emit: TokenEmitter = (token) => {
      if (response && typeof response.sendChunk === "function") {
        response.sendChunk({ token });
      }
    };

    try {
      return await chatWithTeacherCore(
        { auth, data: { sessionId: request.data?.sessionId, text: request.data?.text } },
        defaultChatDeps,
        emit,
      );
    } catch (err) {
      if (err instanceof InvalidChatInputError) {
        throw new HttpsError("invalid-argument", err.message);
      }
      if (err instanceof Error && err.name === "GrammarFeedbackValidationError") {
        throw new HttpsError("internal", "Could not generate valid feedback.");
      }
      if (err instanceof Error && err.name === "AuthRequiredError") {
        throw new HttpsError("unauthenticated", err.message);
      }
      throw err;
    }
  },
);

/** Minimal shape of the streaming callable request we consume. */
interface ChatCallableRequest {
  auth?: { uid: string };
  data?: { sessionId?: unknown; text?: unknown };
}
/** Minimal shape of the streaming callable response surface we consume. */
interface ChatCallableResponse {
  sendChunk(chunk: unknown): void;
}

/**
 * Lazily resolves the Admin SDK Firestore instance. `require` happens at call
 * time (never at module load) so this module and its callable can be
 * unit-tested without the Admin SDK initialized or credentials present.
 */
function getFirestore(): FirestoreLike {
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const admin = require("firebase-admin") as AdminLike;
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  return admin.firestore();
}

// --- Minimal structural types mirroring the Admin SDK surface we consume. ---
interface DocumentSnapshotLike {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
}
interface DocumentRefLike {
  get(): Promise<DocumentSnapshotLike>;
  set(data: Record<string, unknown>): Promise<unknown>;
  collection(path: string): CollectionRefLike;
}
interface CollectionRefLike {
  doc(path: string): DocumentRefLike;
}
interface FirestoreLike {
  collection(path: string): CollectionRefLike;
}
interface AdminLike {
  apps: unknown[];
  initializeApp(): void;
  firestore(): FirestoreLike;
}
