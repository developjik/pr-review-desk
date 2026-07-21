/**
 * Config handshake + hot-reload.
 *
 * The host delivers configuration by sending `config` commands on stdin. The
 * loader:
 *   1. subscribes to the transport's `config` command,
 *   2. validates each payload into a frozen {@link Config} snapshot,
 *   3. fans the snapshot out to registered handlers, strictly serialized so
 *      every handler observes a consistent per-cycle snapshot.
 *
 * Serialization model: one in-flight update at a time (`cycle`). Each cycle
 * owns its own resolved snapshot; handlers never see a partially-applied state.
 */
import type { ConfigPayload, DaemonCommandName } from "@pr-review/shared";
import { transport } from "../ipc/transport";
import { getLogger } from "../logging/logger";
import { parseConfig, type Config } from "./schema";

export type ConfigHandler = (config: Config) => void | Promise<void>;

const handlers = new Set<ConfigHandler>();
let active: Config | null = null;
/** Serializes config updates so handlers always see one consistent snapshot. */
let cycle: Promise<Config | null> = Promise.resolve(active);

/**
 * Register a handler invoked for every accepted config snapshot (initial +
 * hot-reloads). Returns an unsubscribe function.
 */
export function onConfig(handler: ConfigHandler): () => void {
  handlers.add(handler);
  return () => handlers.delete(handler);
}

/** The most recently accepted snapshot, or null before the first config. */
export function getActiveConfig(): Config | null {
  return active;
}

// Wire the transport -> loader pipeline exactly once at import time.
const CONFIG_CMD: DaemonCommandName = "config";
transport.on(CONFIG_CMD, (cmd) => {
  cycle = cycle
    .then(async () => applyConfig(cmd.config))
    .catch(async (err) => {
      const message = err instanceof Error ? err.message : String(err);
      getLogger().error({ code: "config_invalid" }, message);
      await transport.error("config_invalid", message);
      return active;
    });
});

async function applyConfig(raw: ConfigPayload): Promise<Config> {
  const next = parseConfig(raw); // throws ZodError on bad input
  const prev = active;
  active = next;
  for (const handler of [...handlers]) {
    try {
      await handler(next);
    } catch (err) {
      getLogger().error(
        { code: "config_handler_error" },
        err instanceof Error ? err.message : String(err),
      );
    }
  }
  if (prev === null) {
    getLogger().info({ model: next.llmModel }, "config applied (initial handshake)");
  } else {
    getLogger().info("config hot-reloaded");
  }
  return next;
}
