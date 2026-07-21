/**
 * DaemonStatusBadge — sidebar header summarizing daemon health.
 *
 * Renders a status dot, a countdown to the next poll, a Poll Now button,
 * and — when a review is in flight — the PR being reviewed.
 */
import { useState } from "react";
import { pollNow } from "../lib/tauri";
import type { PrLookupEntry } from "../hooks/useReviewQueue";
import Icon from "./ui/Icon";
import { useToast } from "./ui/Toast";

interface DaemonStatusBadgeProps {
  state: string;
  online: boolean;
  nextPollInSec: number | null;
  inProgressPrId: number | null;
  prLookup: Map<number, PrLookupEntry>;
}

function dotClass(state: string, online: boolean): string {
  if (!online) return "dot-offline";
  if (state === "error") return "dot-error";
  if (state === "polling" || state === "reviewing" || state === "publishing") {
    return "dot-active";
  }
  return "dot-idle";
}

function formatCountdown(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

export default function DaemonStatusBadge({
  state,
  online,
  nextPollInSec,
  inProgressPrId,
  prLookup,
}: DaemonStatusBadgeProps) {
  const [polling, setPolling] = useState(false);
  const toast = useToast();
  const review =
    inProgressPrId != null ? prLookup.get(inProgressPrId) : undefined;
  const reviewNum = review?.number ?? inProgressPrId;
  const isBusy = state === "polling" || state === "reviewing" || state === "publishing";

  const handlePollNow = async () => {
    setPolling(true);
    try {
      await pollNow();
      toast.info("폴링을 시작했어요.");
    } catch (err) {
      toast.error(
        "폴링 시작에 실패했어요.",
        err instanceof Error ? err.message : String(err),
      );
    } finally {
      setPolling(false);
    }
  };

  return (
    <div className="daemon-status-badge">
      <div className="badge-title">
        <span className={`status-dot ${dotClass(state, online)}`} />
        <span className="badge-name">PR Review</span>
        <button
          type="button"
          className="poll-now-btn"
          disabled={!online || isBusy || polling}
          onClick={handlePollNow}
          title="즉시 폴링"
          aria-label="즉시 폴링"
        >
          {polling || isBusy ? <Icon name="hourglass" /> : <Icon name="refresh-cw" />}
        </button>
      </div>
      <div className="countdown">
        {isBusy
          ? "폴링 중…"
          : nextPollInSec == null
            ? "첫 폴링을 기다리는 중…"
            : `다음 폴링: ${formatCountdown(nextPollInSec)}`}
      </div>
      {reviewNum != null && (
        <div className="badge-reviewing">
          #{reviewNum} 리뷰 중
          {review ? ` · ${review.title}` : ""}
        </div>
      )}
    </div>
  );
}
