/**
 * Logs — real-time log stream from `daemon://log` events.
 *
 * Terminal-style rendering: monospace, timestamped, level-tagged with color.
 * Auto-scrolls to the latest entry while the user is pinned to the bottom;
 * a Clear button sits top-right.
 */
import { useEffect, useRef, useState } from "react";
import { useLogs } from "../hooks/useLogs";
import EmptyState from "../components/EmptyState";
import type { LogLevel } from "@pr-review/shared";
import AlertDialog from "../components/ui/AlertDialog";
import { useToast } from "../components/ui/Toast";
import { Icon } from "../components/ui/Icon";

const LEVEL_CLASS: Record<LogLevel, string> = {
  info: "log-info",
  warn: "log-warn",
  error: "log-error",
};

export default function Logs() {
  const { logs, clear } = useLogs();
  const toast = useToast();
  const containerRef = useRef<HTMLDivElement>(null);
  const atBottomRef = useRef(true);
  const [clearOpen, setClearOpen] = useState(false);
  // P4: explicit auto-follow toggle in the header. Default ON; persists for the
  // session only (useState, no localStorage). When ON, the existing
  // atBottomRef smart behavior is preserved — scrolling up to read old logs
  // still pauses auto-scroll until the user re-pins to the bottom. When OFF,
  // never auto-scroll regardless of position.
  const [autoFollow, setAutoFollow] = useState(true);

  // Auto-scroll: keep pinned to the bottom if auto-follow is on AND the user
  // hasn't scrolled away from the bottom.
  useEffect(() => {
    const el = containerRef.current;
    if (el && autoFollow && atBottomRef.current) {
      el.scrollTop = el.scrollHeight;
    }
  }, [logs, autoFollow]);

  const handleScroll = () => {
    const el = containerRef.current;
    if (!el) return;
    atBottomRef.current = el.scrollHeight - el.scrollTop - el.clientHeight < 40;
  };

  const toggleAutoFollow = () => {
    const next = !autoFollow;
    setAutoFollow(next);
    // Re-enabling should also re-pin to the bottom immediately.
    if (next) {
      const el = containerRef.current;
      if (el) {
        el.scrollTop = el.scrollHeight;
        atBottomRef.current = true;
      }
    }
  };

  return (
    <section className="page logs-panel">
      <h2>
        Logs
        <span className="logs-header-actions">
          <button
            type="button"
            className="auto-follow-btn"
            aria-pressed={autoFollow}
            onClick={toggleAutoFollow}
            title={autoFollow ? "자동 스크롤: 켜짐" : "자동 스크롤: 꺼짐"}
          >
            {autoFollow && <Icon name="chevron-down" />}
            자동 스크롤
          </button>
          <AlertDialog
            open={clearOpen}
            onOpenChange={setClearOpen}
            title="로그 삭제"
            description="모든 로그를 삭제할까요?"
            confirmLabel="삭제"
            cancelLabel="취소"
            onConfirm={() => {
              clear();
              toast.success("로그를 삭제했어요.");
            }}
          >
            <button type="button" className="link-btn">
              삭제
            </button>
          </AlertDialog>
        </span>
      </h2>
      <div className="log-stream" ref={containerRef} onScroll={handleScroll}>
        {logs.length === 0 ? (
          <EmptyState
            icon="file-text"
            title="로그를 기다리는 중이에요…"
            message="데몬 출력이 여기에 표시돼요."
          />
        ) : (
          logs.map((entry, i) => (
            <div key={i} className={`log-line ${LEVEL_CLASS[entry.level]}`}>
              <span className="log-time">
                {new Date(entry.ts).toLocaleTimeString()}
              </span>
              <span className="log-level">{entry.level}</span>
              <span className="log-msg">{entry.msg}</span>
            </div>
          ))
        )}
      </div>
    </section>
  );
}
