import {
  AuthRequiredError,
  DeleteMyDataContext,
  DeleteMyDataDeps,
  deleteMyDataCore,
} from "./delete_my_data";

/**
 * Builds an in-memory {@link DeleteMyDataDeps} that records the ordered calls
 * plus the uid each seam was invoked with, so tests can assert both that the
 * effects ran and that they targeted the *verified caller* uid only.
 */
function makeHarness() {
  const calls: string[] = [];
  const deletedDataFor: string[] = [];
  const revokedAuthFor: string[] = [];

  const deps: DeleteMyDataDeps = {
    async recursiveDeleteUserData(uid: string) {
      calls.push("recursiveDeleteUserData");
      deletedDataFor.push(uid);
    },
    async deleteAuthUser(uid: string) {
      calls.push("deleteAuthUser");
      revokedAuthFor.push(uid);
    },
  };

  return { deps, calls, deletedDataFor, revokedAuthFor };
}

const authedContext: DeleteMyDataContext = { auth: { uid: "user-1" } };

describe("deleteMyData core flow", () => {
  it("requires authentication before deleting anything", async () => {
    const { deps, calls } = makeHarness();

    await expect(deleteMyDataCore({ auth: null }, deps)).rejects.toBeInstanceOf(
      AuthRequiredError,
    );
    // No effect ran on the unauthenticated path.
    expect(calls).toEqual([]);
  });

  it("treats a missing auth field the same as unauthenticated", async () => {
    const { deps, calls } = makeHarness();

    await expect(deleteMyDataCore({}, deps)).rejects.toBeInstanceOf(AuthRequiredError);
    expect(calls).toEqual([]);
  });

  it("deletes the user subtree then revokes auth for the verified caller uid", async () => {
    const { deps, calls, deletedDataFor, revokedAuthFor } = makeHarness();

    const res = await deleteMyDataCore(authedContext, deps);

    expect(res).toEqual({ status: "deleted", uid: "user-1" });
    // Data is erased BEFORE the auth account is revoked.
    expect(calls).toEqual(["recursiveDeleteUserData", "deleteAuthUser"]);
    // Both effects targeted ONLY the caller's uid.
    expect(deletedDataFor).toEqual(["user-1"]);
    expect(revokedAuthFor).toEqual(["user-1"]);
  });

  it("only ever operates on the verified caller uid", async () => {
    const { deps, deletedDataFor, revokedAuthFor } = makeHarness();

    await deleteMyDataCore({ auth: { uid: "caller-abc" } }, deps);

    expect(deletedDataFor).toEqual(["caller-abc"]);
    expect(revokedAuthFor).toEqual(["caller-abc"]);
  });

  it("does not revoke auth if the data delete fails (no orphaned active account)", async () => {
    const { deps, revokedAuthFor } = makeHarness();
    deps.recursiveDeleteUserData = async () => {
      throw new Error("firestore down");
    };

    await expect(deleteMyDataCore(authedContext, deps)).rejects.toThrow("firestore down");
    expect(revokedAuthFor).toEqual([]);
  });
});
