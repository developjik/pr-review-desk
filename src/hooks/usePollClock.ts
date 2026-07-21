/**
 * usePollClock — countdown to the next daemon poll.
 *
 * Listens for `daemon://poll:started` events; on each one it resets the
 * countdown to `pollIntervalMin * 60` seconds and then decrements every second.
 * Returns `nextPollInSec: null` until the first poll event is observed, so the
 * UI can distinguish "no poll yet" from "poll imminent".
 */
import { useEffect, useState } from "react";
import { onPollStarted } from "../lib/tauri";

export interface PollClock {
  nextPollInSec: number | null;
}

export function usePollClock(pollIntervalMin: number): PollClock {
  const [nextPollInSec, setNextPollInSec] = useState<number | null>(null);

  useEffect(() => {
    const totalSec = Math.max(0, Math.floor(pollIntervalMin * 60));
    let unlisten: (() => void) | null = null;
    let cancelled = false;

    onPollStarted(() => {
      setNextPollInSec(totalSec);
    }).then((fn) => {
      if (cancelled) fn();
      else unlisten = fn;
    });

    const tick = window.setInterval(() => {
      setNextPollInSec((prev) => (prev === null ? null : Math.max(0, prev - 1)));
    }, 1000);

    return () => {
      cancelled = true;
      unlisten?.();
      window.clearInterval(tick);
    };
  }, [pollIntervalMin]);

  return { nextPollInSec };
}
