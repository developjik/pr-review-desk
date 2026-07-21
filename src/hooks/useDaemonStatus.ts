/**
 * useDaemonStatus — subscribe to `daemon://status` events + poll the initial
 * snapshot via `daemon_status()` on mount, plus periodic re-sync every 10s
 * to recover from any missed status events.
 */
import { useEffect, useState } from "react";
import { getDaemonStatus, onDaemonStatus } from "../lib/tauri";

export interface DaemonStatus {
  online: boolean;
  state: string;
}

const INITIAL: DaemonStatus = { online: false, state: "idle" };

export function useDaemonStatus(): DaemonStatus {
  const [status, setStatus] = useState<DaemonStatus>(INITIAL);

  useEffect(() => {
    let unlisten: (() => void) | null = null;
    let cancelled = false;

    const sync = () => {
      getDaemonStatus()
        .then((snap) => {
          if (!cancelled) setStatus(snap);
        })
        .catch(() => {});
    };

    // Seed from the current snapshot
    sync();

    // Subscribe to live events
    onDaemonStatus((state) => {
      setStatus({ online: true, state });
    }).then((fn) => {
      if (cancelled) fn();
      else unlisten = fn;
    });

    // Periodic re-sync every 10s to recover from missed events
    const interval = window.setInterval(sync, 10_000);

    return () => {
      cancelled = true;
      unlisten?.();
      window.clearInterval(interval);
    };
  }, []);

  return status;
}
