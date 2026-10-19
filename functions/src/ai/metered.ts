/**
 * Metered AI middleware for the AI_Proxy.
 *
 * `meteredAi` enforces the shared gate order that every metered AI function
 * (chat, lesson personalization, placement generation) runs through:
 *
 *   require auth
 *     → read tier
 *     → read today's usage
 *     → limit check      (provider NOT called on limit)
 *     → input moderation
 *     → provider call
 *     → output moderation
 *     → increment usage  (only on success)
 *
 * The counter is incremented ONLY after a successful, moderated provider call,
 * so a limit-reached request never invokes the provider and never mutates the
 * counter, and a refused request likewise leaves the counter untouched.
 * (Req 4.6, 5.1, 5.2, 11.3, 11.4)
 *
 * All external effects (auth, tier/usage reads, usage writes, moderation,
 * provider resolution) are injected via {@link MeteredAiDeps} so the gate order
 * is unit-testable with in-memory fakes. Production callers use the default
 * deps, which wire the Admin SDK + Remote Config + the configured moderator and
 * provider.
 */
import { AiProvider, CefrLevel, NativeLanguage } from "./types";
import {
  ModerationOutcome,
  SAFE_INPUT_REFUSAL,
  SAFE_OUTPUT_REFUSAL,
  moderateContent,
} from "./moderation";
import { resolveProvider } from "./provider";
import {
  AccountTier,
  TierLimits,
  UsageKind,
  getLimits,
  getTodayUsage,
  getUserTier,
  incrementUsage,
} from "./usage";

/**
 * Authenticated request context passed to the middleware. `auth` carries the
 * verified `uid` (populated by the callable runtime); `input` is the learner
 * text moderated before the provider is called.
 */
export interface MeteredAiContext {
  /** Verified auth payload; `uid` is present for authenticated callers. */
  auth?: { uid: string } | null;
  /** Raw learner input to moderate before invoking the provider. */
  input: string;
  /** Learner native language, forwarded to the handler for provider requests. */
  nativeLanguage?: NativeLanguage;
  /** Learner CEFR level, forwarded to the handler for provider requests. */
  cefrLevel?: CefrLevel;
}

/**
 * Result a {@link MeteredHandler} returns: the domain `result` to hand back to
 * the caller plus the `outputText` that must pass output moderation. Keeping
 * the moderated text explicit lets the middleware moderate provider output
 * regardless of the concrete result shape.
 */
export interface HandlerResult<T> {
  /** The domain result returned to the caller on success. */
  result: T;
  /** Provider output text subject to output moderation. */
  outputText: string;
}

/** Handler that performs the actual provider call for a metered function. */
export type MeteredHandler<T> = (provider: AiProvider) => Promise<HandlerResult<T>>;

/** Injectable seams the middleware depends on. */
export interface MeteredAiDeps {
  getUserTier(uid: string): Promise<AccountTier>;
  getLimits(tier: AccountTier): Promise<TierLimits>;
  getTodayUsage(uid: string, kind: UsageKind): Promise<number>;
  incrementUsage(uid: string, kind: UsageKind): Promise<void>;
  resolveProvider(): AiProvider;
  moderate(content: string, direction: "input" | "output"): Promise<ModerationOutcome>;
}

/** Default deps wiring Admin SDK usage, Remote Config limits, and moderation. */
export const defaultMeteredAiDeps: MeteredAiDeps = {
  getUserTier,
  getLimits,
  getTodayUsage,
  incrementUsage,
  resolveProvider,
  moderate: moderateContent,
};

/** Discriminated response returned by {@link meteredAi}. */
export type MeteredAiResponse<T> =
  | { status: "ok"; result: T }
  | { status: "limit_reached"; limit: number }
  | { status: "refusal"; safeMessage: string };

/** Thrown when a metered call is made without a verified authenticated uid. */
export class AuthRequiredError extends Error {
  constructor(message = "Authentication is required for this action.") {
    super(message);
    this.name = "AuthRequiredError";
  }
}

/**
 * Extracts the verified `uid` from the context or throws
 * {@link AuthRequiredError}. Callable wrappers convert this into an
 * `unauthenticated` error for the client.
 */
function requireAuth(context: MeteredAiContext): string {
  const uid = context.auth?.uid;
  if (!uid) {
    throw new AuthRequiredError();
  }
  return uid;
}

/**
 * Runs the metered AI gate order for `kind`, delegating the provider call to
 * `handler`. See the module doc for the exact ordering and invariants.
 */
export async function meteredAi<T>(
  context: MeteredAiContext,
  kind: UsageKind,
  handler: MeteredHandler<T>,
  deps: MeteredAiDeps = defaultMeteredAiDeps,
): Promise<MeteredAiResponse<T>> {
  // 1. require auth
  const uid = requireAuth(context);

  // 2. read tier
  const tier = await deps.getUserTier(uid);

  // 3. read today's usage + resolve the applicable limit
  const limit = (await deps.getLimits(tier))[kind];
  const used = await deps.getTodayUsage(uid, kind);

  // 4. limit check — provider is NOT called and the counter is NOT touched.
  if (used >= limit) {
    return { status: "limit_reached", limit };
  }

  // 5. input moderation — refuse before any provider call on unsafe input.
  const inputCheck = await deps.moderate(context.input, "input");
  if (!inputCheck.safe) {
    return { status: "refusal", safeMessage: inputCheck.safeMessage ?? SAFE_INPUT_REFUSAL };
  }

  // 6. provider call
  const { result, outputText } = await handler(deps.resolveProvider());

  // 7. output moderation — withhold unsafe output; counter stays untouched.
  const outputCheck = await deps.moderate(outputText, "output");
  if (!outputCheck.safe) {
    return { status: "refusal", safeMessage: outputCheck.safeMessage ?? SAFE_OUTPUT_REFUSAL };
  }

  // 8. increment usage — ONLY after a successful, moderated provider call.
  await deps.incrementUsage(uid, kind);
  return { status: "ok", result };
}
