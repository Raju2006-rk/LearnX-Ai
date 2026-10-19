import {
  DEFAULT_TIER_LIMITS,
  USAGE_FIELD_BY_KIND,
  UsageKind,
  dayKey,
} from "./usage";

describe("usage seams — pure helpers", () => {
  it("formats the UTC calendar-day key as yyyy-mm-dd", () => {
    const key = dayKey(new Date("2024-03-07T23:45:00Z"));
    expect(key).toBe("2024-03-07");
  });

  it("uses the current date by default and matches the yyyy-mm-dd shape", () => {
    expect(dayKey()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it("maps every metered kind to its distinct usage-doc field", () => {
    expect(USAGE_FIELD_BY_KIND).toEqual({
      chat: "chatMessages",
      lessonPersonalization: "lessonPersonalizations",
      placementQuestion: "placementGenerations",
    });
    const fields = Object.values(USAGE_FIELD_BY_KIND);
    expect(new Set(fields).size).toBe(fields.length); // no collisions
  });

  it("defines a limit for every metered kind on both tiers", () => {
    const kinds: UsageKind[] = ["chat", "lessonPersonalization", "placementQuestion"];
    for (const kind of kinds) {
      expect(typeof DEFAULT_TIER_LIMITS.free[kind]).toBe("number");
      // Premium is effectively unmetered but must never be below free.
      expect(DEFAULT_TIER_LIMITS.premium[kind]).toBeGreaterThanOrEqual(
        DEFAULT_TIER_LIMITS.free[kind],
      );
    }
  });
});
