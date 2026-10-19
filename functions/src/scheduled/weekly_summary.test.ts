import {
  DailyActivity,
  WeeklySummary,
  WeeklySummaryDeps,
  aggregateWeek,
  dateKey,
  formatIsoWeek,
  isoWeek,
  isoWeekDateKeys,
  isoWeekMonday,
  isoWeekParts,
  previousIsoWeek,
  runWeeklySummaryCore,
} from "./weekly_summary";

describe("aggregateWeek", () => {
  it("returns all-zero totals for an empty week", () => {
    expect(aggregateWeek([])).toEqual({
      timeSpentSec: 0,
      wordsLearned: 0,
      mistakesFixed: 0,
    });
  });

  it("sums each metric field-wise across the week's daily documents", () => {
    const docs: DailyActivity[] = [
      { activities: 2, timeSpentSec: 300, wordsLearned: 5, mistakesFixed: 1 },
      { activities: 1, timeSpentSec: 120, wordsLearned: 3, mistakesFixed: 4 },
      { activities: 3, timeSpentSec: 600, wordsLearned: 7, mistakesFixed: 2 },
    ];

    expect(aggregateWeek(docs)).toEqual({
      timeSpentSec: 1020,
      wordsLearned: 15,
      mistakesFixed: 7,
    });
  });

  it("treats missing, non-numeric, and negative counters as zero", () => {
    const docs: DailyActivity[] = [
      { timeSpentSec: 100 },
      {},
      { wordsLearned: 4, mistakesFixed: -5 },
      { timeSpentSec: Number.NaN, wordsLearned: 2 },
    ];

    expect(aggregateWeek(docs)).toEqual({
      timeSpentSec: 100,
      wordsLearned: 6,
      mistakesFixed: 0,
    });
  });

  it("is order-independent (aggregate matches the field-wise sum)", () => {
    const docs: DailyActivity[] = [
      { timeSpentSec: 10, wordsLearned: 1, mistakesFixed: 0 },
      { timeSpentSec: 20, wordsLearned: 2, mistakesFixed: 3 },
      { timeSpentSec: 30, wordsLearned: 0, mistakesFixed: 1 },
    ];
    const reversed = [...docs].reverse();

    expect(aggregateWeek(reversed)).toEqual(aggregateWeek(docs));
  });
});

describe("isoWeekParts / formatIsoWeek / isoWeek", () => {
  it("numbers a mid-year week and zero-pads the id", () => {
    // 2024-01-15 is a Monday in ISO week 3 of 2024.
    expect(isoWeekParts(new Date("2024-01-15T12:00:00Z"))).toEqual({ year: 2024, week: 3 });
    expect(isoWeek(new Date("2024-01-15T12:00:00Z"))).toBe("2024-W03");
  });

  it("assigns 2021-01-01 to ISO week 53 of 2020 (belongs to the prior ISO year)", () => {
    // Fri 2021-01-01 falls in the ISO week that started Mon 2020-12-28.
    expect(isoWeekParts(new Date("2021-01-01T00:00:00Z"))).toEqual({ year: 2020, week: 53 });
    expect(isoWeek(new Date("2021-01-01T00:00:00Z"))).toBe("2020-W53");
  });

  it("assigns 2023-01-01 to ISO week 52 of 2022 (Sunday belongs to prior week)", () => {
    expect(isoWeek(new Date("2023-01-01T00:00:00Z"))).toBe("2022-W52");
  });

  it("puts 2024-12-30 into ISO week 1 of 2025 (belongs to the next ISO year)", () => {
    // Mon 2024-12-30 opens ISO week 1 of 2025.
    expect(isoWeekParts(new Date("2024-12-30T00:00:00Z"))).toEqual({ year: 2025, week: 1 });
  });

  it("is stable across every day of a single ISO week", () => {
    // Mon 2024-01-15 through Sun 2024-01-21 are all ISO week 3 of 2024.
    for (let day = 15; day <= 21; day++) {
      const d = new Date(Date.UTC(2024, 0, day, 9, 30));
      expect(isoWeek(d)).toBe("2024-W03");
    }
  });

  it("formats parts with padding for single- and double-digit weeks", () => {
    expect(formatIsoWeek({ year: 2024, week: 3 })).toBe("2024-W03");
    expect(formatIsoWeek({ year: 2024, week: 42 })).toBe("2024-W42");
  });
});

describe("isoWeekMonday / dateKey / isoWeekDateKeys", () => {
  it("resolves the Monday that opens an ISO week", () => {
    expect(dateKey(isoWeekMonday({ year: 2024, week: 3 }))).toBe("2024-01-15");
    // ISO week 1 of 2025 opens on 2024-12-30.
    expect(dateKey(isoWeekMonday({ year: 2025, week: 1 }))).toBe("2024-12-30");
  });

  it("lists the seven Monday→Sunday yyyy-mm-dd keys of an ISO week", () => {
    expect(isoWeekDateKeys({ year: 2024, week: 3 })).toEqual([
      "2024-01-15",
      "2024-01-16",
      "2024-01-17",
      "2024-01-18",
      "2024-01-19",
      "2024-01-20",
      "2024-01-21",
    ]);
  });

  it("round-trips: every date key maps back to its ISO week", () => {
    const parts = { year: 2024, week: 3 };
    for (const key of isoWeekDateKeys(parts)) {
      expect(isoWeek(new Date(`${key}T12:00:00Z`))).toBe(formatIsoWeek(parts));
    }
  });
});

describe("previousIsoWeek", () => {
  it("targets the week that just completed relative to now", () => {
    // A run early Monday 2024-01-22 should aggregate ISO week 3 (Jan 15–21).
    expect(previousIsoWeek(new Date("2024-01-22T00:05:00Z"))).toEqual({ year: 2024, week: 3 });
  });
});

/** In-memory {@link WeeklySummaryDeps} recording every persisted summary. */
function makeHarness(
  now: Date,
  activityByUser: Record<string, Record<string, DailyActivity>>,
) {
  const saved: { uid: string; isoWeek: string; summary: WeeklySummary }[] = [];
  const deps: WeeklySummaryDeps = {
    async listUserIds() {
      return Object.keys(activityByUser);
    },
    async getDailyActivity(uid, dateKeys) {
      const byDate = activityByUser[uid] ?? {};
      return dateKeys.filter((k) => k in byDate).map((k) => byDate[k]);
    },
    async saveWeeklySummary(uid, week, summary) {
      saved.push({ uid, isoWeek: week, summary });
    },
    now() {
      return now;
    },
  };
  return { deps, saved };
}

describe("runWeeklySummaryCore", () => {
  it("aggregates each user's completed ISO week and writes it under that week id", async () => {
    const now = new Date("2024-01-22T00:05:00Z"); // completed week: 2024-W03
    const { deps, saved } = makeHarness(now, {
      "user-1": {
        "2024-01-15": { timeSpentSec: 300, wordsLearned: 5, mistakesFixed: 1 },
        "2024-01-18": { timeSpentSec: 200, wordsLearned: 2, mistakesFixed: 3 },
        // A day outside the target week must not be counted.
        "2024-01-22": { timeSpentSec: 999, wordsLearned: 99, mistakesFixed: 99 },
      },
      "user-2": {
        "2024-01-21": { timeSpentSec: 60, wordsLearned: 1, mistakesFixed: 0 },
      },
    });

    const result = await runWeeklySummaryCore(deps);

    expect(result).toEqual({ isoWeek: "2024-W03", usersProcessed: 2 });
    expect(saved).toEqual([
      {
        uid: "user-1",
        isoWeek: "2024-W03",
        summary: { timeSpentSec: 500, wordsLearned: 7, mistakesFixed: 4 },
      },
      {
        uid: "user-2",
        isoWeek: "2024-W03",
        summary: { timeSpentSec: 60, wordsLearned: 1, mistakesFixed: 0 },
      },
    ]);
  });

  it("writes an all-zero summary for a user with no activity that week", async () => {
    const now = new Date("2024-01-22T00:05:00Z");
    const { deps, saved } = makeHarness(now, { "quiet-user": {} });

    await runWeeklySummaryCore(deps);

    expect(saved).toEqual([
      {
        uid: "quiet-user",
        isoWeek: "2024-W03",
        summary: { timeSpentSec: 0, wordsLearned: 0, mistakesFixed: 0 },
      },
    ]);
  });

  it("processes no writes when there are no users", async () => {
    const { deps, saved } = makeHarness(new Date("2024-01-22T00:05:00Z"), {});

    const result = await runWeeklySummaryCore(deps);

    expect(result.usersProcessed).toBe(0);
    expect(saved).toEqual([]);
  });
});
