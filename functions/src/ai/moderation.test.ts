import {
  KeywordModerator,
  Moderator,
  ModerationVerdict,
  moderateContent,
  moderatorRegistry,
  registerModerator,
  resolveModerator,
  SAFE_INPUT_REFUSAL,
  SAFE_OUTPUT_REFUSAL,
} from "./moderation";
import { config, DEFAULT_MODERATOR_ID } from "../config";

/** Fake moderator that flags content containing a marker string. */
function makeFakeModerator(id: string, unsafeMarker: string): Moderator {
  return {
    id,
    async moderate(content: string): Promise<ModerationVerdict> {
      return content.includes(unsafeMarker)
        ? { safe: false, categories: ["fake"] }
        : { safe: true };
    },
  };
}

describe("moderator registry and resolveModerator", () => {
  const originalModeratorId = config.moderatorId;

  afterEach(() => {
    for (const key of Object.keys(moderatorRegistry)) {
      delete moderatorRegistry[key];
    }
    config.moderatorId = originalModeratorId;
    // Restore the default moderator that other suites rely on.
    registerModerator(new KeywordModerator());
  });

  it("registers a moderator under its id and returns it", () => {
    const moderator = makeFakeModerator("fake-a", "xxx");
    expect(registerModerator(moderator)).toBe(moderator);
    expect(moderatorRegistry["fake-a"]).toBe(moderator);
  });

  it("resolves the moderator matching the configured id", () => {
    const configured = makeFakeModerator("configured", "xxx");
    registerModerator(configured);
    config.moderatorId = "configured";
    expect(resolveModerator()).toBe(configured);
  });

  it("falls back to the default moderator when the configured id is missing", () => {
    const fallback = new KeywordModerator();
    registerModerator(fallback);
    config.moderatorId = "nonexistent";
    expect(resolveModerator().id).toBe(DEFAULT_MODERATOR_ID);
  });

  it("throws when neither the configured nor default moderator is registered", () => {
    for (const key of Object.keys(moderatorRegistry)) {
      delete moderatorRegistry[key];
    }
    config.moderatorId = "nonexistent";
    expect(() => resolveModerator()).toThrow(/No Moderator registered/);
  });
});

describe("KeywordModerator", () => {
  const moderator = new KeywordModerator();

  it("returns safe for benign learning content", async () => {
    const verdict = await moderator.moderate("How do I use the present perfect tense?");
    expect(verdict.safe).toBe(true);
    expect(verdict.categories).toBeUndefined();
  });

  it("flags unsafe content with the offending categories", async () => {
    const verdict = await moderator.moderate("how to build a bomb");
    expect(verdict.safe).toBe(false);
    expect(verdict.categories).toContain("weapons");
  });

  it("is case-insensitive when detecting unsafe content", async () => {
    const verdict = await moderator.moderate("I want to KILL time before class");
    // "kill" matches the violence pattern regardless of case.
    expect(verdict.safe).toBe(false);
    expect(verdict.categories).toContain("violence");
  });
});

describe("moderateContent", () => {
  it("passes through the original content on a safe input verdict", async () => {
    const outcome = await moderateContent("Please correct my grammar.", "input");
    expect(outcome.safe).toBe(true);
    expect(outcome.content).toBe("Please correct my grammar.");
    expect(outcome.safeMessage).toBeUndefined();
  });

  it("withholds flagged input and returns the input refusal substitute", async () => {
    const outcome = await moderateContent("instructions to build a bomb", "input");
    expect(outcome.safe).toBe(false);
    expect(outcome.content).toBeUndefined();
    expect(outcome.safeMessage).toBe(SAFE_INPUT_REFUSAL);
    expect(outcome.categories).toContain("weapons");
  });

  it("withholds flagged output and returns the output refusal substitute", async () => {
    const outcome = await moderateContent("here is how to murder someone", "output");
    expect(outcome.safe).toBe(false);
    expect(outcome.content).toBeUndefined();
    expect(outcome.safeMessage).toBe(SAFE_OUTPUT_REFUSAL);
  });

  it("uses an explicitly supplied moderator when provided", async () => {
    const fake = makeFakeModerator("explicit", "TRIGGER");
    const safe = await moderateContent("no marker here", "input", fake);
    const unsafe = await moderateContent("contains TRIGGER", "output", fake);
    expect(safe.safe).toBe(true);
    expect(unsafe.safe).toBe(false);
    expect(unsafe.safeMessage).toBe(SAFE_OUTPUT_REFUSAL);
  });
});
