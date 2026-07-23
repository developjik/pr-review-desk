/**
 * Pending — reviews awaiting approval.
 *
 * Each pending review is a card with selectable findings. The user approves a
 * subset (checkboxes default to all selected) or rejects the whole review.
 * Approve / Reject fire optimistic removals via the hook.
 *
 * Per-finding affordances:
 *  - "code" toggle: expand an in-repo DiffViewer on the finding's file/line.
 *  - "edit" toggle: inline-edit comment / line / severity / suggestion before
 *    approving. Edits are collected per review (keyed by finding id) and
 *    threaded into approve(); the daemon applies them before the selection
 *    filter, so unedited findings pass through byte-identical.
 */
import { useState } from "react";
import { usePendingReviews } from "../hooks/usePendingReviews";
import EmptyState from "../components/EmptyState";
import DiffViewer from "../components/DiffViewer";
import AlertDialog from "../components/ui/AlertDialog";
import { useToast } from "../components/ui/Toast";
import { markFinding } from "../lib/tauri";
import type {
  FindingEdit,
  FindingFeedback,
  PendingReview,
  PendingFinding,
} from "@pr-review/shared";

const SEVERITY_CLASS: Record<string, string> = {
  high: "sev-high",
  medium: "sev-medium",
  low: "sev-low",
  info: "sev-info",
  critical: "sev-high",
};

const SEVERITY_OPTIONS = Object.keys(SEVERITY_CLASS);

export default function Pending() {
  const { pending, approve, reject, submitting } = usePendingReviews();
  const toast = useToast();
  const [selections, setSelections] = useState<Record<number, Set<string>>>({});
  // reviewId → set of finding ids with the diff viewer expanded.
  const [expanded, setExpanded] = useState<Record<number, Set<string>>>({});
  // reviewId → set of finding ids with the inline editor open.
  const [editing, setEditing] = useState<Record<number, Set<string>>>({});
  // reviewId → findingId → partial edit applied before posting.
  const [edits, setEdits] = useState<
    Record<number, Record<string, FindingEdit>>
  >({});
  // reviewId → findingId → feedback ('useful' | 'false_positive')
  const [feedback, setFeedback] = useState<Record<number, Record<string, FindingFeedback>>>({});
  // reviewId whose Reject AlertDialog is currently open (only one at a time).
  const [rejectOpenFor, setRejectOpenFor] = useState<number | null>(null);

  const getSelected = (
    reviewId: number,
    findings: PendingFinding[],
  ): Set<string> => {
    if (!selections[reviewId]) {
      return new Set(findings.map((f) => f.id));
    }
    return selections[reviewId];
  };

  const toggleFinding = (reviewId: number, findingId: string) => {
    setSelections((prev) => {
      const current = new Set(prev[reviewId] ?? []);
      if (current.has(findingId)) current.delete(findingId);
      else current.add(findingId);
      return { ...prev, [reviewId]: current };
    });
  };

  const toggleIn = (
    prev: Record<number, Set<string>>,
    reviewId: number,
    findingId: string,
  ): Record<number, Set<string>> => {
    const current = new Set(prev[reviewId] ?? []);
    if (current.has(findingId)) current.delete(findingId);
    else current.add(findingId);
    return { ...prev, [reviewId]: current };
  };

  const toggleExpanded = (reviewId: number, findingId: string) =>
    setExpanded((prev) => toggleIn(prev, reviewId, findingId));

  const toggleEditing = (reviewId: number, findingId: string) =>
    setEditing((prev) => toggleIn(prev, reviewId, findingId));

  const setEdit = (
    reviewId: number,
    findingId: string,
    patch: Partial<FindingEdit>,
  ) => {
    setEdits((prev) => {
      const reviewEdits = prev[reviewId] ?? {};
      const existing = reviewEdits[findingId] ?? {};
      return {
        ...prev,
        [reviewId]: {
          ...reviewEdits,
          [findingId]: { ...existing, ...patch },
        },
      };
    });
  };

  const clearEdit = (reviewId: number, findingId: string) => {
    setEdits((prev) => {
      const reviewEdits = prev[reviewId];
      if (!reviewEdits) return prev;
      const next = { ...reviewEdits };
      delete next[findingId];
      return { ...prev, [reviewId]: next };
    });
  };
  const handleFeedback = (
    reviewId: number,
    finding: PendingFinding,
    fb: FindingFeedback,
  ) => {
    setFeedback((prev) => ({
      ...prev,
      [reviewId]: { ...prev[reviewId], [finding.id]: fb },
    }));
    void markFinding(
      reviewId,
      finding.id,
      finding.file,
      finding.line,
      finding.comment,
      finding.area,
      finding.severity,
      fb,
    );
    toast.success(fb === "useful" ? "유용한 리뷰로 표시했어요." : "오탐으로 표시했어요.");
  };

  return (
    <section className="page">
      <h2>승인 대기 리뷰</h2>
      {pending.length === 0 ? (
        <EmptyState
          icon="hourglass"
          title="승인 대기 중인 리뷰가 없어요"
          message="승인을 기다리는 리뷰가 여기에 표시돼요."
        />
      ) : (
        <div className="pending-list">
          {pending.map((review: PendingReview) => {
            const selected = getSelected(review.reviewId, review.findings);
            const reviewEdits = edits[review.reviewId] ?? {};
            const expandedSet = expanded[review.reviewId] ?? new Set<string>();
            const editingSet = editing[review.reviewId] ?? new Set<string>();
            return (
              <div key={review.reviewId} className="pending-card card">
                <div className="pending-header">
                  <h3>
                    {review.repo} #{review.prNumber}
                  </h3>
                  {review.title && <p className="pending-title">{review.title}</p>}
                  <p className="pending-summary">{review.summary}</p>
                  <span className="badge">{review.findings.length}개 코멘트</span>
                </div>
                <div className="pending-findings">
                  {review.findings.map((f) => {
                    const edit = reviewEdits[f.id] ?? {};
                    const codeOpen = expandedSet.has(f.id);
                    const editOpen = editingSet.has(f.id);
                    const lineValue = edit.line !== undefined ? edit.line : f.line;
                    return (
                      <div key={f.id} className="pending-finding-group">
                        <div className="pending-finding-main">
                          <label className="pending-finding">
                            <input
                              type="checkbox"
                              checked={selected.has(f.id)}
                              onChange={() =>
                                toggleFinding(review.reviewId, f.id)
                              }
                            />
                            <span
                              className={`severity-badge ${SEVERITY_CLASS[f.severity] || "sev-low"}`}
                            >
                              {f.severity}
                            </span>
                            <span className="finding-loc">
                              {f.file}
                              {f.line !== null ? `:${f.line}` : ""}
                            </span>
                            <span className="finding-comment">{f.comment}</span>
                          </label>
                          <span className="finding-toggles">
                            <button
                              type="button"
                              className="finding-code-toggle"
                              aria-pressed={codeOpen}
                              onClick={() =>
                                toggleExpanded(review.reviewId, f.id)
                              }
                            >
                              코드
                            </button>
                            <button
                              type="button"
                              className="finding-code-toggle"
                              aria-pressed={editOpen}
                              onClick={() =>
                                toggleEditing(review.reviewId, f.id)
                              }
                            >
                              편집
                            </button>
                          </span>
                          <div className="finding-feedback">
                            <button
                              type="button"
                              className={`feedback-btn ${feedback[review.reviewId]?.[f.id] === "useful" ? "active" : ""}`}
                              onClick={() => handleFeedback(review.reviewId, f, "useful")}
                              aria-label="유용"
                            >
                              👍
                            </button>
                            <button
                              type="button"
                              className={`feedback-btn ${feedback[review.reviewId]?.[f.id] === "false_positive" ? "active" : ""}`}
                              onClick={() => handleFeedback(review.reviewId, f, "false_positive")}
                              aria-label="오탐"
                            >
                              👎
                            </button>
                          </div>
                        </div>
                        {codeOpen && (
                          <DiffViewer
                            hunk={review.diff?.[f.file]}
                            targetLine={f.line}
                          />
                        )}
                        {editOpen && (
                          <div className="finding-edit">
                            <div className="finding-edit-row">
                              <label>
                                코멘트
                                <textarea
                                  value={edit.comment ?? f.comment}
                                  onChange={(e) =>
                                    setEdit(review.reviewId, f.id, {
                                      comment: e.target.value,
                                    })
                                  }
                                />
                              </label>
                            </div>
                            <div className="finding-edit-row">
                              <label>
                                줄
                                <input
                                  type="number"
                                  value={lineValue ?? ""}
                                  onChange={(e) => {
                                    const raw = e.target.value;
                                    const parsed =
                                      raw === "" ? null : Number.parseInt(raw, 10);
                                    setEdit(review.reviewId, f.id, {
                                      line:
                                        parsed !== null &&
                                        Number.isNaN(parsed)
                                          ? null
                                          : parsed,
                                    });
                                  }}
                                />
                              </label>
                              <label>
                                심각도
                                <select
                                  value={edit.severity ?? f.severity}
                                  onChange={(e) =>
                                    setEdit(review.reviewId, f.id, {
                                      severity: e.target.value,
                                    })
                                  }
                                >
                                  {SEVERITY_OPTIONS.map((s) => (
                                    <option key={s} value={s}>
                                      {s}
                                    </option>
                                  ))}
                                </select>
                              </label>
                            </div>
                            <div className="finding-edit-row">
                              <label>
                                제안
                                <textarea
                                  value={edit.suggestion ?? f.suggestion ?? ""}
                                  onChange={(e) =>
                                    setEdit(review.reviewId, f.id, {
                                      suggestion: e.target.value,
                                    })
                                  }
                                />
                              </label>
                            </div>
                            <div className="finding-edit-actions">
                              <button
                                type="button"
                                onClick={() =>
                                  clearEdit(review.reviewId, f.id)
                                }
                              >
                                초기화
                              </button>
                            </div>
                          </div>
                        )}
                      </div>
                    );
                  })}
                </div>
                <div className="pending-actions">
                  <button
                    type="button"
                    className="btn btn-primary"
                    data-loading={submitting[review.reviewId] === "approve"}
                    disabled={submitting[review.reviewId] != null}
                    onClick={async () => {
                      const r = await approve(
                        review.reviewId,
                        [...selected],
                        reviewEdits && Object.keys(reviewEdits).length > 0
                          ? reviewEdits
                          : undefined,
                      );
                      if (r.ok)
                        toast.success(`${selected.size}개 코멘트를 승인했어요.`);
                      else toast.error("승인에 실패했어요.", r.error);
                    }}
                  >
                    {selected.size}개 승인
                  </button>
                  <AlertDialog
                    open={rejectOpenFor === review.reviewId}
                    onOpenChange={(open) =>
                      setRejectOpenFor(open ? review.reviewId : null)
                    }
                    title="리뷰 거부"
                    description="정말 이 리뷰를 거부하시겠어요?"
                    confirmLabel="거부"
                    cancelLabel="취소"
                    onConfirm={async () => {
                      const r = await reject(review.reviewId);
                      if (r.ok) toast.success("리뷰를 거부했어요.");
                      else {
                        toast.error("거부에 실패했어요.", r.error);
                        throw new Error(r.error ?? "reject failed");
                      }
                    }}
                  >
                    <button
                      type="button"
                      className="btn btn-secondary"
                      disabled={submitting[review.reviewId] != null}
                    >
                      거부
                    </button>
                  </AlertDialog>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
