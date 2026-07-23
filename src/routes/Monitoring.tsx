/**
 * Monitoring — layered review dashboard.
 *
 * 1. Summary  — session-level stat cards (reviews, comments, avg findings).
 * 2. Tabs     — switch between the live Queue and completed History.
 * 3. Queue    — live PRs from `poll:found`, filterable by status.
 * 4. History  — completed reviews with findings counts.
 * 5. Slide-over — PR detail panel opened on row click.
 *
 * Backed by the `useReviewQueue` hook.
 */
import { useMemo, useState } from "react";
import { motion } from "motion/react";
import { Menu, MenuItem } from "@tauri-apps/api/menu";
import { openUrl } from "@tauri-apps/plugin-opener";
import { useReviewQueue } from "../hooks/useReviewQueue";
import { useReviewHistory } from "../hooks/useReviewHistory";
import { useStats } from "../hooks/useStats";
import EmptyState from "../components/EmptyState";
import type { HistoryEntry, QueueEntry } from "../hooks/useReviewQueue";
import Tabs, { TabList, Tab } from "../components/ui/Tabs";
import Dialog from "../components/ui/Dialog";
import AlertDialog from "../components/ui/AlertDialog";
import { useToast } from "../components/ui/Toast";
import { Icon } from "../components/ui/Icon";
import type { ReviewHistoryEntry } from "@pr-review/shared";
type TabId = "queue" | "history";
type Filter = "all" | "waiting" | "reviewing";
type PrStatus = "queued" | "reviewing" | "done";

interface PrDetail {
  title: string;
  repo: string;
  number: number;
  status: PrStatus;
  findings?: number;
  completedAt?: number;
}

const FILTER_LABEL: Record<Filter, string> = {
  all: "전체",
  waiting: "대기중",
  reviewing: "리뷰중",
};

const STATUS_LABEL: Record<PrStatus, string> = {
  queued: "대기",
  reviewing: "리뷰중",
  done: "완료",
};

const STATUS_BADGE: Record<PrStatus, string> = {
  queued: "badge-idle",
  reviewing: "badge-active",
  done: "badge-success",
};

/** Build a GitHub PR URL from an "owner/name" repo + PR number. */
function prUrl(repo: string, number: number): string {
  return `https://github.com/${repo}/pull/${number}`;
}

/**
 * Native context menu for a PR row. Two actions only: Copy PR link / Open in
 * browser. "Re-review" is intentionally dropped — no IPC command exists. Uses
 * the Tauri v2 menu API; `Menu.popup()` renders at the current cursor. When no
 * `url` is resolvable the menu is skipped but the browser default is still
 * suppressed (no native browser menu on app rows).
 */
async function showPrContextMenu(
  e: React.MouseEvent,
  url: string | null,
): Promise<void> {
  e.preventDefault();
  if (!url) return;
  const copy = await MenuItem.new({
    id: "copy-link",
    text: "PR 링크 복사",
    action: () => {
      void navigator.clipboard.writeText(url).catch(() => {});
    },
  });
  const open = await MenuItem.new({
    id: "open-browser",
    text: "브라우저에서 열기",
    action: () => {
      void openUrl(url);
    },
  });
  const menu = await Menu.new({ items: [copy, open] });
  await menu.popup();
}

export default function Monitoring() {
  const toast = useToast();
  const { queue, history, stats, inProgressPrId, clearHistory } =
    useReviewQueue();
  const { reviews: dbReviews, filters, setFilters, loading: historyLoading } = useReviewHistory();
  const { summary, daily } = useStats();
  const [tab, setTab] = useState<TabId>("queue");
  const [filter, setFilter] = useState<Filter>("all");
  const [detail, setDetail] = useState<PrDetail | null>(null);
  // Whether the Clear-history confirmation AlertDialog is open.
  const [clearOpen, setClearOpen] = useState(false);

  const avgFindings =
    stats.totalReviews > 0
      ? (stats.totalComments / stats.totalReviews).toFixed(1)
      : "0";

  const filteredQueue = useMemo(() => {
    if (filter === "all") return queue;
    return queue.filter((entry) =>
      filter === "reviewing"
        ? entry.pr.id === inProgressPrId
        : entry.pr.id !== inProgressPrId,
    );
  }, [queue, filter, inProgressPrId]);

  const openQueueDetail = (entry: QueueEntry) => {
    setDetail({
      title: entry.pr.title,
      repo: entry.pr.repo,
      number: entry.pr.number,
      status: entry.pr.id === inProgressPrId ? "reviewing" : "queued",
    });
  };

  const openHistoryDetail = (h: HistoryEntry) => {
    setDetail({
      title: h.title ?? `PR #${h.prId}`,
      repo: h.repo ?? "—",
      number: h.number ?? h.prId,
      status: "done",
      findings: h.posted,
      completedAt: h.completedAt,
    });
  };

  return (
    <section className="page monitoring">
      <div className="page-header">
        <h2>모니터링</h2>
      </div>

      {/* ---- Summary ----------------------------------------------------- */}
      <div className="monitoring-summary">
        <div className="summary-card">
          <span className="summary-label">이번 세션 리뷰 수</span>
          <span className="summary-value">{stats.totalReviews}</span>
        </div>
        <div className="summary-card">
          <span className="summary-label">총 코멘트 수</span>
          <span className="summary-value">{stats.totalComments}</span>
        </div>
        <div className="summary-card">
          <span className="summary-label">평균 코멘트 수</span>
          <span className="summary-value">{avgFindings}</span>
        </div>
        <div className="summary-card">
          <span className="summary-label">이번 달 총 비용</span>
          <span className="summary-value">{summary?.totalCostUsd.toFixed(4) ?? "0"} USD</span>
        </div>
        <div className="summary-card">
          <span className="summary-label">이번 달 총 토큰</span>
          <span className="summary-value">{summary?.totalTokens.toLocaleString() ?? "0"}</span>
        </div>
        <div className="summary-card">
          <span className="summary-label">일평균 리뷰 (최근 30일)</span>
          <span className="summary-value">
            {(daily.reduce((s, d) => s + d.reviews, 0) / Math.max(1, daily.length)).toFixed(1)}
          </span>
        </div>
        {daily.length > 0 && (
          <div className="stats-chart">
            <h4 className="stats-chart-title">최근 리뷰 추이</h4>
            <svg className="daily-chart" viewBox="0 0 300 80" preserveAspectRatio="none">
              {daily.map((d, i) => {
                const max = Math.max(1, ...daily.map((x) => x.reviews));
                const h = (d.reviews / max) * 70;
                const w = 300 / daily.length;
                return (
                  <rect
                    key={d.date}
                    x={i * w}
                    y={80 - h}
                    width={Math.max(1, w - 1)}
                    height={h}
                    fill="var(--accent)"
                    opacity={0.7}
                  />
                );
              })}
            </svg>
          </div>
        )}
      </div>

      {/* ---- Tab bar ----------------------------------------------------- */}
      <Tabs value={tab} onValueChange={(v) => setTab(v as TabId)}>
        <TabList>
          <Tab value="queue">
            Queue
            <span className="tab-count">{queue.length}</span>
          </Tab>
          <Tab value="history">
            History
            <span className="tab-count">{history.length}</span>
          </Tab>
        </TabList>
      </Tabs>

      {/* ---- Queue tab --------------------------------------------------- */}
      {tab === "queue" && (
        <div className="tab-panel-content">
          <div className="filter-chips">
            {(Object.keys(FILTER_LABEL) as Filter[]).map((f) => (
              <button
                key={f}
                type="button"
                className={`filter-chip ${filter === f ? "active" : ""}`}
                onClick={() => setFilter(f)}
              >
                {FILTER_LABEL[f]}
              </button>
            ))}
          </div>
          {filteredQueue.length === 0 ? (
            queue.length === 0 ? (
              <EmptyState
                icon="package-open"
                title="아직 리뷰 대상 PR이 없어요"
                message="폴링이 실행되면 여기에 표시돼요."
              />
            ) : (
              <EmptyState
                icon="search"
                title="선택한 필터에 해당하는 PR이 없어요"
                message="다른 필터를 선택해 보세요."
              />
            )
          ) : (
            <ul className="monitoring-list">
              {filteredQueue.map((entry, index) => {
                const reviewing = entry.pr.id === inProgressPrId;
                const status: PrStatus = reviewing ? "reviewing" : "queued";
                // Stagger capped at ~8 items so long lists don't keep users
                // waiting on the entrance (plan §5 Phase 3, MOTION_INTENSITY=4).
                const delay = Math.min(index, 7) * 0.04;
                return (
                  <motion.li
                    key={entry.pr.id}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.18, ease: "easeOut", delay }}
                  >
                    <button
                      type="button"
                      className="pr-row"
                      onClick={() => openQueueDetail(entry)}
                      onContextMenu={(e) =>
                        void showPrContextMenu(e, entry.pr.url)
                      }
                    >
                      <span className="pr-repo">{entry.pr.repo}</span>
                      <span className="pr-title">{entry.pr.title}</span>
                      <span className="pr-number">#{entry.pr.number}</span>
                      <span className={`badge ${STATUS_BADGE[status]}`}>
                        {STATUS_LABEL[status]}
                      </span>
                    </button>
                  </motion.li>
                );
              })}
            </ul>
          )}
        </div>
      )}

      {/* ---- History tab ------------------------------------------------- */}
      {tab === "history" && (
        <div className="tab-panel-content">
          <div className="history-filters">
            <input
              type="text"
              className="history-search"
              placeholder="리포 검색 (owner/repo)..."
              value={filters.repo ?? ""}
              onChange={(e) => setFilters({ repo: e.target.value || undefined })}
            />
            <select
              className="history-severity-filter"
              value={filters.severity ?? ""}
              onChange={(e) => setFilters({ severity: e.target.value || undefined })}
            >
              <option value="">모든 심각도</option>
              <option value="high">High</option>
              <option value="medium">Medium</option>
              <option value="low">Low</option>
            </select>
          </div>
          <div className="list-header">
            {history.length > 0 && (
              <AlertDialog
                open={clearOpen}
                onOpenChange={setClearOpen}
                title="기록 삭제"
                description="완료된 리뷰 기록을 모두 삭제할까요?"
                confirmLabel="삭제"
                cancelLabel="취소"
                onConfirm={() => {
                  clearHistory();
                  toast.success("기록을 삭제했어요.");
                }}
              >
                <button type="button" className="link-btn">
                  삭제
                </button>
              </AlertDialog>
            )}
          </div>
          {history.length === 0 ? (
            <EmptyState
              icon="bar-chart-2"
              title="완료된 리뷰가 없어요"
              message="리뷰가 완료되면 여기에 표시돼요."
            />
          ) : (
            <ul className="monitoring-list">
              {history.map((h, i) => {
                const delay = Math.min(i, 7) * 0.04;
                return (
                  <motion.li
                    key={`${h.prId}-${i}`}
                    initial={{ opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ duration: 0.18, ease: "easeOut", delay }}
                  >
                    <button
                      type="button"
                      className="pr-row"
                      onClick={() => openHistoryDetail(h)}
                      onContextMenu={(e) =>
                        void showPrContextMenu(
                          e,
                          h.repo && h.number != null
                            ? prUrl(h.repo, h.number)
                            : null,
                        )
                      }
                    >
                      <span className="pr-repo">{h.repo ?? "—"}</span>
                      <span className="pr-title">
                        {h.title ?? `PR #${h.prId}`}
                      </span>
                      <span className="pr-number">#{h.number ?? h.prId}</span>
                      <span className="findings-count">{h.posted}개</span>
                      <time>{new Date(h.completedAt).toLocaleString()}</time>
                    </button>
                  </motion.li>
                );
              })}
              {historyLoading && <p className="history-loading">불러오는 중...</p>}
              {dbReviews.length > 0 && (
                <>
                  <div className="history-section-divider">
                    <span>과거 리뷰 ({dbReviews.length})</span>
                  </div>
                  {dbReviews.slice(0, 50).map((r: ReviewHistoryEntry) => (
                    <li key={`db-${r.id}`} className="history-item db-history-item">
                      <div className="history-detail">
                        <span className="pr-title">{r.title ?? `PR #${r.prNumber}`}</span>
                        <span className="pr-repo">{r.repo}</span>
                      </div>
                      <div className="history-meta">
                        <span>{r.findingsTotal} findings</span>
                        <time>{new Date(r.reviewedAt).toLocaleDateString()}</time>
                      </div>
                    </li>
                  ))}
                </>
              )}
            </ul>
          )}
        </div>
      )}

      {/* ---- Slide-over detail ------------------------------------------- */}
      <Dialog
        open={detail !== null}
        onOpenChange={(open) => {
          if (!open) setDetail(null);
        }}
        variant="slide-over"
        label="PR 상세"
      >
        <div className="slide-over-header">
          <h3>PR 상세</h3>
          <button
            type="button"
            className="slide-over-close"
            aria-label="닫기"
            onClick={() => setDetail(null)}
          >
            <Icon name="x" />
          </button>
        </div>
        <div className="slide-over-body">
          {detail && (
            <>
              <div className="detail-title">{detail.title}</div>
              <div className="detail-rows">
                <div className="detail-row">
                  <span className="detail-key">리포지토리</span>
                  <span className="detail-val">{detail.repo}</span>
                </div>
                <div className="detail-row">
                  <span className="detail-key">PR 번호</span>
                  <span className="detail-val">#{detail.number}</span>
                </div>
                <div className="detail-row">
                  <span className="detail-key">상태</span>
                  <span className="detail-val">
                    <span className={`badge ${STATUS_BADGE[detail.status]}`}>
                      {STATUS_LABEL[detail.status]}
                    </span>
                  </span>
                </div>
                {detail.findings !== undefined && (
                  <div className="detail-row">
                    <span className="detail-key">코멘트 수</span>
                    <span className="detail-val">{detail.findings}</span>
                  </div>
                )}
                {detail.completedAt !== undefined && (
                  <div className="detail-row">
                    <span className="detail-key">완료 시간</span>
                    <span className="detail-val">
                      {new Date(detail.completedAt).toLocaleString()}
                    </span>
                  </div>
                )}
              </div>
            </>
          )}
        </div>
      </Dialog>
    </section>
  );
}
