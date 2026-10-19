/**
 * Server-side configuration for the AI_Proxy.
 *
 * Provider selection is config-driven so swapping the AI provider is a
 * server-only change with no client impact. (Req 11.2)
 */

/** Identifier of the default provider used when none is configured. */
export const DEFAULT_PROVIDER_ID = "gemini-1.5";

/** Identifier of the default moderator used when none is configured. */
export const DEFAULT_MODERATOR_ID = "keyword-v1";

export interface AppConfig {
  /** Selects which registered {@link AiProvider} the proxy resolves. */
  aiProviderId: string;
  /** Selects which registered moderator the proxy resolves. */
  moderatorId: string;
}

/**
 * Reads configuration from the environment, falling back to defaults.
 * `AI_PROVIDER_ID` selects an alternate provider and `MODERATOR_ID` selects an
 * alternate moderator without redeploying code (e.g. for tests or a
 * provider/classifier migration).
 */
export const config: AppConfig = {
  aiProviderId: process.env.AI_PROVIDER_ID ?? DEFAULT_PROVIDER_ID,
  moderatorId: process.env.MODERATOR_ID ?? DEFAULT_MODERATOR_ID,
};
