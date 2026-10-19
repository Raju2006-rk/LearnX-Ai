/**
 * Provider registry and config-driven resolution for the AI_Proxy.
 *
 * `resolveProvider()` selects an {@link AiProvider} by id from Remote/env
 * config, falling back to the default provider id. Concrete providers (e.g.
 * `GeminiProvider`) register themselves into {@link providerRegistry} so that
 * swapping providers is a server-only change with no client impact.
 * (Req 11.1, 11.2)
 */
import { config, DEFAULT_PROVIDER_ID } from "../config";
import { AiProvider } from "./types";

/**
 * Registry of available providers keyed by their `id`. Provider modules
 * register into this map at import time via {@link registerProvider}.
 */
export const providerRegistry: Record<string, AiProvider> = {};

/**
 * Registers a provider under its `id`. Returns the provider for convenient
 * chaining at module scope.
 */
export function registerProvider(provider: AiProvider): AiProvider {
  providerRegistry[provider.id] = provider;
  return provider;
}

/**
 * Resolves the active provider using config-driven selection. Prefers the
 * configured `aiProviderId`, then the default provider id. Throws if no
 * matching provider has been registered so misconfiguration fails loudly
 * rather than silently degrading.
 */
export function resolveProvider(): AiProvider {
  const selected = providerRegistry[config.aiProviderId];
  if (selected) {
    return selected;
  }
  const fallback = providerRegistry[DEFAULT_PROVIDER_ID];
  if (fallback) {
    return fallback;
  }
  throw new Error(
    `No AiProvider registered for id "${config.aiProviderId}" ` +
      `and no default provider "${DEFAULT_PROVIDER_ID}" is available.`,
  );
}
