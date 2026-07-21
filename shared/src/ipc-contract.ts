// IPC Protocol v1 — shared between daemon (sidecar) and host (Tauri).
//
// Wire format: one JSON message per line (JSON-line), UTF-8, terminated by "\n".
//  - daemon -> host: written to daemon stdout
//  - host  -> daemon: written to daemon stdin
//
// Every message carries a discriminator:
//   events    carry { type: "event",    event: <DaemonEventName>,    ... }
//   commands  carry { type: "command",  cmd:   <DaemonCommandName>, ... }

export const PROTO_VERSION = 1 as const;

// ----------------------------------------------------------------------------
// Shared scalar / payload types
// ----------------------------------------------------------------------------

/** Coarse daemon lifecycle state. `offline` is host-side (process not running). */
export type DaemonState = "idle" | "polling" | "reviewing" | "publishing" | "error";

/** Log severity propagated on `daemon:log`. Debug/trace are folded to "info". */
export type LogLevel = "info" | "warn" | "error";

/** Per-file review outcome carried on `review:file`. */
export type ReviewFileStatus = "ok" | "findings" | "skipped" | "error";

/** Review posting mode. */
export type ReviewMode = "auto" | "pending";

/** Minimal PR snapshot carried on the wire (`poll:found`). */
export interface PrSnapshot {
  id: number;
  number: number;
  title: string;
  repo: string; // "owner/name"
  author: string;
  headSha: string;
  url: string;
  updatedAt: string; // ISO 8601
}

/**
 * Full daemon configuration. Optional fields have daemon-side defaults but are
 * echoed back by the host once resolved so both sides agree on the snapshot.
 */
export interface ConfigPayload {
  githubUsername: string;
  githubPat: string;
  llmBaseUrl: string;
  llmApiKey: string;
  llmJsonMode?: boolean;
  llmModel: string;
  pollIntervalMin?: number;
  showSeverity?: boolean;
  osNotify?: boolean;
  reviewMode?: ReviewMode;
  reviewRules?: string;
  repoInclude?: string;
  repoExclude?: string;
  triggerLabels?: string;
  skipLabels?: string;
  dbPath: string;
  logDir: string;
}

/** A finding with a synthesized stable id, for pending review selection. */
export interface PendingFinding {
  id: string;
  file: string;
  line: number | null;
  severity: string;
  area: string;
  comment: string;
  suggestion?: string;
}

/** A user edit to a pending finding, applied before the pending review is posted. */
export interface FindingEdit {
  comment?: string;
  line?: number | null;
  severity?: string;
  suggestion?: string;
}

/** A pending review held for user approval. */
export interface PendingReview {
  reviewId: number;
  prId: number;
  prNumber: number;
  repo: string;
  title?: string;
  headSha: string;
  summary: string;
  findings: PendingFinding[];
  createdAt: string;
  /** Per-file diff hunk text (file → hunks) for the pending diff viewer. */
  diff?: Record<string, string> | null;
}

// ----------------------------------------------------------------------------
// Events (daemon -> host)
// ----------------------------------------------------------------------------

export const DaemonEventName = {
  Ready: "daemon:ready",
  Log: "daemon:log",
  Status: "daemon:status",
  PollStarted: "poll:started",
  PollFound: "poll:found",
  PollSkipped: "poll:skipped",
  ReviewFile: "review:file",
  ReviewSummary: "review:summary",
  PublishReview: "publish:review",
  Error: "daemon:error",
  ReviewPending: "review:pending",
  PendingSnapshot: "pending:snapshot",
  PendingResolved: "pending:resolved",
} as const;
export type DaemonEventName = (typeof DaemonEventName)[keyof typeof DaemonEventName];

interface EventEnvelope {
  type: "event";
  /** Epoch millis. Daemon stamps every event; host may override. */
  ts?: number;
}

export interface DaemonReadyEvent extends EventEnvelope {
  event: typeof DaemonEventName.Ready;
  proto: typeof PROTO_VERSION;
}

export interface DaemonLogEvent extends EventEnvelope {
  event: typeof DaemonEventName.Log;
  level: LogLevel;
  msg: string;
}

export interface DaemonStatusEvent extends EventEnvelope {
  event: typeof DaemonEventName.Status;
  state: DaemonState;
  msg?: string;
}

export interface PollStartedEvent extends EventEnvelope {
  event: typeof DaemonEventName.PollStarted;
}

export interface PollFoundEvent extends EventEnvelope {
  event: typeof DaemonEventName.PollFound;
  pr: PrSnapshot;
}

/** A queued PR was removed because it is no longer reviewable (merged/closed). */
export interface PollSkippedEvent extends EventEnvelope {
  event: typeof DaemonEventName.PollSkipped;
  prId: number;
  /** Machine reason: `merged` or `closed`. */
  reason: "merged" | "closed";
}

export interface ReviewFileEvent extends EventEnvelope {
  event: typeof DaemonEventName.ReviewFile;
  prId: number;
  file: string;
  status: ReviewFileStatus;
  findings: number;
}

export interface ReviewSummaryEvent extends EventEnvelope {
  event: typeof DaemonEventName.ReviewSummary;
  prId: number;
  summary: string;
  findings: number;
  /** Finding counts keyed by severity label (e.g. { "high": 2, "medium": 5 }). */
  severityCounts: Record<string, number>;
}

export interface PublishReviewEvent extends EventEnvelope {
  event: typeof DaemonEventName.PublishReview;
  prId: number;
  posted: number;
  degraded: number;
  retried: number;
}

export interface DaemonErrorEvent extends EventEnvelope {
  event: typeof DaemonEventName.Error;
  /** Stable machine code, e.g. "config_invalid", "fatal", "poll_failed". */
  code: string;
  /** Human-readable detail. */
  err: string;
}

export interface ReviewPendingEvent extends EventEnvelope {
  event: typeof DaemonEventName.ReviewPending;
  reviewId: number;
  prId: number;
  prNumber: number;
  repo: string;
  title?: string;
  headSha: string;
  summary: string;
  findings: PendingFinding[];
  /** Per-file diff hunk text (file → hunks) for the pending diff viewer. */
  diff?: Record<string, string> | null;
}

export interface PendingSnapshotEvent extends EventEnvelope {
  event: typeof DaemonEventName.PendingSnapshot;
  reviews: PendingReview[];
}

export interface PendingResolvedEvent extends EventEnvelope {
  event: typeof DaemonEventName.PendingResolved;
  reviewId: number;
  prId: number;
  status: "approved" | "rejected";
}

export type DaemonEvent =
  | DaemonReadyEvent
  | DaemonLogEvent
  | DaemonStatusEvent
  | PollStartedEvent
  | PollFoundEvent
  | PollSkippedEvent
  | ReviewFileEvent
  | ReviewSummaryEvent
  | PublishReviewEvent
  | DaemonErrorEvent
  | ReviewPendingEvent
  | PendingSnapshotEvent
  | PendingResolvedEvent;

// ----------------------------------------------------------------------------
// Commands (host -> daemon)
// ----------------------------------------------------------------------------

export const DaemonCommandName = {
  Config: "config",
  PollNow: "poll:now",
  Pause: "pause",
  Resume: "resume",
  Shutdown: "shutdown",
  ApproveReview: "approve:review",
  RejectReview: "reject:review",
  ListPending: "pending:list",
} as const;
export type DaemonCommandName = (typeof DaemonCommandName)[keyof typeof DaemonCommandName];

interface CommandEnvelope {
  type: "command";
  ts?: number;
}

export interface ConfigCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.Config;
  config: ConfigPayload;
}

export interface PollNowCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.PollNow;
}

export interface PauseCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.Pause;
}

export interface ResumeCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.Resume;
}

export interface ShutdownCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.Shutdown;
}

export interface ApproveReviewCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.ApproveReview;
  reviewId: number;
  findingIds?: string[];
  /** Per-finding edits keyed by finding id, applied before posting. */
  edits?: Record<string, FindingEdit>;
}

export interface RejectReviewCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.RejectReview;
  reviewId: number;
}

export interface ListPendingCommand extends CommandEnvelope {
  cmd: typeof DaemonCommandName.ListPending;
}

export type DaemonCommand =
  | ConfigCommand
  | PollNowCommand
  | PauseCommand
  | ResumeCommand
  | ShutdownCommand
  | ApproveReviewCommand
  | RejectReviewCommand
  | ListPendingCommand;

// ----------------------------------------------------------------------------
// Discriminated-union narrowing helpers
// ----------------------------------------------------------------------------

export type EventOf<E extends DaemonEventName> = Extract<DaemonEvent, { event: E }>;
export type CommandOf<C extends DaemonCommandName> = Extract<DaemonCommand, { cmd: C }>;

/** Type guard: is this object a well-formed daemon event envelope? */
export function isDaemonEvent(value: unknown): value is DaemonEvent {
  return (
    typeof value === "object" &&
    value !== null &&
    (value as { type?: unknown }).type === "event" &&
    typeof (value as { event?: unknown }).event === "string"
  );
}

/** Type guard: is this object a well-formed daemon command envelope? */
export function isDaemonCommand(value: unknown): value is DaemonCommand {
  return (
    typeof value === "object" &&
    value !== null &&
    (value as { type?: unknown }).type === "command" &&
    typeof (value as { cmd?: unknown }).cmd === "string"
  );
}
