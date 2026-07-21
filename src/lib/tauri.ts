/**
 * Tauri invoke / listen wrappers — single import surface for the React UI.
 *
 * All daemon IPC flows through these typed helpers:
 *   - `invoke` wrappers call Rust `#[tauri::command]` functions,
 *   - `listen` wrappers subscribe to `daemon://<event>` channels emitted by
 *     `ipc::bridge_line` on the Rust side.
 *
 * Event names mirror the bare event names after the `daemon:` prefix is
 * stripped by `ipc::bridge_line` (e.g. `daemon:log` → `daemon://log`).
 */
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";
import type {
  ConfigPayload,
  DaemonEvent,
  DaemonLogEvent,
  FindingEdit,
  DaemonState,
  PendingReview,
  PollFoundEvent,
  PollSkippedEvent,
  PublishReviewEvent,
  ReviewFileEvent,
} from "@pr-review/shared";

// ---------------------------------------------------------------------------
// Config + command types
// ---------------------------------------------------------------------------

/** User-editable config fields. Internal paths (dbPath/logDir) are injected by
 *  the Rust host before forwarding to the daemon. */
export interface UiConfig {
  githubUsername: string;
  githubPat: string;
  llmProvider: string;
  llmBaseUrl: string;
  llmApiKey: string;
  llmJsonMode: boolean;
  llmModel: string;
  pollIntervalMin: number;
  showSeverity: boolean;
  osNotify: boolean;
  reviewMode: "auto" | "pending";
  reviewRules: string;
  repoInclude: string;
  repoExclude: string;
  triggerLabels: string;
  skipLabels: string;
}

/** Response shape of `daemon_status()`. */
export interface DaemonStatusSnapshot {
  online: boolean;
  state: DaemonState | string;
}

// ---------------------------------------------------------------------------
// invoke wrappers
// ---------------------------------------------------------------------------

export const getConfig = (): Promise<unknown> => invoke("get_config");

export const saveConfig = (config: Partial<UiConfig>): Promise<void> =>
  invoke("save_config", { config });

export const pollNow = (): Promise<void> => invoke("poll_now");

export const pauseDaemon = (): Promise<void> => invoke("pause_daemon");

export const resumeDaemon = (): Promise<void> => invoke("resume_daemon");

export const getDaemonStatus = (): Promise<DaemonStatusSnapshot> =>
  invoke("daemon_status");

export const testGithubConnection = (pat: string): Promise<string> =>
  invoke("test_github_connection", { pat });

export const testLlmConnection = (
  baseUrl: string,
  apiKey: string,
  model: string,
): Promise<string> =>
  invoke("test_llm_connection", { baseUrl, apiKey, model });
export const listLlmModels = (
  baseUrl: string,
  apiKey: string,
): Promise<string[]> =>
  invoke("list_llm_models", { baseUrl, apiKey });

// ---- pending review commands ----

export const approveReview = (
  reviewId: number,
  findingIds?: string[],
  edits?: Record<string, FindingEdit>,
): Promise<void> =>
  invoke("approve_review", {
    reviewId,
    findingIds: findingIds ?? null,
    edits: edits ?? null,
  });

export const rejectReview = (reviewId: number): Promise<void> =>
  invoke("reject_review", { reviewId });

export const listPendingReviews = (): Promise<void> =>
  invoke("list_pending_reviews");


// ---------------------------------------------------------------------------
// listen wrappers
// ---------------------------------------------------------------------------

// ---- typed convenience listeners ------------------------------------------

export function onDaemonStatus(
  cb: (state: DaemonState, msg: string | undefined) => void,
): Promise<UnlistenFn> {
  return listen<DaemonEvent>("daemon://status", (e) => {
    const ev = e.payload as Extract<DaemonEvent, { event: "daemon:status" }>;
    cb(ev.state, ev.msg);
  });
}

export function onDaemonLog(
  cb: (level: DaemonLogEvent["level"], msg: string) => void,
): Promise<UnlistenFn> {
  return listen<DaemonLogEvent>("daemon://log", (e) => {
    cb(e.payload.level, e.payload.msg);
  });
}

export function onPollFound(
  cb: (pr: PollFoundEvent["pr"]) => void,
): Promise<UnlistenFn> {
  return listen<PollFoundEvent>("daemon://poll:found", (e) => {
    cb(e.payload.pr);
  });
}

export function onPollSkipped(
  cb: (prId: number, reason: "merged" | "closed") => void,
): Promise<UnlistenFn> {
  return listen<PollSkippedEvent>("daemon://poll:skipped", (e) => {
    cb(e.payload.prId, e.payload.reason);
  });
}
export function onPollStarted(cb: () => void): Promise<UnlistenFn> {
  return listen("daemon://poll:started", () => cb());
}

export function onReviewFile(
  cb: (
    prId: number,
    file: string,
    status: ReviewFileEvent["status"],
    findings: number,
  ) => void,
): Promise<UnlistenFn> {
  return listen<ReviewFileEvent>("daemon://review:file", (e) => {
    cb(e.payload.prId, e.payload.file, e.payload.status, e.payload.findings);
  });
}

export function onPublishReview(
  cb: (review: PublishReviewEvent) => void,
): Promise<UnlistenFn> {
  return listen<PublishReviewEvent>("daemon://publish:review", (e) => {
    cb(e.payload);
  });
}

export function onDaemonReady(cb: () => void): Promise<UnlistenFn> {
  return listen("daemon://ready", () => cb());
}

export function onDaemonError(
  cb: (code: string, err: string) => void,
): Promise<UnlistenFn> {
  return listen<Extract<DaemonEvent, { event: "daemon:error" }>>(
    "daemon://error",
    (e) => {
      cb(e.payload.code, e.payload.err);
    },
  );
}

// ---- pending review listeners ---------------------------------------------

export function onReviewPending(
  cb: (r: PendingReview) => void,
): Promise<UnlistenFn> {
  return listen<PendingReview>("daemon://review:pending", (e) =>
    cb(e.payload),
  );
}

export function onPendingSnapshot(
  cb: (reviews: PendingReview[]) => void,
): Promise<UnlistenFn> {
  return listen<{ reviews: PendingReview[] }>(
    "daemon://pending:snapshot",
    (e) => cb(e.payload.reviews),
  );
}

export function onPendingResolved(
  cb: (reviewId: number, prId: number, status: string) => void,
): Promise<UnlistenFn> {
  return listen<{ reviewId: number; prId: number; status: string }>(
    "daemon://pending:resolved",
    (e) => cb(e.payload.reviewId, e.payload.prId, e.payload.status),
  );
}

// ---------------------------------------------------------------------------
// Config helpers
// ---------------------------------------------------------------------------

/** Known LLM providers with preset base URLs. */
export const LLM_PROVIDERS = [
  {
    id: "glm",
    label: "GLM Coding Plan (Zhipu AI)",
    baseUrl: "https://api.z.ai/api/coding/paas/v4",
  },
] as const;

export type LlmProviderId = (typeof LLM_PROVIDERS)[number]["id"];

/** Default config used by the wizard + settings when no persisted config exists. */
export const DEFAULT_CONFIG: UiConfig = {
  githubUsername: "",
  githubPat: "",
  llmProvider: "glm",
  llmBaseUrl: LLM_PROVIDERS[0].baseUrl,
  llmApiKey: "",
  llmJsonMode: true,
  llmModel: "",
  pollIntervalMin: 15,
  showSeverity: true,
  osNotify: false,
  reviewMode: "auto",
  reviewRules: "",
  repoInclude: "",
  repoExclude: "",
  triggerLabels: "",
  skipLabels: "",
};

/**
 * Coerce an arbitrary persisted value (from `get_config()`) into a fully-formed
 * `UiConfig`, filling missing fields with defaults. This handles first-run
 * (null) and partial / forward-compatible configs gracefully.
 */
export function normalizeConfig(raw: unknown): UiConfig {
  if (typeof raw !== "object" || raw === null) return { ...DEFAULT_CONFIG };
  const obj = raw as Record<string, unknown>;
  return {
    githubUsername: String(obj.githubUsername ?? ""),
    githubPat: String(obj.githubPat ?? ""),
    llmProvider: String(obj.llmProvider ?? "openai"),
    llmBaseUrl: String(obj.llmBaseUrl ?? ""),
    llmApiKey: String(obj.llmApiKey ?? ""),
    llmModel: String(obj.llmModel ?? ""),
    llmJsonMode:
      typeof obj.llmJsonMode === "boolean"
        ? obj.llmJsonMode
        : DEFAULT_CONFIG.llmJsonMode,
    pollIntervalMin:
      typeof obj.pollIntervalMin === "number"
        ? obj.pollIntervalMin
        : DEFAULT_CONFIG.pollIntervalMin,
    showSeverity:
      typeof obj.showSeverity === "boolean"
        ? obj.showSeverity
        : DEFAULT_CONFIG.showSeverity,
    osNotify:
      typeof obj.osNotify === "boolean" ? obj.osNotify : DEFAULT_CONFIG.osNotify,
    reviewMode:
      typeof obj.reviewMode === "string" && ["auto", "pending"].includes(obj.reviewMode)
        ? (obj.reviewMode as "auto" | "pending")
        : DEFAULT_CONFIG.reviewMode,
    reviewRules: typeof obj.reviewRules === "string" ? obj.reviewRules : "",
    repoInclude: typeof obj.repoInclude === "string" ? obj.repoInclude : "",
    repoExclude: typeof obj.repoExclude === "string" ? obj.repoExclude : "",
    triggerLabels: typeof obj.triggerLabels === "string" ? obj.triggerLabels : "",
    skipLabels: typeof obj.skipLabels === "string" ? obj.skipLabels : "",
  };
}

/** Determine whether a config has the minimum fields to skip the wizard. */
export function isConfigComplete(config: UiConfig | null): boolean {
  if (!config) return false;
  return (
    config.githubPat.length > 0 &&
    config.llmBaseUrl.length > 0 &&
    config.llmApiKey.length > 0 &&
    config.llmModel.length > 0
  );
}

// Re-export shared types for convenience.
export type { ConfigPayload, DaemonState };
