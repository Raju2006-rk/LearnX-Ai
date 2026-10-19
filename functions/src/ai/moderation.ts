/**
 * Content moderation for the AI_Proxy.
 *
 * Moderation runs as a distinct, swappable step on BOTH the learner input and
 * the AI output for every chat and personalization call. On an unsafe verdict
 * the flagged content is withheld and a safe substitute/refusal is returned so
 * the unsafe content never reaches the client or persistence.
 * (Req 5.1, 5.2, 10.4)
 *
 * The moderator is an interface with a config-driven default implementation,
 * mirroring the provider abstraction: swapping in a provider safety API or a
 * dedicated classifier is a server-only change with no client impact.
 */
import { config, DEFAULT_MODERATOR_ID } from "../config";

/** Direction of the content being moderated relative to the AI provider. */
export type ModerationDirection = "input" | "output";

/** Result of classifying a single piece of content. */
export interface ModerationVerdict {
  /** True when the content is safe/age-appropriate for all ages. */
  safe: boolean;
  /** Categories that caused an unsafe verdict (empty/absent when safe). */
  categories?: string[];
}

/**
 * Swappable moderation contract. The default implementation is a lightweight
 * keyword classifier; production may register a provider safety API or a
 * dedicated ML classifier under a different id. (Req 5.1)
 */
export interface Moderator {
  /** Stable moderator identifier, e.g. "keyword-v1". */
  readonly id: string;
  /** Classifies content as safe or unsafe. */
  moderate(content: string): Promise<ModerationVerdict>;
}

/**
 * Registry of available moderators keyed by their `id`. Moderator modules
 * register into this map at import time via {@link registerModerator}.
 */
export const moderatorRegistry: Record<string, Moderator> = {};

/**
 * Registers a moderator under its `id`. Returns the moderator for convenient
 * chaining at module scope.
 */
export function registerModerator(moderator: Moderator): Moderator {
  moderatorRegistry[moderator.id] = moderator;
  return moderator;
}

/**
 * Resolves the active moderator using config-driven selection. Prefers the
 * configured `moderatorId`, then the default moderator id. Throws if no
 * matching moderator has been registered so misconfiguration fails loudly
 * rather than silently letting unsafe content through.
 */
export function resolveModerator(): Moderator {
  const selected = moderatorRegistry[config.moderatorId];
  if (selected) {
    return selected;
  }
  const fallback = moderatorRegistry[DEFAULT_MODERATOR_ID];
  if (fallback) {
    return fallback;
  }
  throw new Error(
    `No Moderator registered for id "${config.moderatorId}" ` +
      `and no default moderator "${DEFAULT_MODERATOR_ID}" is available.`,
  );
}

/**
 * Unsafe-content categories detected by the default keyword moderator. Each
 * pattern is matched case-insensitively against the content.
 */
const UNSAFE_PATTERNS: ReadonlyArray<{ category: string; pattern: RegExp }> = [
  { category: "violence", pattern: /\b(kill|murder|behead|massacre|shoot(?:ing)?)\b/i },
  { category: "weapons", pattern: /\b(bomb|explosive|grenade|firearm)\b/i },
  { category: "self_harm", pattern: /\b(suicide|self[-\s]?harm|kill myself)\b/i },
  { category: "sexual", pattern: /\b(porn|sexually explicit|nude)\b/i },
  { category: "hate", pattern: /\b(racial slur|ethnic cleansing)\b/i },
];

/**
 * Default moderator: a deterministic keyword classifier. It is intentionally
 * conservative and simple so it is fast on the hot path and easy to test;
 * production deployments swap in a richer classifier via the registry.
 */
export class KeywordModerator implements Moderator {
  readonly id = DEFAULT_MODERATOR_ID;

  async moderate(content: string): Promise<ModerationVerdict> {
    const categories: string[] = [];
    for (const { category, pattern } of UNSAFE_PATTERNS) {
      if (pattern.test(content)) {
        categories.push(category);
      }
    }
    return categories.length > 0 ? { safe: false, categories } : { safe: true };
  }
}

// Register the default moderator at import time so `resolveModerator()` works
// out of the box.
registerModerator(new KeywordModerator());

/** Safe substitute shown when a learner's input is withheld. */
export const SAFE_INPUT_REFUSAL =
  "I can't help with that. Let's keep things friendly and focused on learning English.";

/** Safe substitute shown when an AI reply is withheld. */
export const SAFE_OUTPUT_REFUSAL =
  "Sorry, I can't share a response to that. Let's try a different English question.";

/**
 * Outcome of applying moderation to a piece of content. When `safe`, the
 * original `content` is passed through unchanged. When unsafe, the flagged
 * `content` is withheld (absent) and a `safeMessage` substitute is provided
 * along with the offending `categories`. (Req 5.2, 10.4)
 */
export interface ModerationOutcome {
  safe: boolean;
  /** Original content, present ONLY when the verdict is safe. */
  content?: string;
  /** Safe substitute/refusal, present ONLY when the verdict is unsafe. */
  safeMessage?: string;
  /** Categories that triggered the unsafe verdict (present when unsafe). */
  categories?: string[];
}

/**
 * Applies the moderation step to `content` for the given `direction`. This is
 * the function callers use on both input and output: on a safe verdict it
 * returns the original content; on an unsafe verdict it withholds the flagged
 * content and returns a direction-appropriate safe substitute so unsafe
 * content is never passed through. (Req 5.1, 5.2, 10.4)
 */
export async function moderateContent(
  content: string,
  direction: ModerationDirection,
  moderator: Moderator = resolveModerator(),
): Promise<ModerationOutcome> {
  const verdict = await moderator.moderate(content);
  if (verdict.safe) {
    return { safe: true, content };
  }
  return {
    safe: false,
    safeMessage: direction === "input" ? SAFE_INPUT_REFUSAL : SAFE_OUTPUT_REFUSAL,
    categories: verdict.categories ?? [],
  };
}
