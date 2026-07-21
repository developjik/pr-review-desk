/**
 * Single transport channel for the daemon.
 *
 * Invariants:
 *  - ALL daemon stdout is produced here (JSON-line events). No other module may
 *    write to process.stdout. Logs go to stderr / file (see `logging/logger`).
 *  - stdin is read line-by-line; each line is one command, dispatched to typed
 *    subscribers. Malformed input becomes a `daemon:error` event, never a throw.
 *  - Emits are serialized through a promise chain so concurrent callers cannot
 *    interleave bytes on stdout.
 */
import { createInterface, type Interface as ReadlineInterface } from "node:readline";
import type {
  CommandOf,
  DaemonCommand,
  DaemonCommandName,
  DaemonEvent,
  DaemonState,
  LogLevel,
  PROTO_VERSION,
} from "@pr-review/shared";

type AnyCommand = DaemonCommand;

type CommandListener<N extends DaemonCommandName> = (
  cmd: CommandOf<N>,
) => void | Promise<void>;

export class Transport {
  /** Serializes stdout writes so JSON lines never interleave. */
  private writeChain: Promise<void> = Promise.resolve();
  /** stdout has been closed by the parent (EPIPE) — stop accepting emits. */
  private closed = false;

  private readonly listeners: Partial<
    Record<DaemonCommandName, Set<(cmd: AnyCommand) => void>>
  > = {};

  private readline: ReadlineInterface | null = null;

  // ---------------------------------------------------------------- stdout ---

  /** Emit a fully-formed event on stdout (serialized). */
  emit(event: DaemonEvent): Promise<void> {
    if (this.closed) return Promise.resolve();
    this.writeChain = this.writeChain
      .then(() => this.writeLine(event))
      .catch(() => {
        /* swallow; the chain must not break on a single bad write */
      });
    return this.writeChain;
  }

  /** Flush all pending stdout writes. Call before `process.exit`. */
  flush(): Promise<void> {
    return this.writeChain;
  }

  // -- typed convenience wrappers (keep call-sites terse & checked) ----------

  ready(proto: typeof PROTO_VERSION): Promise<void> {
    return this.emit({ type: "event", event: "daemon:ready", proto });
  }

  status(state: DaemonState, msg?: string): Promise<void> {
    return msg === undefined
      ? this.emit({ type: "event", event: "daemon:status", state })
      : this.emit({ type: "event", event: "daemon:status", state, msg });
  }

  log(level: LogLevel, msg: string): Promise<void> {
    return this.emit({ type: "event", event: "daemon:log", level, msg });
  }

  error(code: string, err: string): Promise<void> {
    return this.emit({ type: "event", event: "daemon:error", code, err });
  }

  // ----------------------------------------------------------------- stdin ---

  /** Begin consuming newline-delimited commands from stdin. Idempotent. */
  startStdin(): void {
    if (this.readline) return;
    this.readline = createInterface({
      input: process.stdin,
      terminal: false,
      crlfDelay: Infinity,
    });
    this.readline.on("line", (line) => this.handleLine(line));
    this.readline.on("close", () => {
      /* parent closed stdin; keep running until shutdown command */
    });
  }

  /** Stop reading stdin. */
  stopStdin(): void {
    this.readline?.close();
    this.readline = null;
  }

  /** Subscribe to a command by name. Returns an unsubscribe fn. */
  on<N extends DaemonCommandName>(cmd: N, listener: CommandListener<N>): () => void {
    const set = (this.listeners[cmd] ??= new Set());
    const adapter = (c: AnyCommand) => void listener(c as CommandOf<N>);
    set.add(adapter);
    return () => {
      set.delete(adapter);
    };
  }

  // ------------------------------------------------------------- internals ---

  private async writeLine(value: unknown): Promise<void> {
    return new Promise((resolve) => {
      const ok = process.stdout.write(`${JSON.stringify(value)}\n`, (err) => {
        if (err) {
          // EPIPE / parent gone: stop trying to emit further events.
          this.closed = true;
        }
        resolve();
      });
      // If the buffer could not accept all bytes, wait for the 'drain' event.
      if (!ok && !this.closed) {
        process.stdout.once("drain", () => resolve());
      }
    });
  }

  private handleLine(line: string): void {
    const trimmed = line.trim();
    if (!trimmed) return;

    let parsed: unknown;
    try {
      parsed = JSON.parse(trimmed);
    } catch (err) {
      void this.error("bad_command_json", `invalid JSON: ${(err as Error).message}`);
      return;
    }

    if (
      typeof parsed !== "object" ||
      parsed === null ||
      (parsed as { type?: unknown }).type !== "command" ||
      typeof (parsed as { cmd?: unknown }).cmd !== "string"
    ) {
      void this.error("bad_command_shape", `not a command: ${trimmed.slice(0, 200)}`);
      return;
    }

    const cmd = parsed as AnyCommand;
    const set = this.listeners[cmd.cmd];
    if (!set) {
      void this.error("unknown_command", `no handler for cmd "${cmd.cmd}"`);
      return;
    }
    for (const listener of set) {
      try {
        listener(cmd);
      } catch (err) {
        void this.error(
          "command_handler_error",
          `${cmd.cmd}: ${(err as Error).message}`,
        );
      }
    }
  }
}

/** Process-wide singleton: there is exactly one stdout/stdin pair. */
export const transport = new Transport();
