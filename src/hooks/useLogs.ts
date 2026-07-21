/**
 * useLogs — accumulate `daemon://log` events into a bounded ring buffer.
 *
 * Each entry is `{ level, msg, ts }`. The buffer caps at `maxEntries` (default
 * 1000) to avoid unbounded memory growth in a long-running session. `clear`
 * resets the buffer.
 */
import { useCallback, useEffect, useRef, useState } from "react";
import { onDaemonLog } from "../lib/tauri";
import type { LogLevel } from "@pr-review/shared";

export interface LogEntry {
  level: LogLevel;
  msg: string;
  ts: number;
}

const DEFAULT_MAX = 1000;

export function useLogs(maxEntries: number = DEFAULT_MAX) {
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const counter = useRef(0);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    let cancelled = false;

    onDaemonLog((level, msg) => {
      counter.current += 1;
      setLogs((prev) => {
        const next = [...prev, { level, msg, ts: Date.now() }];
        return next.length > maxEntries
          ? next.slice(next.length - maxEntries)
          : next;
      });
    }).then((fn) => {
      if (cancelled) fn();
      else unlisten = fn;
    });

    return () => {
      cancelled = true;
      unlisten?.();
    };
  }, [maxEntries]);

  const clear = useCallback(() => setLogs([]), []);

  return { logs, clear };
}
