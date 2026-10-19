import { AiProvider, AiRequest, AiResult } from "./types";
import { providerRegistry, registerProvider, resolveProvider } from "./provider";
import { config, DEFAULT_PROVIDER_ID } from "../config";

/** Minimal in-test fake provider used to exercise the registry/resolution. */
function makeFakeProvider(id: string): AiProvider {
  return {
    id,
    async generate(_req: AiRequest): Promise<AiResult> {
      return { text: `generated:${id}` };
    },
    async *generateStream(_req: AiRequest): AsyncIterable<AiResult> {
      yield { text: `stream:${id}` };
    },
  };
}

describe("provider registry and resolveProvider", () => {
  const originalProviderId = config.aiProviderId;

  afterEach(() => {
    // Reset registry and config between tests for isolation.
    for (const key of Object.keys(providerRegistry)) {
      delete providerRegistry[key];
    }
    config.aiProviderId = originalProviderId;
  });

  it("registers a provider under its id and returns it", () => {
    const provider = makeFakeProvider("fake-a");
    expect(registerProvider(provider)).toBe(provider);
    expect(providerRegistry["fake-a"]).toBe(provider);
  });

  it("resolves the provider matching the configured id", () => {
    const configured = makeFakeProvider("configured");
    const other = makeFakeProvider("other");
    registerProvider(configured);
    registerProvider(other);
    config.aiProviderId = "configured";

    expect(resolveProvider()).toBe(configured);
  });

  it("falls back to the default provider id when the configured id is missing", () => {
    const fallback = makeFakeProvider(DEFAULT_PROVIDER_ID);
    registerProvider(fallback);
    config.aiProviderId = "nonexistent";

    expect(resolveProvider()).toBe(fallback);
  });

  it("throws when neither the configured nor default provider is registered", () => {
    config.aiProviderId = "nonexistent";
    expect(() => resolveProvider()).toThrow(/No AiProvider registered/);
  });
});
