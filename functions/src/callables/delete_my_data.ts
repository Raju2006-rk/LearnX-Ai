/**
 * `deleteMyData` callable — the DPDP "right to erasure" data-delete path.
 *
 * Input: none (the caller's own account). Erases everything LearnX holds for
 * the verified caller: it recursively deletes the `users/{uid}/**` Firestore
 * subtree (which covers `reports`, `usage`, `progress`, `profile`, …) and then
 * revokes the Firebase Auth user so the account can no longer sign in.
 * (Req 10.3)
 *
 * The function only ever operates on the *verified* caller uid — never a uid
 * supplied in the request payload — so one learner can never delete another's
 * data.
 *
 * All external effects (recursive Firestore delete, auth user deletion) are
 * injected via {@link DeleteMyDataDeps} so the core logic is unit testable with
 * in-memory fakes. firebase-admin is loaded behind a lazy `require` in the
 * default deps so tests run without the Admin SDK initialized or credentials
 * present.
 */

/** Minimal callable context: the verified auth payload. */
export interface DeleteMyDataContext {
  /** Verified auth payload; `uid` is present for authenticated callers. */
  auth?: { uid: string } | null;
}

/** Successful erasure result handed back to the caller. */
export interface DeleteMyDataResult {
  status: "deleted";
  /** The uid whose data + auth account were erased. */
  uid: string;
}

/** Injectable seams the erasure flow depends on. */
export interface DeleteMyDataDeps {
  /** Recursively deletes the `users/{uid}/**` Firestore subtree. */
  recursiveDeleteUserData(uid: string): Promise<void>;
  /** Revokes (deletes) the Firebase Auth user so it can no longer sign in. */
  deleteAuthUser(uid: string): Promise<void>;
}

/** Thrown when the delete call is made without a verified authenticated uid. */
export class AuthRequiredError extends Error {
  constructor(message = "Authentication is required for this action.") {
    super(message);
    this.name = "AuthRequiredError";
  }
}

/**
 * Core erasure logic. Requires auth, recursively deletes the `users/{uid}/**`
 * subtree (covering `reports` and every other per-user collection), then
 * revokes the Firebase Auth user. Firestore data is deleted BEFORE the auth
 * account so a partial failure never leaves an active account whose data still
 * lingers unreachable. Throws {@link AuthRequiredError} when unauthenticated so
 * the callable wrapper maps it onto an `unauthenticated` error. (Req 10.3)
 */
export async function deleteMyDataCore(
  context: DeleteMyDataContext,
  deps: DeleteMyDataDeps,
): Promise<DeleteMyDataResult> {
  const uid = context.auth?.uid;
  if (!uid) {
    throw new AuthRequiredError();
  }
  await deps.recursiveDeleteUserData(uid);
  await deps.deleteAuthUser(uid);
  return { status: "deleted", uid };
}

/**
 * Lazily resolves an initialized Admin SDK instance. `require` happens at call
 * time (never at module load) so the core logic and its callable can be
 * unit-tested without the Admin SDK initialized or credentials present.
 */
function requireAdmin(): AdminLike {
  // eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
  const admin = require("firebase-admin") as AdminLike;
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }
  return admin;
}

/**
 * Default deps over the Admin SDK. `recursiveDelete` walks and deletes the
 * whole `users/{uid}` document subtree; `auth().deleteUser` revokes the
 * account.
 */
export const defaultDeleteMyDataDeps: DeleteMyDataDeps = {
  async recursiveDeleteUserData(uid: string): Promise<void> {
    const admin = requireAdmin();
    const db = admin.firestore();
    await db.recursiveDelete(db.collection("users").doc(uid));
  },
  async deleteAuthUser(uid: string): Promise<void> {
    const admin = requireAdmin();
    await admin.auth().deleteUser(uid);
  },
};

/**
 * The `deleteMyData` HTTPS callable. Thin wrapper that adapts the callable
 * request to {@link deleteMyDataCore} using the default (Admin SDK) deps. The
 * function only ever erases the *verified* caller's data; {@link AuthRequiredError}
 * is mapped onto an `unauthenticated` {@link HttpsError} so an unauthenticated
 * caller gets a typed error rather than an internal fault. (Req 10.3)
 */
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
const { onCall, HttpsError } = require("firebase-functions/v2/https");
export const deleteMyData = onCall(async (request: { auth?: { uid: string } }) => {
  const context: DeleteMyDataContext = {
    auth: request.auth ? { uid: request.auth.uid } : null,
  };
  try {
    return await deleteMyDataCore(context, defaultDeleteMyDataDeps);
  } catch (err) {
    if (err instanceof AuthRequiredError) {
      throw new HttpsError("unauthenticated", err.message);
    }
    throw err;
  }
});

// --- Minimal structural types mirroring the Admin SDK surface we consume. ---
interface DocumentRefLike {
  path: string;
}
interface CollectionRefLike {
  doc(path: string): DocumentRefLike;
}
interface FirestoreLike {
  collection(path: string): CollectionRefLike;
  recursiveDelete(ref: DocumentRefLike): Promise<void>;
}
interface AuthLike {
  deleteUser(uid: string): Promise<void>;
}
interface AdminLike {
  apps: unknown[];
  initializeApp(): void;
  firestore(): FirestoreLike;
  auth(): AuthLike;
}
