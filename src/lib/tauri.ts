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
  UsageSummary,
  ReviewHistoryEntry,
  StatsSummary,
  DailyStat,
  FindingFeedback,
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
  fileInclude: string;
  fileExclude: string;
  maxDiffLines: number;
  maxFiles: number;
  largePrPolicy: "trim" | "abort";
  llmPricing: string;
  defaultPer1M: number;
  monthlyBudgetUsd: number;
  botAuthors: string;
  botPolicy: "skip" | "review";
  incrementalReview: boolean;
  reviewAreas: string;
  replyToThreads: boolean;
  maxConcurrentReviews: number;
  /** True when the OS keyring was unavailable and the secret is stored in
   *  plaintext config.json (Linux without Secret Service). Set by the host. */
  githubPatInsecureFallback: boolean;
  llmApiKeyInsecureFallback: boolean;
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

// ---- cost & budget commands ----

export const getUsage = (): Promise<UsageSummary> =>
  invoke("get_usage");

// ---- history & stats commands (#8/#11) ----

export const getHistory = (filters?: {
  repo?: string;
  since?: string;
  until?: string;
  severity?: string;
  author?: string;
  limit?: number;
}): Promise<void> => invoke("get_history", filters ?? {});

export const getStats = (since: string, days: number): Promise<void> =>
  invoke("get_stats", { since, days });

export const markFinding = (
  prId: number,
  findingKey: string,
  file: string,
  line: number | null,
  comment: string,
  area: string | null,
  severity: string | null,
  feedback: FindingFeedback,
): Promise<void> =>
  invoke("mark_finding", { prId, findingKey, file, line, comment, area, severity, feedback });

// ---- auto-update commands (G003) ----

/** Check for an available app update. Returns "up-to-date" or
 *  "update-available: <version>" (or throws on error). Status only. */
export const checkForUpdates = (): Promise<string> =>
  invoke("check_for_updates");

/** Download + install the latest update (if any), then restart the app. */
export const installUpdate = (): Promise<void> =>
  invoke("install_update");


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

// ---- usage summary listener (G001) ----------------------------------------

export function onUsageSummary(
  cb: (summary: UsageSummary) => void,
): Promise<UnlistenFn> {
  return listen<{ summary: UsageSummary }>(
    "daemon://usage:summary",
    (e) => cb(e.payload.summary),
  );
}

// ---- history & stats listeners (#8/#11) ------------------------------------

export function onHistorySnapshot(
  cb: (reviews: ReviewHistoryEntry[]) => void,
): Promise<UnlistenFn> {
  return listen<{ reviews: ReviewHistoryEntry[]}>(
    "daemon://history:snapshot",
    (e) => cb(e.payload.reviews),
  );
}

export function onStatsSnapshot(
  cb: (summary: StatsSummary, daily: DailyStat[]) => void,
): Promise<UnlistenFn> {
  return listen<{ summary: StatsSummary; daily: DailyStat[]}>(
    "daemon://stats:snapshot",
    (e) => cb(e.payload.summary, e.payload.daily),
  );
}

// ---- auto-update status listener (G003) ------------------------------------

/** Listen for tray-triggered update checks. Payload is the same status string
 *  returned by `checkForUpdates` ("up-to-date" / "update-available: <v>" /
 *  "error: …"). */
export function onUpdateStatus(cb: (status: string) => void): Promise<UnlistenFn> {
  return listen<string>("daemon://update:status", (e) => cb(e.payload));
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
  fileInclude: "",
  fileExclude: "",
  maxDiffLines: 5000,
  maxFiles: 50,
  largePrPolicy: "trim",
  llmPricing: "",
  defaultPer1M: 0,
  monthlyBudgetUsd: 0,
  botAuthors: "",
  botPolicy: "skip",
  incrementalReview: false,
  reviewAreas: "bug,style,structure,security",
  replyToThreads: false,
  maxConcurrentReviews: 1,
  githubPatInsecureFallback: false,
  llmApiKeyInsecureFallback: false,
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
    fileInclude: typeof obj.fileInclude === "string" ? obj.fileInclude : "",
    fileExclude: typeof obj.fileExclude === "string" ? obj.fileExclude : "",
    maxDiffLines:
      typeof obj.maxDiffLines === "number"
        ? obj.maxDiffLines
        : DEFAULT_CONFIG.maxDiffLines,
    maxFiles:
      typeof obj.maxFiles === "number"
        ? obj.maxFiles
        : DEFAULT_CONFIG.maxFiles,
    largePrPolicy:
      typeof obj.largePrPolicy === "string" &&
      ["trim", "abort"].includes(obj.largePrPolicy)
        ? (obj.largePrPolicy as "trim" | "abort")
        : DEFAULT_CONFIG.largePrPolicy,
    llmPricing: typeof obj.llmPricing === "string" ? obj.llmPricing : "",
    defaultPer1M:
      typeof obj.defaultPer1M === "number"
        ? obj.defaultPer1M
        : DEFAULT_CONFIG.defaultPer1M,
    monthlyBudgetUsd:
      typeof obj.monthlyBudgetUsd === "number"
        ? obj.monthlyBudgetUsd
        : DEFAULT_CONFIG.monthlyBudgetUsd,
    botAuthors: typeof obj.botAuthors === "string" ? obj.botAuthors : "",
    botPolicy:
      typeof obj.botPolicy === "string" &&
      ["skip", "review"].includes(obj.botPolicy)
        ? (obj.botPolicy as "skip" | "review")
        : DEFAULT_CONFIG.botPolicy,
    incrementalReview:
      typeof obj.incrementalReview === "boolean"
        ? obj.incrementalReview
        : DEFAULT_CONFIG.incrementalReview,
    reviewAreas: typeof obj.reviewAreas === "string" ? obj.reviewAreas : DEFAULT_CONFIG.reviewAreas,
    replyToThreads:
      typeof obj.replyToThreads === "boolean"
        ? obj.replyToThreads
        : DEFAULT_CONFIG.replyToThreads,
    maxConcurrentReviews:
      typeof obj.maxConcurrentReviews === "number"
        ? obj.maxConcurrentReviews
        : DEFAULT_CONFIG.maxConcurrentReviews,
    githubPatInsecureFallback:
      typeof obj.githubPatInsecureFallback === "boolean"
        ? obj.githubPatInsecureFallback
        : false,
    llmApiKeyInsecureFallback:
      typeof obj.llmApiKeyInsecureFallback === "boolean"
        ? obj.llmApiKeyInsecureFallback
        : false,
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
export type { ConfigPayload, DaemonState, UsageSummary };
