/**
 * Daemon entry point.
 *
 * Bootstrap sequence:
 *   1. Start the stdin command stream.
 *   2. Emit `daemon:ready` (proto 1) on stdout.
 *   3. Initialize the orchestrator (wires `poll:now` / `pause` / `resume`).
 *   4. Wait for the first `config` command (handshake), then configure logging
 *      with `logDir` and start the orchestrator -> `daemon:status idle`.
 *   5. Subsequent `config` commands hot-reload the orchestrator.
 *   6. `shutdown` command (or SIGTERM/SIGINT) performs a clean exit.
 *
 * The daemon runs standalone (no Tauri) — drive it by piping JSON commands to
 * stdin. Only stdout is the event channel; logs go to stderr/file.
 */
import { PROTO_VERSION } from "@pr-review/shared";
import { transport } from "./ipc/transport";
import { getLogger, configureLogging, flushLogs } from "./logging/logger";
import { onConfig, getActiveConfig } from "./config/loader";
import { Orchestrator } from "./orchestrator";

async function main(): Promise<void> {
  const log = getLogger();
  transport.startStdin();

  // (2) READY handshake — emitted before any logging file sink exists.
  await transport.ready(PROTO_VERSION);
  log.info({ proto: PROTO_VERSION }, "daemon ready");

  // (3) orchestrator
  const orchestrator = new Orchestrator(transport);
  await orchestrator.init();

  // (4)+(5) config handshake + hot-reload
  onConfig(async (cfg) => {
    const isFirst = getActiveConfig() === cfg;
    if (isFirst) {
      // Logging file sink is only available once logDir is known.
      configureLogging({ logDir: cfg.logDir, level: "info", transport });
      getLogger().info({ model: cfg.llmModel }, "starting orchestrator");
      await orchestrator.start(cfg);
    } else {
      getLogger().info({ model: cfg.llmModel }, "applying hot-reloaded config");
      await orchestrator.applyConfig(cfg);
      await transport.status(orchestrator.state);
    }
  });

  // (6) shutdown — command or signal
  const shutdown = createShutdown(orchestrator);
  transport.on("shutdown", () => {
    void shutdown("shutdown command");
  });

  log.info("awaiting config handshake on stdin");
}

function createShutdown(orchestrator: Orchestrator): (reason: string) => Promise<void> {
  let invoked = false;
  return async (reason: string) => {
    if (invoked) return;
    invoked = true;
    const log = getLogger();
    log.info({ reason }, "shutting down");
    await transport.status("idle", `offline: ${reason}`).catch(() => undefined);
    await orchestrator.stop().catch(() => undefined);
    transport.stopStdin();
    await transport.flush().catch(() => undefined);
    await flushLogs().catch(() => undefined);
    process.exit(0);
  };
}

main().catch(async (err) => {
  const message = err instanceof Error ? err.stack ?? err.message : String(err);
  // Best-effort error event before dying; transport may not be ready.
  await transport.error("fatal", message).catch(() => undefined);
  process.stderr.write(`fatal: ${message}\n`);
  process.exit(1);
});

// Graceful signal handling (e.g. Tauri killing the sidecar).
for (const sig of ["SIGTERM", "SIGINT"] as const) {
  process.on(sig, () => {
    process.stderr.write(`received ${sig}\n`);
    // Flush in-flight event emits + pending log writes to disk, then exit.
    Promise.all([transport.flush(), flushLogs()])
      .catch(() => undefined)
      .finally(() => process.exit(0));
  });
}

// Unhandled rejection safety net (Node 22 default would terminate).
process.on("unhandledRejection", (reason) => {
  const msg = reason instanceof Error ? reason.message : String(reason);
  try {
    getLogger().error({ code: "unhandled_rejection" }, msg);
  } catch {
    console.error("[unhandledRejection]", msg);
  }
});
