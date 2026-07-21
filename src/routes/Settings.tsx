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
} from "../lib/tauri";
import { useToast } from "../components/ui/Toast";
import { Icon } from "../components/ui/Icon";

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
        </div>
      </div>

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
