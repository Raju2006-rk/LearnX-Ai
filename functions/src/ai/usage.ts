/**
 * Usage metering and tier-limit seams for the AI_Proxy.
 *
 * These are the Admin SDK / Remote Config backed implementations that the
 * {@link meteredAi} middleware depends on. They are intentionally small,
 * side-effecting functions so the middleware can be unit-tested with in-memory
 * fakes while production wires the real Firestore/Remote Config here.
 *
 * Per-tier daily counters live at `users/{uid}/usage/{yyyy-mm-dd}` and are
 * written ONLY by functions via the Admin SDK, so usage limits are tamper-proof
 * from the client. Limits are read from Remote Config so they can be tuned
 * without redeploying. (Req 4.6, 11.3, 11.4)
 */
import { AiRequestKind } from "./types";

/** Account entitlement level. `premium` is reserved; the MVP defaults `free`. */
export type AccountTier = "free" | "premium";

/**
 * Metered action kind. Mirrors {@link AiRequestKind} so the middleware and the
 * provider abstraction share one vocabulary.
 */
export type UsageKind = AiRequestKind;

/** Daily limits for each metered action, per tier. */
export type TierLimits = Record<UsageKind, number>;

/**
 * Firestore field on the daily usage doc that counts each metered kind. The
 * usage doc shape is `{ chatMessages, lessonPersonalizations,
 * placementGenerations }` per the design data model.
 */
export const USAGE_FIELD_BY_KIND: Record<UsageKind, string> = {
  chat: "chatMessages",
  lessonPersonalization: "lessonPersonalizations",
  placementQuestion: "placementGenerations",
};

/**
 * Safe default limits used when Remote Config is unavailable (e.g. local dev or
 * a transient fetch failure). Chosen conservatively so the gate still enforces
 * a cap rather than failing open. Free is metered; premium is effectively
 * unmetered for the MVP.
 */
export const DEFAULT_TIER_LIMITS: Record<AccountTier, TierLimits> = {
  free: { chat: 20, lessonPersonalization: 20, placementQuestion: 15 },
  premium: {
    chat: Number.MAX_SAFE_INTEGER,
    lessonPersonalization: Number.MAX_SAFE_INTEGER,
    placementQuestion: Number.MAX_SAFE_INTEGER,
  },
};

/** Remote Config parameter key holding the JSON limits-by-tier map. */
export const REMOTE_CONFIG_LIMITS_KEY = "aiUsageLimits";

/** Returns the UTC calendar-day key (`yyyy-mm-dd`) for `date`. */
export function dayKey(date: Date = new Date()): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Lazily resolves the Admin SDK Firestore instance. `require` happens at call
 * time (never at module load) so the middleware and its seams can be
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

/**
 * Reads the learner's account tier from `users/{uid}`. Defaults to `free` when
 * the document or field is absent so metering always applies.
 */
export async function getUserTier(uid: string): Promise<AccountTier> {
  const db = getFirestore();
  const snap = await db.collection("users").doc(uid).get();
  const tier = snap.exists ? (snap.data()?.accountTier as string | undefined) : undefined;
  return tier === "premium" ? "premium" : "free";
}

/**
 * Reads today's usage count for `kind` from
 * `users/{uid}/usage/{yyyy-mm-dd}`. Returns 0 when the counter is absent.
 */
export async function getTodayUsage(uid: string, kind: UsageKind): Promise<number> {
  const db = getFirestore();
  const snap = await db
    .collection("users")
    .doc(uid)
    .collection("usage")
    .doc(dayKey())
    .get();
  if (!snap.exists) {
    return 0;
  }
  const value = snap.data()?.[USAGE_FIELD_BY_KIND[kind]];
  return typeof value === "number" ? value : 0;
}

/**
 * Atomically increments today's usage counter for `kind` at
 * `users/{uid}/usage/{yyyy-mm-dd}`, creating the doc/field as needed. Uses a
 * field increment so concurrent function invocations reconcile correctly.
 */
export async function incrementUsage(uid: string, kind: UsageKind): Promise<void> {
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const admin = require("firebase-admin") as AdminLike;
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  const db = admin.firestore();
  await db
    .collection("users")
    .doc(uid)
    .collection("usage")
    .doc(dayKey())
    .set({ [USAGE_FIELD_BY_KIND[kind]]: admin.firestore.FieldValue.increment(1) }, { merge: true });
}

/**
 * Reads the per-tier daily limits from Remote Config, falling back to
 * {@link DEFAULT_TIER_LIMITS} when Remote Config is unavailable or the
 * parameter is missing/malformed. This keeps limits tunable without redeploy
 * while never failing open. (Req 11.3)
 */
export async function getLimits(tier: AccountTier): Promise<TierLimits> {
  try {
    // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
    const admin = require("firebase-admin") as AdminLike;
    if (admin.apps.length === 0) {
      admin.initializeApp();
    }
    const remoteConfig = admin.remoteConfig?.();
    const template = await remoteConfig?.getServerTemplate?.();
    const config = template?.evaluate?.();
    const raw = config?.getString?.(REMOTE_CONFIG_LIMITS_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<Record<AccountTier, Partial<TierLimits>>>;
      const forTier = parsed[tier];
      if (forTier) {
        return {
          chat: forTier.chat ?? DEFAULT_TIER_LIMITS[tier].chat,
          lessonPersonalization:
            forTier.lessonPersonalization ?? DEFAULT_TIER_LIMITS[tier].lessonPersonalization,
          placementQuestion:
            forTier.placementQuestion ?? DEFAULT_TIER_LIMITS[tier].placementQuestion,
        };
      }
    }
  } catch {
    // Fall through to defaults: never fail open on a Remote Config error.
  }
  return DEFAULT_TIER_LIMITS[tier];
}

// --- Minimal structural types mirroring the Admin SDK surface we consume. ---
// These keep the module typed and testable without depending on the concrete
// firebase-admin types at compile time.

interface DocumentSnapshotLike {
  exists: boolean;
  data(): Record<string, unknown> | undefined;
}
interface DocumentRefLike {
  get(): Promise<DocumentSnapshotLike>;
  set(data: Record<string, unknown>, options?: { merge?: boolean }): Promise<unknown>;
  collection(path: string): CollectionRefLike;
}
interface CollectionRefLike {
  doc(path: string): DocumentRefLike;
}
interface FirestoreLike {
  collection(path: string): CollectionRefLike;
}
interface RemoteConfigLike {
  getServerTemplate?(): Promise<{
    evaluate?(): { getString?(key: string): string | undefined } | undefined;
  }>;
}
interface AdminLike {
  apps: unknown[];
  initializeApp(): void;
  firestore: (() => FirestoreLike) & {
    FieldValue: { increment(n: number): unknown };
  };
  remoteConfig?(): RemoteConfigLike | undefined;
}
