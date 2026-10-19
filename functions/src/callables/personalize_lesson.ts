/**
 * `personalizeLesson` callable for the AI_Proxy.
 *
 * Input `{ stepId }`. Reads the learner's profile (CEFR level + goal) and the
 * authored step, then asks the provider (through the {@link meteredAi} gate) for
 * personalized examples/practice tagged by the learner's CEFR level and goal.
 *
 * CRITICAL — skeleton fallback contract (Req 3.5, 3.6): on ANY failure
 * (unauthenticated, missing/invalid profile or step, usage limit reached,
 * moderation refusal, provider error, or malformed/invalid provider output)
 * this returns `{ personalization: null }` rather than surfacing an error, so
 * the client always falls back to the authored skeleton content. Personalized
 * content is strictly additive; its absence never blocks a lesson.
 *
 * All external effects (profile read, step read, metering/provider/moderation)
 * are injected via {@link PersonalizeLessonDeps} so the core logic is unit
 * testable with in-memory fakes. firebase-admin is loaded behind a lazy
 * `require` in the default deps so tests run without Admin SDK init.
 */
import {
  MeteredAiContext,
  MeteredAiDeps,
  MeteredHandler,
  defaultMeteredAiDeps,
  meteredAi,
} from "../ai/metered";
import { AiRequest, CefrLevel, JsonSchema, NativeLanguage } from "../ai/types";

/** Learner goal captured during onboarding. */
export type LearnerGoal = "speaking" | "job" | "both";

/** Allowed CEFR levels, used to validate a profile before personalizing. */
const CEFR_LEVELS: ReadonlyArray<CefrLevel> = ["A1", "A2", "B1", "B2", "C1"];
/** Allowed learner goals. */
const GOALS: ReadonlyArray<LearnerGoal> = ["speaking", "job", "both"];
/** Allowed native languages. */
const NATIVE_LANGUAGES: ReadonlyArray<NativeLanguage> = ["hi", "ta", "te", "bn", "mr"];

/** Learner profile fields the personalization request depends on. */
export interface LessonProfile {
  cefrLevel: CefrLevel;
  goal: LearnerGoal;
  nativeLanguage: NativeLanguage;
}

/** Authored step context used to build the personalization prompt. */
export interface AuthoredStep {
  title: string;
  objectives: string[];
}

/**
 * Personalized lesson payload returned to the client. It is explicitly tagged
 * with the learner's `cefrLevel` and `goal` so the client can render (and the
 * server can audit) which cohort the content was generated for.
 */
export interface LessonPersonalization {
  cefrLevel: CefrLevel;
  goal: LearnerGoal;
  /** CEFR/goal-appropriate example sentences. */
  examples: string[];
  /** CEFR/goal-appropriate practice prompts. */
  practice: string[];
}

/** Result shape of the callable. `null` signals "use the authored skeleton". */
export interface PersonalizeLessonResult {
  personalization: LessonPersonalization | null;
}

/** Minimal callable context: verified auth + request data. */
export interface PersonalizeLessonContext {
  auth?: { uid: string } | null;
  data?: { stepId?: unknown };
}

/** Injectable seams the core logic depends on. */
export interface PersonalizeLessonDeps {
  /** Reads the learner profile; returns null when absent/invalid. */
  getProfile(uid: string): Promise<LessonProfile | null>;
  /** Reads the authored step; returns null when the step is not found. */
  getStep(stepId: string): Promise<AuthoredStep | null>;
  /** Metered-AI seams forwarded to {@link meteredAi}. */
  meteredDeps: MeteredAiDeps;
}

/**
 * Structured-output contract requested from the provider. Kept loose here; the
 * concrete shape is validated by {@link parsePersonalization}.
 */
export const PERSONALIZATION_SCHEMA: JsonSchema = {
  type: "object",
  properties: {
    examples: { type: "array", items: { type: "string" } },
    practice: { type: "array", items: { type: "string" } },
  },
  required: ["examples", "practice"],
};

/** Result signalling the client to fall back to the authored skeleton. */
const FALLBACK: PersonalizeLessonResult = { personalization: null };

/** Builds the moderation input text from the step + profile. */
function buildModerationInput(step: AuthoredStep, profile: LessonProfile): string {
  return [step.title, ...step.objectives, `goal:${profile.goal}`, `level:${profile.cefrLevel}`]
    .filter(Boolean)
    .join(" \n");
}

/** Flattens a personalization payload into text for output moderation. */
function personalizationText(p: LessonPersonalization): string {
  return [...p.examples, ...p.practice].join(" \n");
}

/** Validates that `value` is a non-empty array of non-empty strings. */
function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error("Expected a non-empty string array.");
  }
  return value.map((item) => {
    if (typeof item !== "string" || item.trim().length === 0) {
      throw new Error("Expected every array item to be a non-empty string.");
    }
    return item;
  });
}

/**
 * Validates the provider's structured output against the personalization schema
 * and tags it with the learner's CEFR level and goal. Throws on any malformed
 * output so the caller's try/catch converts it into the skeleton fallback.
 */
export function parsePersonalization(
  structured: object | undefined,
  profile: LessonProfile,
): LessonPersonalization {
  if (!structured || typeof structured !== "object") {
    throw new Error("Provider returned no structured personalization.");
  }
  const raw = structured as { examples?: unknown; practice?: unknown };
  return {
    cefrLevel: profile.cefrLevel,
    goal: profile.goal,
    examples: asStringArray(raw.examples),
    practice: asStringArray(raw.practice),
  };
}

/**
 * Core personalization logic. Never throws: any failure resolves to the
 * skeleton fallback `{ personalization: null }`.
 */
export async function personalizeLessonCore(
  context: PersonalizeLessonContext,
  deps: PersonalizeLessonDeps,
): Promise<PersonalizeLessonResult> {
  try {
    const uid = context.auth?.uid;
    if (!uid) {
      return FALLBACK;
    }
    const stepId = context.data?.stepId;
    if (typeof stepId !== "string" || stepId.trim().length === 0) {
      return FALLBACK;
    }

    const profile = await deps.getProfile(uid);
    if (!profile) {
      return FALLBACK;
    }
    const step = await deps.getStep(stepId);
    if (!step) {
      return FALLBACK;
    }

    const meteredContext: MeteredAiContext = {
      auth: { uid },
      input: buildModerationInput(step, profile),
      nativeLanguage: profile.nativeLanguage,
      cefrLevel: profile.cefrLevel,
    };

    const handler: MeteredHandler<LessonPersonalization> = async (provider) => {
      const request: AiRequest = {
        kind: "lessonPersonalization",
        uid,
        nativeLanguage: profile.nativeLanguage,
        cefrLevel: profile.cefrLevel,
        payload: {
          stepId,
          goal: profile.goal,
          title: step.title,
          objectives: step.objectives,
        },
        responseSchema: PERSONALIZATION_SCHEMA,
      };
      const out = await provider.generate(request);
      const personalization = parsePersonalization(out.structured, profile);
      return { result: personalization, outputText: personalizationText(personalization) };
    };

    const response = await meteredAi(
      meteredContext,
      "lessonPersonalization",
      handler,
      deps.meteredDeps,
    );
    if (response.status !== "ok") {
      return FALLBACK;
    }
    return { personalization: response.result };
  } catch {
    // Any error (provider throw, validation failure, admin read error, …) falls
    // back to the authored skeleton rather than surfacing an error client-side.
    return FALLBACK;
  }
}

/**
 * Reads the learner profile from `users/{uid}/profile/main` via the Admin SDK.
 * firebase-admin is required lazily so tests never touch the Admin SDK. Returns
 * null when the doc is missing or any field fails enum validation, which drives
 * the skeleton fallback.
 */
async function fetchProfile(uid: string): Promise<LessonProfile | null> {
  const db = getFirestore();
  const snap = await db.collection("users").doc(uid).collection("profile").doc("main").get();
  if (!snap.exists) {
    return null;
  }
  const data = snap.data() ?? {};
  // Placement refines the self-selected level; prefer it when present.
  const level = (data.placementLevel ?? data.englishLevel) as unknown;
  const goal = data.goal as unknown;
  const nativeLanguage = data.nativeLanguage as unknown;
  if (
    !isCefrLevel(level) ||
    !isGoal(goal) ||
    !isNativeLanguage(nativeLanguage)
  ) {
    return null;
  }
  return { cefrLevel: level, goal, nativeLanguage };
}

/**
 * Reads an authored step by id. Authored steps live under a deep content path;
 * the client passes only a `stepId`, so this resolves the step via a collection
 * group query. Returns null when not found so the client falls back to the
 * skeleton it already holds.
 */
async function fetchStep(stepId: string): Promise<AuthoredStep | null> {
  const db = getFirestore();
  const query = await db
    .collectionGroup("steps")
    .where("stepId", "==", stepId)
    .limit(1)
    .get();
  if (query.empty) {
    return null;
  }
  const data = query.docs[0].data() ?? {};
  const skeleton = (data.skeleton ?? {}) as { objectives?: unknown };
  const objectives = Array.isArray(skeleton.objectives)
    ? skeleton.objectives.filter((o): o is string => typeof o === "string")
    : [];
  const title = typeof data.title === "string" ? data.title : stepId;
  return { title, objectives };
}

function isCefrLevel(value: unknown): value is CefrLevel {
  return typeof value === "string" && (CEFR_LEVELS as ReadonlyArray<string>).includes(value);
}
function isGoal(value: unknown): value is LearnerGoal {
  return typeof value === "string" && (GOALS as ReadonlyArray<string>).includes(value);
}
function isNativeLanguage(value: unknown): value is NativeLanguage {
  return typeof value === "string" && (NATIVE_LANGUAGES as ReadonlyArray<string>).includes(value);
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

/** Default deps: Admin SDK profile/step reads + the production metered seams. */
export const defaultPersonalizeLessonDeps: PersonalizeLessonDeps = {
  getProfile: fetchProfile,
  getStep: fetchStep,
  meteredDeps: defaultMeteredAiDeps,
};

/**
 * The `personalizeLesson` HTTPS callable. Thin wrapper that adapts the callable
 * request to {@link personalizeLessonCore} using the default (Admin SDK) deps.
 */
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
const { onCall } = require("firebase-functions/v2/https");
export const personalizeLesson = onCall(
  async (request: { auth?: { uid: string }; data?: { stepId?: unknown } }) => {
    const context: PersonalizeLessonContext = {
      auth: request.auth ? { uid: request.auth.uid } : null,
      data: { stepId: request.data?.stepId },
    };
    return personalizeLessonCore(context, defaultPersonalizeLessonDeps);
  },
);

// --- Minimal structural types mirroring the Admin SDK surface we consume. ---
interface DocumentSnapshotLike {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
}
interface DocumentRefLike {
  get(): Promise<DocumentSnapshotLike>;
  collection(path: string): CollectionRefLike;
}
interface CollectionRefLike {
  doc(path: string): DocumentRefLike;
}
interface QuerySnapshotLike {
  empty: boolean;
  docs: Array<{ data(): Record<string, unknown> | undefined }>;
}
interface QueryLike {
  where(field: string, op: string, value: unknown): QueryLike;
  limit(n: number): QueryLike;
  get(): Promise<QuerySnapshotLike>;
}
interface FirestoreLike {
  collection(path: string): CollectionRefLike;
  collectionGroup(path: string): QueryLike;
}
interface AdminLike {
  apps: unknown[];
  initializeApp(): void;
  firestore(): FirestoreLike;
}
