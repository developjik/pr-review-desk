/**
 * Settings — full configuration form.
 *
 * Grouped into three cards (GitHub / LLM / Behavior), each with a header and
 * icon. GitHub and LLM cards include "Test Connection" actions. Loads the
 * persisted config on mount, saves via `save_config` with a debounce guard.
 */
import { useEffect, useRef, useState } from "react";
import {
  type UiConfig,
  LLM_PROVIDERS,
  type LlmProviderId,
  DEFAULT_CONFIG,
  getConfig,
  normalizeConfig,
  saveConfig,
  testGithubConnection,
  testLlmConnection,
  getUsage,
  onUsageSummary,
  type UsageSummary,
  checkForUpdates,
  installUpdate,
  onUpdateStatus,
} from "../lib/tauri";
import { useToast } from "../components/ui/Toast";
import { Icon } from "../components/ui/Icon";


/**
 * CostBudgetCard — shows monthly LLM spend + cost inputs (G001).
 *
 * Fetches usage on mount via getUsage() and subscribes to the usage:summary event
 * for live updates. Config inputs (budget / pricing / default rate) use the
 * parent Settings `update()` helper so they persist with the rest of the form.
 */
function CostBudgetCard({
  config,
  update,
}: {
  config: UiConfig;
  update: <K extends keyof UiConfig>(key: K, value: UiConfig[K]) => void;
}) {
  const [usage, setUsage] = useState<UsageSummary | null>(null);

  useEffect(() => {
    let unlisten: (() => void) | undefined;
    getUsage()
      .then(setUsage)
      .catch(() => undefined);
    onUsageSummary(setUsage).then((fn) => {
      unlisten = fn;
    });
    return () => {
      unlisten?.();
    };
  }, []);

  const budget = config.monthlyBudgetUsd;
  const cost = usage?.monthlyCost ?? 0;
  const tokens = usage?.tokensThisMonth ?? 0;
  const paused = usage?.paused ?? false;
  const pct = budget > 0 ? Math.min(100, (cost / budget) * 100) : 100;

  return (
    <div className="card">
      <div className="card-header">
        <span className="card-icon"><Icon name="bar-chart-2" /></span>
        <h3>Cost &amp; Budget</h3>
      </div>
      <div className="card-body">
        <div className="field">
          <span className="field-label">This month</span>
          <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", flexWrap: "wrap" }}>
            <span>
              This month: ${cost.toFixed(2)} /{" "}
              {budget > 0 ? `$${budget}` : "unlimited"}{" "}
              ({tokens.toLocaleString()} tokens)
            </span>
            {paused && (
              <span
                style={{
                  display: "inline-flex",
                  alignItems: "center",
                  gap: "0.25rem",
                  padding: "0.125rem 0.5rem",
                  borderRadius: "999px",
                  fontSize: "0.75rem",
                  fontWeight: 600,
                  background: "var(--danger, #ef4444)",
                  color: "#fff",
                }}
              >
                <Icon name="pause" size="sm" /> Budget exceeded — reviews paused
              </span>
            )}
          </div>
          {/* Inline progress bar */}
          <svg
            width="100%"
            height="8"
            viewBox="0 0 100 8"
            preserveAspectRatio="none"
            style={{ display: "block", marginTop: "0.5rem", borderRadius: "4px" }}
          >
            <rect x="0" y="0" width="100" height="8" rx="4" fill="var(--surface-border, #e5e7eb)" />
            <rect
              x="0"
              y="0"
              width={pct}
              height="8"
              rx="4"
              fill={paused ? "var(--danger, #ef4444)" : "var(--primary, #3b82f6)"}
            />
          </svg>
        </div>

        <div className="field">
          <span className="field-label">Monthly budget (USD)</span>
          <input
            type="number"
            className="input"
            min={0}
            value={config.monthlyBudgetUsd}
            onChange={(e) =>
              update("monthlyBudgetUsd", Number(e.target.value) || DEFAULT_CONFIG.monthlyBudgetUsd)
            }
          />
          <p className="hint">
            Maximum monthly LLM spend. 0 = unlimited. When exceeded, new reviews
            are paused until next month.
          </p>
        </div>

        <div className="field">
          <span className="field-label">Default rate ($/1M tokens)</span>
          <input
            type="number"
            className="input"
            min={0}
            step="0.1"
            value={config.defaultPer1M}
            onChange={(e) =>
              update("defaultPer1M", Number(e.target.value) || DEFAULT_CONFIG.defaultPer1M)
            }
          />
          <p className="hint">
            Blended fallback $/1M tokens for models not listed below. 0 =
            free/unknown.
          </p>
        </div>

        <div className="field">
          <span className="field-label">Per-model pricing</span>
          <textarea
            className="input"
            rows={6}
            value={config.llmPricing}
            onChange={(e) => update("llmPricing", e.target.value)}
            placeholder={"Newline-separated model:promptPer1M,completionPer1M, e.g.\ngpt-4o:2.50,10.00\nglm-5.2:0.50,1.50\nEmpty = use the default rate above for all models."}
            style={{
              fontFamily: '"SF Mono", ui-monospace, monospace',
              resize: "vertical",
            }}
          />
          <p className="hint">
            Newline-separated{" "}
            <code>model:promptPer1M,completionPer1M</code> rates. Unknown models
            fall back to the default rate. Changes apply on the next review.
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * UpdateCard — manual "Check for updates" trigger (G003, Rust-driven).
 *
 * Calls the `check_for_updates` command and shows the status text. When an
 * update is available it offers a confirm → install path (`install_update`
 * downloads, verifies the signature, and restarts). Also subscribes to
 * `daemon://update:status` so tray "Check for Updates…" clicks surface here.
 */
function UpdateCard() {
  type UpdateState =
    | "idle"
    | "checking"
    | "up-to-date"
    | "available"
    | "installing"
    | "error";
  const [state, setState] = useState<UpdateState>("idle");
  const [version, setVersion] = useState("");
  const [msg, setMsg] = useState("");
  const toast = useToast();

  useEffect(() => {
    // Surface tray-triggered update checks in this card.
    const unlistenP = onUpdateStatus((status) => {
      if (status.startsWith("update-available:")) {
        setVersion(status.slice("update-available:".length).trim());
        setState("available");
      } else if (status === "up-to-date") {
        setState("up-to-date");
      } else if (status.startsWith("error:")) {
        setMsg(status);
        setState("error");
      }
    });
    return () => {
      unlistenP.then((fn) => fn());
    };
  }, []);

  const handleCheck = async () => {
    setState("checking");
    setMsg("");
    try {
      const status = await checkForUpdates();
      if (status.startsWith("update-available:")) {
        setVersion(status.slice("update-available:".length).trim());
        setState("available");
      } else {
        setState("up-to-date");
      }
    } catch (e) {
      setMsg(e instanceof Error ? e.message : String(e));
      setState("error");
    }
  };

  const handleInstall = async () => {
    setState("installing");
    setMsg("");
    try {
      await installUpdate();
      // install_update() restarts the app on success — unreachable on success.
    } catch (e) {
      const m = e instanceof Error ? e.message : String(e);
      setMsg(m);
      setState("error");
      toast.error("업데이트 설치에 실패했어요.", m);
    }
  };

  return (
    <div className="card">
      <div className="card-header">
        <span className="card-icon"><Icon name="refresh-cw" /></span>
        <h3>About &amp; Updates</h3>
      </div>
      <div className="card-body">
        <div className="field">
          <span className="field-label">Application updates</span>
          <div className="test-row">
            <button
              type="button"
              className={`test-btn ${state === "checking" ? "is-testing" : ""}`}
              disabled={state === "checking" || state === "installing"}
              onClick={handleCheck}
            >
              {state === "checking" ? "Checking…" : "Check for updates"}
            </button>
            {state === "up-to-date" && (
              <span className="test-ok">✓ You're up to date</span>
            )}
            {state === "available" && (
              <span className="test-ok">↻ Update available: {version}</span>
            )}
            {state === "error" && (
              <span className="test-fail">✕ {msg}</span>
            )}
          </div>
          {(state === "available" || state === "installing") && (
            <div className="field" style={{ marginTop: "0.75rem" }}>
              <button
                type="button"
                className="btn btn-primary"
                disabled={state === "installing"}
                data-loading={state === "installing"}
                onClick={handleInstall}
              >
                {state === "installing" ? "Installing…" : "Install & restart"}
              </button>
              <p className="hint">
                Downloads the update, verifies its signature, and restarts the
                app.
              </p>
            </div>
          )}
          <p className="hint">
            Checks the release feed for a newer signed build. Auto-update
            requires the signing key to be configured (see the README's
            "Auto-update signing" section).
          </p>
        </div>
      </div>
    </div>
  );
}
interface SettingsProps {
  onSaved?: () => void;
  onOpenInstallHelp?: () => void;
}

type SaveState = "idle" | "saving" | "saved" | "error";
type TestState = { state: "idle" | "testing" | "ok" | "fail"; msg: string };

export default function Settings({ onSaved, onOpenInstallHelp }: SettingsProps) {
  const [config, setConfig] = useState<UiConfig>({ ...DEFAULT_CONFIG });
  const [loaded, setLoaded] = useState(false);
  const [saveState, setSaveState] = useState<SaveState>("idle");
  const [error, setError] = useState<string | null>(null);
  const [ghTest, setGhTest] = useState<TestState>({ state: "idle", msg: "" });
  const [llmTest, setLlmTest] = useState<TestState>({ state: "idle", msg: "" });
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const toast = useToast();

  // Load persisted config once.
  useEffect(() => {
    getConfig()
      .then((raw) => setConfig(normalizeConfig(raw)))
      .catch(() => {
        /* ignore; keep defaults */
      })
      .finally(() => setLoaded(true));
  }, []);

  const update = <K extends keyof UiConfig>(key: K, value: UiConfig[K]) => {
    setConfig((prev) => ({ ...prev, [key]: value }));
  };

  const selectProvider = (id: LlmProviderId) => {
    const provider = LLM_PROVIDERS.find((p) => p.id === id);
    update("llmProvider", id);
    if (provider && provider.baseUrl) {
      update("llmBaseUrl", provider.baseUrl);
    }
  };

  const handleTestGithub = async () => {
    setGhTest({ state: "testing", msg: "" });
    try {
      const username = await testGithubConnection(config.githubPat);
      setGhTest({ state: "ok", msg: `Connected as @${username}` });
    } catch (e) {
      setGhTest({
        state: "fail",
        msg: e instanceof Error ? e.message : String(e),
      });
    }
  };

  const handleTestLlm = async () => {
    setLlmTest({ state: "testing", msg: "" });
    try {
      const msg = await testLlmConnection(
        config.llmBaseUrl,
        config.llmApiKey,
        config.llmModel,
      );
      setLlmTest({ state: "ok", msg });
    } catch (e) {
      setLlmTest({
        state: "fail",
        msg: e instanceof Error ? e.message : String(e),
      });
    }
  };

  const handleSave = () => {
    if (debounceRef.current) return;
    setSaveState("saving");
    setError(null);

    saveConfig(config)
      .then(() => {
        setSaveState("saved");
        toast.success("설정을 저장했어요.");
        onSaved?.();
        debounceRef.current = setTimeout(() => {
          debounceRef.current = null;
        }, 1000);
        setTimeout(() => setSaveState("idle"), 2000);
      })
      .catch((e) => {
        const msg = e instanceof Error ? e.message : String(e);
        setError(msg);
        setSaveState("error");
        toast.error("설정 저장에 실패했어요.", msg);
      });
  };

  if (!loaded) {
    return (
      <section className="page">
        <div className="empty-state">
          <span className="empty-icon"><Icon name="settings" size="lg" /></span>
          <span className="empty-text">Loading settings…</span>
        </div>
      </section>
    );
  }

  return (
    <section className="page settings">
      <div className="page-header">
        <h2>Settings</h2>
        <p>
          Configure your GitHub credentials, LLM provider, and daemon behavior.
        </p>
        <button
          type="button"
          className="link-btn"
          onClick={() => onOpenInstallHelp?.()}
        >
          <Icon name="help-circle" /> 서명/설치 도움말
        </button>
      </div>

      {/* GitHub */}
      <div className="card">
        <div className="card-header">
          <span className="card-icon"><Icon name="github" /></span>
          <h3>GitHub</h3>
        </div>
        <div className="card-body">
          <div className="field">
            <span className="field-label">Personal Access Token</span>
            <input
              type="password"
              className="input"
              value={config.githubPat}
              onChange={(e) => update("githubPat", e.target.value)}
              placeholder="ghp_…"
            />
          </div>
          {config.githubPatInsecureFallback && (
            <p className="hint" style={{ color: "var(--warning)" }}>
              ⚠ Stored insecurely — no OS keyring on this system. The token is
              saved in plaintext in config.json.
            </p>
          )}
          <div className="test-row">
            <button
              type="button"
              className={`test-btn ${ghTest.state === "testing" ? "is-testing" : ""}`}
              disabled={!config.githubPat.trim() || ghTest.state === "testing"}
              onClick={handleTestGithub}
            >
              {ghTest.state === "testing" ? "Testing…" : "Test Connection"}
            </button>
            {ghTest.state === "ok" && (
              <span className="test-ok">✓ {ghTest.msg}</span>
            )}
            {ghTest.state === "fail" && (
              <span className="test-fail">✕ {ghTest.msg}</span>
            )}
          </div>
          <p className="hint">
            Username is auto-detected from your token. The PAT needs{" "}
            <code>repo</code> scope.
          </p>
        </div>
      </div>

      {/* LLM */}
      <div className="card">
        <div className="card-header">
          <span className="card-icon"><Icon name="bot" /></span>
          <h3>LLM Provider</h3>
        </div>
        <div className="card-body">
          <div className="field">
            <span className="field-label">Provider</span>
            <select
              value={config.llmProvider}
              onChange={(e) => selectProvider(e.target.value as LlmProviderId)}
            >
              {LLM_PROVIDERS.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.label}
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <span className="field-label">Base URL</span>
            <input
              type="text"
              className="input"
              value={config.llmBaseUrl}
              onChange={(e) => update("llmBaseUrl", e.target.value)}
              placeholder="https://api.openai.com/v1"
            />
          </div>
          <div className="field">
            <span className="field-label">API Key</span>
            <input
              type="password"
              className="input"
              value={config.llmApiKey}
              onChange={(e) => update("llmApiKey", e.target.value)}
              placeholder="sk-…"
            />
          </div>
          {config.llmApiKeyInsecureFallback && (
            <p className="hint" style={{ color: "var(--warning)" }}>
              ⚠ Stored insecurely — no OS keyring on this system. The key is
              saved in plaintext in config.json.
            </p>
          )}
          <div className="field">
            <span className="field-label">Model</span>
            <input
              type="text"
              className="input"
              value={config.llmModel}
              onChange={(e) => update("llmModel", e.target.value)}
              placeholder="gpt-4o"
            />
          </div>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={config.llmJsonMode}
              onChange={(e) => update("llmJsonMode", e.target.checked)}
            />
            JSON Mode{" "}
            <span className="hint">
              (disable if your LLM provider returns errors about response_format)
            </span>
          </label>
          <div className="test-row">
            <button
              type="button"
              className={`test-btn ${llmTest.state === "testing" ? "is-testing" : ""}`}
              disabled={
                !config.llmApiKey.trim() ||
                !config.llmModel.trim() ||
                llmTest.state === "testing"
              }
              onClick={handleTestLlm}
            >
              {llmTest.state === "testing" ? "Testing…" : "Test Connection"}
            </button>
            {llmTest.state === "ok" && (
              <span className="test-ok">✓ {llmTest.msg}</span>
            )}
            {llmTest.state === "fail" && (
              <span className="test-fail">✕ {llmTest.msg}</span>
            )}
          </div>
        </div>
      </div>

      {/* Behavior */}
      <div className="card">
        <div className="card-header">
          <span className="card-icon"><Icon name="zap" /></span>
          <h3>Behavior</h3>
        </div>
        <div className="card-body">
          <div className="field">
            <span className="field-label">Poll Interval</span>
            <div className="range-row">
              <input
                type="range"
                min={1}
                max={120}
                value={config.pollIntervalMin}
                onChange={(e) =>
                  update("pollIntervalMin", Number(e.target.value))
                }
              />
              <span className="range-value">{config.pollIntervalMin}m</span>
            </div>
          </div>
          <div className="field">
            <span className="field-label">Review Mode</span>
            <div className="segmented-control">
              <button
                type="button"
                className={config.reviewMode === "auto" ? "active" : ""}
                onClick={() => update("reviewMode", "auto")}
              >
                Auto (즉시 게시)
              </button>
              <button
                type="button"
                className={config.reviewMode === "pending" ? "active" : ""}
                onClick={() => update("reviewMode", "pending")}
              >
                Pending (승인 후 게시)
              </button>
            </div>
          </div>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={config.showSeverity}
              onChange={(e) => update("showSeverity", e.target.checked)}
            />
            Show severity badges in reviews
          </label>
          <label className="checkbox-field">
            <input
              type="checkbox"
              checked={config.osNotify}
              onChange={(e) => update("osNotify", e.target.checked)}
            />
            OS notification on review completion
          </label>
        </div>
      </div>

      {/* Custom review guidelines */}
      <div className="card">
        <div className="card-header">
          <span className="card-icon"><Icon name="list" /></span>
          <h3>Custom Review Guidelines</h3>
        </div>
        <div className="card-body">
          <div className="field">
            <span className="field-label">Custom review guidelines</span>
            <textarea
              className="input"
              rows={6}
              value={config.reviewRules}
              onChange={(e) => update("reviewRules", e.target.value)}
              placeholder="Free-form team rules. Per-repo .prreview/rules.md rules are appended AFTER these and take precedence where they conflict."
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
          </div>
          <p className="hint">
            Free-form team rules. Per-repo .prreview/rules.md rules are appended
            AFTER these and take precedence where they conflict.
          </p>
        </div>
      </div>

      {/* Repo & label filters */}
      <div className="card">
        <div className="card-header">
          <span className="card-icon"><Icon name="filter" /></span>
          <h3>Repo &amp; Label Filters</h3>
        </div>
        <div className="card-body">
          <div className="field">
            <span className="field-label">Repo include (optional)</span>
            <textarea
              className="input"
              rows={6}
              value={config.repoInclude}
              onChange={(e) => update("repoInclude", e.target.value)}
              placeholder={"Newline-separated glob patterns, e.g.\nmyorg/*\notherorg/important-repo\nOnly PRs in matching repos are reviewed. Empty = all repos."}
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
          </div>
          <div className="field">
            <span className="field-label">Repo exclude (optional)</span>
            <textarea
              className="input"
              rows={6}
              value={config.repoExclude}
              onChange={(e) => update("repoExclude", e.target.value)}
              placeholder={"Newline-separated glob patterns, e.g.\nmyorg/legacy-*\notherorg/noisy-repo\nPRs in matching repos are skipped. Use this instead of `!` negation."}
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
          </div>
          <div className="field">
            <span className="field-label">Trigger labels (optional)</span>
            <textarea
              className="input"
              rows={6}
              value={config.triggerLabels}
              onChange={(e) => update("triggerLabels", e.target.value)}
              placeholder={"Newline-separated labels, e.g.\nreview-requested\nneeds-review\nWhen set, a PR is only reviewed if it has at least one of these labels. Empty = review all (not gated by labels)."}
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
          </div>
          <div className="field">
            <span className="field-label">Skip labels (optional)</span>
            <textarea
              className="input"
              rows={6}
              value={config.skipLabels}
              onChange={(e) => update("skipLabels", e.target.value)}
              placeholder={"Newline-separated labels, e.g.\nwip\nbot:skip\nPRs with any of these labels are never reviewed."}
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
          </div>
          <p className="hint">
            Repo patterns use only <code>*</code>/<code>?</code> (no{" "}
            <code>!</code> negation — use Exclude). Matching is case-insensitive
            and applied to <code>owner/repo</code>. Labels are also
            case-insensitive. Empty filters = today's behavior (all repos, no
            label gating). Changes apply on the next poll (no restart needed).
          </p>
        <div className="field">
          <span className="field-label">Bot authors</span>
          <textarea
            rows={4}
            value={config.botAuthors}
            onChange={(e) => update("botAuthors", e.target.value)}
            placeholder={"Newline-separated bot logins to skip, e.g.\ndependabot\nrenovate\nPRs by these authors are not reviewed (Skip) when Bot policy = Skip."}
            style={{
              fontFamily: '"SF Mono", ui-monospace, monospace',
              resize: "vertical",
            }}
          />
        </div>
        <div className="field">
          <span className="field-label">Bot policy</span>
          <select
            value={config.botPolicy}
            onChange={(e) => update("botPolicy", e.target.value as "skip" | "review")}
          >
            <option value="skip">Skip (don't review bot PRs)</option>
            <option value="review">Review normally</option>
          </select>
          <p className="hint">
            When set to Skip, PRs authored by a login in <strong>Bot authors</strong>{" "}
            are filtered out before the review fetch (saves API calls + LLM cost).
          </p>
        </div>
        <div className="field">
          <label style={{ display: "inline-flex", alignItems: "center", gap: "0.5rem", cursor: "pointer" }}>
            <input
              type="checkbox"
              checked={config.incrementalReview}
              onChange={(e) => update("incrementalReview", e.target.checked)}
            />
            <span className="field-label" style={{ margin: 0 }}>
              Incremental review (new commits only)
            </span>
          </label>
          <p className="hint">
            When on, a PR pushed to after review is re-reviewed against only the{" "}
            <code>previousSha..head</code> compare (fewer tokens, lower cost). Falls back
            to a full review on force-push/rebase. Off by default.
          </p>
        </div>
        </div>
      </div>

      {/* File filters & review budgets */}
      <div className="card">
        <div className="card-header">
          <span className="card-icon"><Icon name="file-text" /></span>
          <h3>File Filters &amp; Review Budgets</h3>
        </div>
        <div className="card-body">
          <div className="field">
            <span className="field-label">File include patterns</span>
            <textarea
              className="input"
              rows={6}
              value={config.fileInclude}
              onChange={(e) => update("fileInclude", e.target.value)}
              placeholder={"Newline-separated globs of files to review, e.g.\nsrc/**\n*.ts\nEmpty = review all matching files."}
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
            <p className="hint">
              Newline-separated globs of files to review (e.g.{" "}
              <code>src/**</code>). Empty = review all matching files.
            </p>
          </div>
          <div className="field">
            <span className="field-label">File exclude patterns</span>
            <textarea
              className="input"
              rows={6}
              value={config.fileExclude}
              onChange={(e) => update("fileExclude", e.target.value)}
              placeholder={"Newline-separated globs to skip, e.g.\n**/*.generated.ts\nvendor/**\ndist/\nEmpty = exclude none."}
              style={{
                fontFamily: '"SF Mono", ui-monospace, monospace',
                resize: "vertical",
              }}
            />
            <p className="hint">
              Newline-separated globs to skip (e.g.{" "}
              <code>**/*.generated.ts</code>, <code>vendor/**</code>,{" "}
              <code>dist/</code>). Empty = exclude none.
            </p>
          </div>
          <div className="field">
            <span className="field-label">Max diff lines per file</span>
            <input
              type="number"
              className="input"
              min={1}
              value={config.maxDiffLines}
              onChange={(e) =>
                update("maxDiffLines", Number(e.target.value) || DEFAULT_CONFIG.maxDiffLines)
              }
            />
            <p className="hint">
              Skip files whose diff exceeds this many lines (default 5000).
            </p>
          </div>
          <div className="field">
            <span className="field-label">Max files per PR</span>
            <input
              type="number"
              className="input"
              min={1}
              value={config.maxFiles}
              onChange={(e) =>
                update("maxFiles", Number(e.target.value) || DEFAULT_CONFIG.maxFiles)
              }
            />
            <p className="hint">
              Max files reviewed per PR; lower-priority files trimmed beyond this
              (default 50).
            </p>
          </div>
          <div className="field">
            <span className="field-label">Large PR policy</span>
            <select
              value={config.largePrPolicy}
              onChange={(e) =>
                update("largePrPolicy", e.target.value as "trim" | "abort")
              }
            >
              <option value="trim">Trim to budget</option>
              <option value="abort">Abort review (skip all)</option>
            </select>
            <p className="hint">
              When a PR exceeds the file budget: trim lower-priority files, or
              abort the review entirely.
            </p>
          </div>
        <div className="field">
          <span className="field-label">Review areas</span>
          <div style={{ display: "flex", gap: "1rem", flexWrap: "wrap" }}>
            {(["bug", "style", "structure", "security"] as const).map((area) => {
              const enabled = config.reviewAreas
                .split(",")
                .map((a) => a.trim().toLowerCase())
                .includes(area);
              const next = enabled
                ? config.reviewAreas
                    .split(",")
                    .map((a) => a.trim())
                    .filter((a) => a.toLowerCase() !== area)
                : [...config.reviewAreas.split(",").map((a) => a.trim()).filter(Boolean), area];
              // Empty selection = all four (inert); order canonical.
              const ordered = ["bug", "style", "structure", "security"].filter((a) =>
                next.map((n) => n.toLowerCase()).includes(a),
              );
              const value = ordered.length === 0 || ordered.length === 4
                ? "bug,style,structure,security"
                : ordered.join(",");
              return (
                <label key={area} style={{ display: "inline-flex", alignItems: "center", gap: "0.35rem", cursor: "pointer" }}>
                  <input
                    type="checkbox"
                    checked={enabled}
                    onChange={() => update("reviewAreas", value)}
                  />
                  {area}
                </label>
              );
            })}
          </div>
          <p className="hint">
            Which review areas the LLM covers. All four = default. Disabling an area
            drops it from the review prompt (e.g. review only <code>bug</code> +{" "}
            <code>security</code>).
          </p>
        </div>
        </div>
      </div>

      {/* Cost & budget (G001) */}
      <CostBudgetCard config={config} update={update} />

      {/* Auto-update (G003) */}
      <UpdateCard />

      <div className="settings-actions">
        {saveState === "saved" && <span className="ok">Saved ✓</span>}
        {saveState === "error" && <span className="error">{error}</span>}
        <button
          type="button"
          className="btn btn-primary"
          onClick={handleSave}
          disabled={saveState === "saving"}
          data-loading={saveState === "saving"}
        >
          {saveState === "saving" ? "Saving…" : "Save Changes"}
        </button>
      </div>
    </section>
  );
}
