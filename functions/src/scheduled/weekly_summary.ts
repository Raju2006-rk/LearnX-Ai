/**
 * Scheduled weekly-summary function.
 *
 * Once a week a Cloud Scheduler trigger fans out over every user and rolls the
 * just-completed ISO week's `users/{uid}/progress/main/dailyActivity/{yyyy-mm-dd}`
 * documents up into a single `users/{uid}/weeklySummaries/{isoWeek}` document
 * holding `{ timeSpentSec, wordsLearned, mistakesFixed, generatedAt }`. Running
 * this server-side keeps the summary consistent and independent of whether any
 * client happens to be online at the week boundary; the client can still derive
 * a live current-week view straight from `dailyActivity`. (Req 7.4)
 *
 * The aggregation logic is extracted into pure, side-effect-free helpers
 * (`aggregateWeek`, the ISO-week date math) so the arithmetic behind
 * "the summary equals the sum of the underlying daily events" (Property 18) is
 * unit-testable without any Firestore, Admin SDK, or scheduler wiring. Every
 * external effect (listing users, reading daily activity, writing the summary,
 * and reading the clock) is injected via {@link WeeklySummaryDeps}. The default
 * deps load firebase-admin behind a lazy `require` — matching the placement.ts /
 * delete_my_data.ts convention — so this module imports cleanly under test
 * without the Admin SDK initialized or credentials present.
 */

/** One `dailyActivity/{yyyy-mm-dd}` document. All counters are optional. */
export interface DailyActivity {
  /** Number of qualifying activities that day (not part of the summary). */
  activities?: number;
  /** Seconds spent learning that day. */
  timeSpentSec?: number;
  /** Words learned that day. */
  wordsLearned?: number;
  /** Mistakes fixed that day. */
  mistakesFixed?: number;
}

/** Aggregated weekly totals persisted to `weeklySummaries/{isoWeek}`. */
export interface WeeklySummary {
  timeSpentSec: number;
  wordsLearned: number;
  mistakesFixed: number;
}

/** ISO-8601 week identity: the ISO week-numbering year plus the week number. */
export interface IsoWeekParts {
  /** ISO week-numbering year (may differ from the calendar year near Jan 1). */
  year: number;
  /** ISO week number, 1–53. */
  week: number;
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Coerces a possibly-missing counter into a non-negative finite number. Missing,
 * non-numeric, NaN, and negative values fold to 0 so a single malformed daily
 * document can never corrupt (or negate) the weekly totals.
 */
function counter(value: number | undefined): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return 0;
  }
  return value;
}

/**
 * Pure aggregation core: sums `timeSpentSec`, `wordsLearned`, and
 * `mistakesFixed` across the week's daily-activity documents. The order of the
 * inputs does not matter and missing counters are treated as 0, so the summary
 * for a set of days always equals the field-wise sum of those days. (Req 7.4,
 * Property 18)
 */
export function aggregateWeek(docs: readonly DailyActivity[]): WeeklySummary {
  return docs.reduce<WeeklySummary>(
    (acc, doc) => ({
      timeSpentSec: acc.timeSpentSec + counter(doc.timeSpentSec),
      wordsLearned: acc.wordsLearned + counter(doc.wordsLearned),
      mistakesFixed: acc.mistakesFixed + counter(doc.mistakesFixed),
    }),
    { timeSpentSec: 0, wordsLearned: 0, mistakesFixed: 0 },
  );
}

/**
 * Computes the ISO-8601 week-numbering year and week number for a date. ISO
 * weeks start on Monday and week 1 is the week containing the year's first
 * Thursday, which is why the year here can differ from the calendar year for
 * dates in late December or early January. All math is done in UTC so the
 * result is independent of the server's local timezone.
 */
export function isoWeekParts(date: Date): IsoWeekParts {
  // Work on a UTC-midnight copy of the date.
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  // Monday = 0 … Sunday = 6.
  const dayNum = (d.getUTCDay() + 6) % 7;
  // Shift to the Thursday of this week; that Thursday's year is the ISO year.
  d.setUTCDate(d.getUTCDate() - dayNum + 3);
  const isoYear = d.getUTCFullYear();
  // First Thursday of the ISO year.
  const firstThursday = new Date(Date.UTC(isoYear, 0, 4));
  const firstThursdayDayNum = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstThursdayDayNum + 3);
  const week = 1 + Math.round((d.getTime() - firstThursday.getTime()) / (7 * MS_PER_DAY));
  return { year: isoYear, week };
}

/** Formats ISO week parts as the `YYYY-Www` document id, e.g. `2024-W03`. */
export function formatIsoWeek(parts: IsoWeekParts): string {
  const week = parts.week < 10 ? `0${parts.week}` : `${parts.week}`;
  return `${parts.year}-W${week}`;
}

/** Convenience: the `YYYY-Www` ISO-week id a date falls in. */
export function isoWeek(date: Date): string {
  return formatIsoWeek(isoWeekParts(date));
}

/** The Monday (UTC midnight) that opens a given ISO week. */
export function isoWeekMonday(parts: IsoWeekParts): Date {
  // Jan 4 is always in ISO week 1; walk back to that week's Monday, then
  // forward whole weeks to reach the requested week's Monday.
  const jan4 = new Date(Date.UTC(parts.year, 0, 4));
  const jan4DayNum = (jan4.getUTCDay() + 6) % 7;
  const week1Monday = new Date(jan4);
  week1Monday.setUTCDate(jan4.getUTCDate() - jan4DayNum);
  const monday = new Date(week1Monday);
  monday.setUTCDate(week1Monday.getUTCDate() + (parts.week - 1) * 7);
  return monday;
}

/** Pads a 1–2 digit number to a 2-char string. */
function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/** Formats a date as the `yyyy-mm-dd` daily-activity document id (UTC). */
export function dateKey(date: Date): string {
  return `${date.getUTCFullYear()}-${pad2(date.getUTCMonth() + 1)}-${pad2(date.getUTCDate())}`;
}

/**
 * The seven `yyyy-mm-dd` daily-activity document ids (Monday → Sunday) that
 * belong to an ISO week.
 */
export function isoWeekDateKeys(parts: IsoWeekParts): string[] {
  const monday = isoWeekMonday(parts);
  const keys: string[] = [];
  for (let i = 0; i < 7; i++) {
    keys.push(dateKey(new Date(monday.getTime() + i * MS_PER_DAY)));
  }
  return keys;
}

/**
 * The ISO week that has just completed relative to `now`. The scheduled run
 * fires at a week boundary, so subtracting seven days lands squarely in the
 * previous ISO week regardless of the exact trigger time. (Req 7.4)
 */
export function previousIsoWeek(now: Date): IsoWeekParts {
  return isoWeekParts(new Date(now.getTime() - 7 * MS_PER_DAY));
}

/** Injectable seams for {@link runWeeklySummaryCore}. */
export interface WeeklySummaryDeps {
  /** Every user id whose activity should be rolled up. */
  listUserIds(): Promise<string[]>;
  /**
   * The daily-activity documents that exist for `uid` among `dateKeys`. Missing
   * days are simply omitted; the aggregation treats an absent day as zero.
   */
  getDailyActivity(uid: string, dateKeys: string[]): Promise<DailyActivity[]>;
  /** Persists the aggregated summary to `weeklySummaries/{isoWeek}`. */
  saveWeeklySummary(uid: string, isoWeek: string, summary: WeeklySummary): Promise<void>;
  /** Injectable clock so the target week is deterministic under test. */
  now(): Date;
}

/** Outcome of a weekly-summary run, useful for logging and tests. */
export interface WeeklySummaryRunResult {
  /** The ISO week (`YYYY-Www`) that was aggregated. */
  isoWeek: string;
  /** How many users were processed. */
  usersProcessed: number;
}

/**
 * Core weekly-summary flow: determine the just-completed ISO week, then for
 * every user read that week's daily activity, aggregate it, and write the
 * summary. Kept free of any Admin SDK / scheduler types so it runs under unit
 * tests with in-memory deps. (Req 7.4)
 */
export async function runWeeklySummaryCore(
  deps: WeeklySummaryDeps,
): Promise<WeeklySummaryRunResult> {
  const parts = previousIsoWeek(deps.now());
  const week = formatIsoWeek(parts);
  const dateKeys = isoWeekDateKeys(parts);

  const uids = await deps.listUserIds();
  for (const uid of uids) {
    const docs = await deps.getDailyActivity(uid, dateKeys);
    const summary = aggregateWeek(docs);
    await deps.saveWeeklySummary(uid, week, summary);
  }

  return { isoWeek: week, usersProcessed: uids.length };
}

/**
 * Lazily resolves an initialized Admin SDK instance. `require` happens at call
 * time (never at module load) so the core logic and its helpers can be
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
 * Default deps over the Admin SDK. Users are enumerated from the `users`
 * collection; each day's activity is read from the per-user
 * `progress/main/dailyActivity` subcollection; the summary is written with a
 * server timestamp so `generatedAt` reflects the actual run time regardless of
 * the injected clock used for week selection.
 */
export const defaultWeeklySummaryDeps: WeeklySummaryDeps = {
  async listUserIds(): Promise<string[]> {
    const db = requireAdmin().firestore();
    const snap = await db.collection("users").get();
    return snap.docs.map((doc) => doc.id);
  },
  async getDailyActivity(uid: string, dateKeys: string[]): Promise<DailyActivity[]> {
    const db = requireAdmin().firestore();
    const activityCol = db
      .collection("users")
      .doc(uid)
      .collection("progress")
      .doc("main")
      .collection("dailyActivity");
    const snaps = await Promise.all(dateKeys.map((key) => activityCol.doc(key).get()));
    const docs: DailyActivity[] = [];
    for (const snap of snaps) {
      if (snap.exists) {
        docs.push((snap.data() ?? {}) as DailyActivity);
      }
    }
    return docs;
  },
  async saveWeeklySummary(uid: string, week: string, summary: WeeklySummary): Promise<void> {
    const admin = requireAdmin();
    const db = admin.firestore();
    await db
      .collection("users")
      .doc(uid)
      .collection("weeklySummaries")
      .doc(week)
      .set({ ...summary, generatedAt: admin.firestore.FieldValue.serverTimestamp() });
  },
  now(): Date {
    return new Date();
  },
};

/**
 * The `generateWeeklySummaries` scheduled function. Runs every Monday at
 * 00:00 UTC, rolling up the just-completed ISO week for every user via
 * {@link runWeeklySummaryCore} with the default (Admin SDK) deps. (Req 7.4)
 */
// eslint-disable-next-line @typescript-eslint/no-require-imports, @typescript-eslint/no-var-requires
const { onSchedule } = require("firebase-functions/v2/scheduler");
export const generateWeeklySummaries = onSchedule(
  { schedule: "every monday 00:00", timeZone: "Etc/UTC" },
  async () => {
    await runWeeklySummaryCore(defaultWeeklySummaryDeps);
  },
);

// --- Minimal structural types mirroring the Admin SDK surface we consume. ---
interface DocumentSnapshotLike {
  id: string;
  exists: boolean;
  data(): Record<string, unknown> | undefined;
}
interface QuerySnapshotLike {
  docs: DocumentSnapshotLike[];
}
interface DocumentRefLike {
  get(): Promise<DocumentSnapshotLike>;
  set(data: Record<string, unknown>): Promise<unknown>;
  collection(path: string): CollectionRefLike;
}
interface CollectionRefLike {
  doc(path: string): DocumentRefLike;
  get(): Promise<QuerySnapshotLike>;
}
interface FirestoreLike {
  collection(path: string): CollectionRefLike;
}
interface FirestoreStatic {
  FieldValue: { serverTimestamp(): unknown };
}
interface AdminLike {
  apps: unknown[];
  initializeApp(): void;
  firestore: (() => FirestoreLike) & FirestoreStatic;
}
