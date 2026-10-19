/**
 * `generatePlacementQuestion` callable — server-side adaptive placement source.
 *
 * The onboarding placement flow walks a CEFR difficulty-band ladder (A1–C1).
 * The client drives the ladder (step up on a correct answer, down on a wrong
 * one) but MUST NOT hold the answer keys: the difficulty ladder and the correct
 * answers stay off the client so the placement result can't be gamed. This
 * function therefore:
 *
 *   1. generates the next question at the requested band via the provider
 *      abstraction (moderated through the shared {@link meteredAi} gate),
 *   2. returns ONLY the client-facing question (prompt + options, no answer),
 *   3. persists the correct-answer key to a server-only store keyed by a
 *      server-issued `questionId`, and
 *   4. grades any `priorAnswers` the client submits against the previously
 *      stored keys, returning just a per-question `correct` boolean — never the
 *      correct option itself.
 *
 * All external effects (the answer-key store, the id generator, and the metered
 * middleware seams) are injected via {@link PlacementDeps} so the core logic is
 * unit testable with an in-memory store and the fake provider. firebase-admin
 * is loaded behind a lazy `require` in the default deps so tests run without the
 * Admin SDK initialized or credentials present. (Req 2.4)
 */
import {
  MeteredAiContext,
  MeteredAiDeps,
  MeteredAiResponse,
  MeteredHandler,
  defaultMeteredAiDeps,
  meteredAi,
} from "../ai/metered";
import { AiRequest, AiResult, CefrLevel, JsonSchema, NativeLanguage } from "../ai/types";

/** Ordered CEFR difficulty bands used by the placement ladder. */
export const PLACEMENT_BANDS: readonly CefrLevel[] = ["A1", "A2", "B1", "B2", "C1"];

/** Minimum number of options a valid placement question must offer. */
export const MIN_PLACEMENT_OPTIONS = 2;

/** A single previously-served question answer submitted by the client. */
export interface PlacementAnswerSubmission {
  /** Server-issued id of the question being answered. */
  questionId: string;
  /** Index the learner selected among the question's options. */
  selectedIndex: number;
}

/**
 * Client-supplied placement session state. Carries the band the next question
 * should target plus any prior answers to grade. `nativeLanguage` is optional
 * (it is known from onboarding by placement time) and only forwarded to the
 * provider request; it defaults to Hindi when absent.
 */
export interface PlacementSessionState {
  /** CEFR band the next question should target. */
  band: CefrLevel;
  /** Answers to previously served questions, to be graded server-side. */
  priorAnswers?: PlacementAnswerSubmission[];
  /** Learner native language, forwarded to the provider request. */
  nativeLanguage?: NativeLanguage;
}

/** Client-facing question payload. Deliberately omits the correct answer. */
export interface PlacementQuestion {
  /** Server-issued id used to grade the learner's answer later. */
  questionId: string;
  /** Band this question targets. */
  band: CefrLevel;
  /** The question prompt. */
  prompt: string;
  /** Answer options, in display order. The correct index is NOT included. */
  options: string[];
}

/** Server-held answer key. Never returned to the client. */
export interface PlacementAnswerKey {
  questionId: string;
  band: CefrLevel;
  /** Index of the correct option among the question's `options`. */
  correctIndex: number;
}

/** Result of grading one previously-served answer. */
export interface GradedAnswer {
  questionId: string;
  correct: boolean;
}

/** Client-facing result of a placement generation call. */
export interface GeneratePlacementQuestionResult {
  /** The next question to present (no answer key). */
  question: PlacementQuestion;
  /** Grading of any submitted `priorAnswers` (correctness only). */
  gradedAnswers: GradedAnswer[];
}

/** Minimal callable context: verified auth + request data. */
export interface GeneratePlacementQuestionContext {
  auth?: { uid: string } | null;
  data?: { sessionState?: unknown };
}

/**
 * Server-only persistence seam for placement answer keys. The default
 * implementation stores keys under `placementAnswerKeys/{uid}/questions/{id}`,
 * a collection that is not client-readable under the default-deny rules, so the
 * answer key never leaves the server. (Req 2.4)
 */
export interface PlacementAnswerKeyStore {
  saveAnswerKey(uid: string, key: PlacementAnswerKey): Promise<void>;
  getAnswerKey(uid: string, questionId: string): Promise<PlacementAnswerKey | null>;
}

/** Injectable seams for {@link generatePlacementQuestionCore}. */
export interface PlacementDeps {
  /** Server-only answer-key store. */
  store: PlacementAnswerKeyStore;
  /** Generates a unique, unguessable question id. */
  generateId(): string;
  /** Metered-middleware seams (auth/tier/usage/moderation/provider). */
  meteredDeps: MeteredAiDeps;
}

/**
 * Structured-output contract the provider is prompted with. The provider
 * returns a `prompt`, `options`, and the `correctIndex`; the correct index is
 * stripped before anything is returned to the client.
 */
export const PLACEMENT_QUESTION_SCHEMA: JsonSchema = {
  type: "object",
  properties: {
    prompt: { type: "string" },
    options: { type: "array", items: { type: "string" }, minItems: MIN_PLACEMENT_OPTIONS },
    correctIndex: { type: "integer", minimum: 0 },
  },
  required: ["prompt", "options", "correctIndex"],
};

/** Thrown when the requested session state is invalid (e.g. unknown band). */
export class InvalidPlacementStateError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InvalidPlacementStateError";
  }
}

/** Thrown when the provider's question does not satisfy the schema. */
export class PlacementQuestionSchemaError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PlacementQuestionSchemaError";
  }
}

/** Shape the provider is expected to produce for a placement question. */
interface ProviderPlacementQuestion {
  prompt: string;
  options: string[];
  correctIndex: number;
}

/** True when `band` is one of the supported CEFR bands. */
export function isPlacementBand(band: unknown): band is CefrLevel {
  return typeof band === "string" && (PLACEMENT_BANDS as readonly string[]).includes(band);
}

/**
 * Validates and narrows a provider result into a {@link ProviderPlacementQuestion}.
 * Throws {@link PlacementQuestionSchemaError} on any deviation so a malformed
 * provider response never reaches the client.
 */
export function parseProviderQuestion(result: AiResult): ProviderPlacementQuestion {
  const raw = (result.structured ?? undefined) as Record<string, unknown> | undefined;
  if (!raw || typeof raw !== "object") {
    throw new PlacementQuestionSchemaError("Provider returned no structured question.");
  }

  const { prompt, options, correctIndex } = raw as {
    prompt?: unknown;
    options?: unknown;
    correctIndex?: unknown;
  };

  if (typeof prompt !== "string" || prompt.trim().length === 0) {
    throw new PlacementQuestionSchemaError("Question prompt must be a non-empty string.");
  }
  if (
    !Array.isArray(options) ||
    options.length < MIN_PLACEMENT_OPTIONS ||
    !options.every((o) => typeof o === "string" && o.length > 0)
  ) {
    throw new PlacementQuestionSchemaError(
      `Question must have at least ${MIN_PLACEMENT_OPTIONS} non-empty string options.`,
    );
  }
  if (
    typeof correctIndex !== "number" ||
    !Number.isInteger(correctIndex) ||
    correctIndex < 0 ||
    correctIndex >= options.length
  ) {
    throw new PlacementQuestionSchemaError("correctIndex must index into the options array.");
  }

  return { prompt, options: options as string[], correctIndex };
}

/**
 * Grades submitted `priorAnswers` against the server-held keys. An answer for
 * an unknown question id is graded as incorrect rather than throwing, so a
 * stale or forged id can never be scored as correct.
 */
async function gradePriorAnswers(
  uid: string,
  priorAnswers: PlacementAnswerSubmission[],
  store: PlacementAnswerKeyStore,
): Promise<GradedAnswer[]> {
  const graded: GradedAnswer[] = [];
  for (const answer of priorAnswers) {
    const key = await store.getAnswerKey(uid, answer.questionId);
    const correct = key != null && key.correctIndex === answer.selectedIndex;
    graded.push({ questionId: answer.questionId, correct });
  }
  return graded;
}

/**
 * Core placement logic: validates the band, then runs the shared metered gate
 * (auth → tier → usage → input moderation → provider → output moderation →
 * increment). The provider handler grades prior answers, generates the next
 * question, stores its answer key server-side, and returns the client-facing
 * question with the correct index stripped. Returns the discriminated
 * {@link MeteredAiResponse} so the caller can branch on ok/limit_reached/refusal.
 */
export async function generatePlacementQuestionCore(
  auth: { uid: string } | null | undefined,
  sessionState: PlacementSessionState,
  deps: PlacementDeps,
): Promise<MeteredAiResponse<GeneratePlacementQuestionResult>> {
  if (!sessionState || !isPlacementBand(sessionState.band)) {
    throw new InvalidPlacementStateError(
      `sessionState.band must be one of ${PLACEMENT_BANDS.join(", ")}.`,
    );
  }

  const band = sessionState.band;
  const priorAnswers = sessionState.priorAnswers ?? [];
  const nativeLanguage: NativeLanguage = sessionState.nativeLanguage ?? "hi";

  const context: MeteredAiContext = {
    auth,
    // Placement carries no free-form learner text; a minimal, safe descriptor
    // satisfies the input-moderation gate without leaking anything.
    input: `placement:${band}`,
    nativeLanguage,
    cefrLevel: band,
  };

  const handler: MeteredHandler<GeneratePlacementQuestionResult> = async (provider) => {
    // Auth has passed by the time the handler runs, so uid is present.
    const uid = auth!.uid;

    const gradedAnswers = await gradePriorAnswers(uid, priorAnswers, deps.store);

    const request: AiRequest = {
      kind: "placementQuestion",
      uid,
      nativeLanguage,
      cefrLevel: band,
      payload: { band, askedCount: priorAnswers.length },
      responseSchema: PLACEMENT_QUESTION_SCHEMA,
    };
    const parsed = parseProviderQuestion(await provider.generate(request));

    const questionId = deps.generateId();
    await deps.store.saveAnswerKey(uid, { questionId, band, correctIndex: parsed.correctIndex });

    const question: PlacementQuestion = {
      questionId,
      band,
      prompt: parsed.prompt,
      options: parsed.options,
    };

    return {
      result: { question, gradedAnswers },
      // Moderate the learner-visible surface of the question only.
      outputText: [parsed.prompt, ...parsed.options].join("\n"),
    };
  };

  return meteredAi(context, "placementQuestion", handler, deps.meteredDeps);
}

/**
 * Default {@link PlacementAnswerKeyStore} backed by the Admin SDK Firestore.
 * `require` is deferred to call time so the module loads without credentials
 * and stays unit-testable with an in-memory store.
 */
export const defaultPlacementStore: PlacementAnswerKeyStore = {
  async saveAnswerKey(uid: string, key: PlacementAnswerKey): Promise<void> {
    const db = getFirestore();
    await db
      .collection("placementAnswerKeys")
      .doc(uid)
      .collection("questions")
      .doc(key.questionId)
      .set({ band: key.band, correctIndex: key.correctIndex });
  },
  async getAnswerKey(uid: string, questionId: string): Promise<PlacementAnswerKey | null> {
    const db = getFirestore();
    const snap = await db
      .collection("placementAnswerKeys")
      .doc(uid)
      .collection("questions")
      .doc(questionId)
      .get();
    if (!snap.exists) {
      return null;
    }
    const data = snap.data() ?? {};
    const correctIndex = data.correctIndex;
    const band = data.band;
    if (typeof correctIndex !== "number" || !isPlacementBand(band)) {
      return null;
    }
    return { questionId, band, correctIndex };
  },
};

/** Default id generator: a lazily-required UUID, never at module load. */
function defaultGenerateId(): string {
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const { randomUUID } = require("crypto") as { randomUUID(): string };
  return randomUUID();
}

/** Default deps wiring the Admin-backed store and the metered middleware. */
export const defaultPlacementDeps: PlacementDeps = {
  store: defaultPlacementStore,
  generateId: defaultGenerateId,
  meteredDeps: defaultMeteredAiDeps,
};

/**
 * The `generatePlacementQuestion` HTTPS callable. Thin wrapper that adapts the
 * callable request to {@link generatePlacementQuestionCore} using the default
 * (Admin SDK) deps. Returns the discriminated response so the client branches on
 * `status` (`ok` | `limit_reached` | `refusal`); invalid input and provider
 * faults are surfaced as typed `HttpsError`s.
 */
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
const { onCall, HttpsError } = require("firebase-functions/v2/https");
export const generatePlacementQuestion = onCall(
  async (request: GeneratePlacementQuestionContext) => {
    const sessionState = request.data?.sessionState as PlacementSessionState | undefined;
    if (!sessionState) {
      throw new HttpsError("invalid-argument", "Missing sessionState.");
    }
    const auth = request.auth ? { uid: request.auth.uid } : null;

    try {
      return await generatePlacementQuestionCore(auth, sessionState, defaultPlacementDeps);
    } catch (err) {
      if (err instanceof InvalidPlacementStateError) {
        throw new HttpsError("invalid-argument", err.message);
      }
      if (err instanceof PlacementQuestionSchemaError) {
        throw new HttpsError("internal", "Could not generate a placement question.");
      }
      if (err instanceof Error && err.name === "AuthRequiredError") {
        throw new HttpsError("unauthenticated", err.message);
      }
      throw err;
    }
  },
);

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
