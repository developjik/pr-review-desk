/**
 * Logging.
 *
 * Three sinks, all driven by a single pino instance via `pino.multistream`:
 *   1. Rotating file  — raw JSON lines under `<logDir>/daemon.log`, rotated by
 *                       size with `maxFiles - 1` numbered backups.
 *   2. stderr         — human-readable via `pino-pretty` (dev console / host
 *                       stderr capture).
 *   3. IPC            — every record is forwarded to the host as a
 *                       `daemon:log` event through the transport.
 *
 * IMPORTANT: pino never writes to stdout. All stdout output goes through the
 * transport so events and logs cannot interleave on the event channel.
 */
import { createWriteStream, existsSync, mkdirSync, renameSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { Writable } from "node:stream";
import pino, { multistream, type StreamEntry } from "pino";
import pretty from "pino-pretty";
import type { LogLevel } from "@pr-review/shared";
import type { Transport } from "../ipc/transport";

interface RotatingOptions {
  path: string;
  maxBytes: number;
  maxFiles: number; // base + (maxFiles - 1) backups
}

/**
 * Minimal size-rotating write stream. Rotates synchronously when a write would
 * exceed `maxBytes`, shifting `daemon.log.N` -> `.N+1` and dropping the oldest.
 */
class RotatingFileStream extends Writable {
  private readonly opts: RotatingOptions;
  private stream: ReturnType<typeof createWriteStream>;
  private bytes = 0;
  /** Set once the sink is being drained for shutdown/reload. */
  private ended = false;

  constructor(opts: RotatingOptions) {
    super();
    this.opts = opts;
    mkdirSync(dirname(opts.path), { recursive: true });
    try {
      this.bytes = statSync(opts.path).size;
    } catch {
      this.bytes = 0;
    }
    this.stream = createWriteStream(opts.path, { flags: "a" });
  }

  /**
   * No-op once the sink has been ended (flushed for shutdown/reload). Straggler
   * log records produced by in-flight async handlers are dropped rather than
   * crashing the process with ERR_STREAM_WRITE_AFTER_END.
   */
  override write(
    chunk: unknown,
    encodingOrCb?: BufferEncoding | ((error?: Error | null) => void),
    cb?: (error?: Error | null) => void,
  ): boolean {
    if (this.destroyed || this.ended) {
      const done = typeof encodingOrCb === "function" ? encodingOrCb : cb;
      done?.();
      return true;
    }
    return typeof encodingOrCb === "function"
      ? super.write(chunk as Buffer, encodingOrCb)
      : super.write(chunk as Buffer, encodingOrCb as BufferEncoding, cb);
  }

  override _write(
    chunk: Buffer,
    _encoding: BufferEncoding,
    callback: (error?: Error | null) => void,
  ): void {
    if (this.bytes > 0 && this.bytes + chunk.length > this.opts.maxBytes) {
      this.rotate();
    }
    try {
      this.stream.write(chunk);
      this.bytes += chunk.length;
      callback();
    } catch (err) {
      callback(err as Error);
    }
  }

  override _final(callback: (error?: Error | null) => void): void {
    this.ended = true;
    this.stream.end(callback);
  }

  private rotate(): void {
    this.stream.end();
    const { path, maxFiles } = this.opts;
    const oldest = `${path}.${maxFiles - 1}`;
    if (existsSync(oldest)) {
      try {
        renameSync(oldest, `${path}.del`);
      } catch {
        /* best-effort drop of the oldest backup */
      }
    }
    for (let i = maxFiles - 2; i >= 1; i--) {
      const from = `${path}.${i}`;
      const to = `${path}.${i + 1}`;
      if (existsSync(from)) renameSync(from, to);
    }
    if (existsSync(path)) renameSync(path, `${path}.1`);
    this.stream = createWriteStream(path, { flags: "a" });
    this.bytes = 0;
  }
}


/**
 * Forwards every log record to the host as a `daemon:log` event. Receives raw
 * JSON-line chunks from pino (same bytes as the file sink).
 */
class IpcLogStream extends Writable {
  constructor(private readonly transport: Transport) {
    super();
  }

  override _write(
    chunk: Buffer,
    _encoding: BufferEncoding,
    callback: (error?: Error | null) => void,
  ): void {
    try {
      const rec = JSON.parse(chunk.toString("utf8")) as {
        level: number;
        msg?: string;
        [k: string]: unknown;
      };
      const { level, msg, ...rest } = rec;
      const text = renderMessage(msg ?? "", rest);
      void this.transport.log(toLogLevel(level), text);
    } catch {
      /* a non-JSON chunk (partial flush) is not actionable here */
    }
    callback();
  }
}

/** pino numeric level -> wire LogLevel (debug/trace fold to info). */
function toLogLevel(level: number): LogLevel {
  if (level >= 50) return "error";
  if (level >= 40) return "warn";
  return "info";
}

/** Render a one-line message: `msg` plus any non-msg context as JSON. */
function renderMessage(msg: string, rest: Record<string, unknown>): string {
  const extras = Object.keys(rest).filter((k) => k !== "time" && k !== "pid" && k !== "hostname" && k !== "level");
  if (extras.length === 0) return msg;
  const picked: Record<string, unknown> = {};
  for (const k of extras) picked[k] = rest[k];
  return msg ? `${msg} ${JSON.stringify(picked)}` : JSON.stringify(picked);
}

// ----------------------------------------------------------------------------
// Singleton with bootstrap -> configured lifecycle
// ----------------------------------------------------------------------------

let current: pino.Logger | null = null;
/** Tracks the rotating file sink so we can drain it before process exit. */
let activeFile: RotatingFileStream | null = null;

/** Always returns a usable logger (a stderr-only bootstrap one before config). */
export function getLogger(): pino.Logger {
  if (current) return current;
  current = pino(
    { level: "info", timestamp: pino.stdTimeFunctions.isoTime },
    pretty({ destination: process.stderr.fd, colorize: true, sync: true }),
  );
  return current;
}

export interface LoggingOptions {
  logDir: string;
  level?: string;
  transport: Transport;
}

/**
 * (Re)build the logger with all three sinks once `logDir` is known. Safe to
 * call on hot-reload; the previous logger is flushed before being replaced.
 */
export function configureLogging(opts: LoggingOptions): void {
  const prev = current;
  const prevFile = activeFile;
  const file = new RotatingFileStream({
    path: join(opts.logDir, "daemon.log"),
    maxBytes: 5 * 1024 * 1024,
    maxFiles: 6,
  });
  const streams: StreamEntry[] = [
    { level: "trace", stream: file },
    {
      level: "trace",
      stream: pretty({
        destination: process.stderr.fd,
        colorize: true,
        sync: true,
        ignore: "pid,hostname",
      }),
    },
    { level: "trace", stream: new IpcLogStream(opts.transport) },
  ];
  current = pino(
    { level: opts.level ?? "info", timestamp: pino.stdTimeFunctions.isoTime },
    multistream(streams),
  );
  activeFile = file;
  if (prev) prev.flush?.();
  // Drain the previously-installed file sink so no log line is lost on reload.
  if (prevFile) void prevFile.end();
}

/**
 * Flush every pending log record to disk. MUST be awaited before
 * `process.exit` — Node does not flush in-flight `fs` writes on exit.
 */
export function flushLogs(): Promise<void> {
  const logger = current;
  const file = activeFile;
  return new Promise((resolve) => {
    const finishFile = () => {
      if (!file) return resolve();
      if (file.destroyed || file.writableEnded) return resolve();
      file.end(() => resolve());
    };
    if (logger && typeof logger.flush === "function") {
      // Push any pino-internal buffer to the streams, then drain the file sink.
      logger.flush(() => finishFile());
    } else {
      finishFile();
    }
  });
}
