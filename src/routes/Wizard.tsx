/**
 * Wizard — first-run 3-step setup wizard.
 *
 * Steps:
 *   1. GitHub PAT
 *   2. LLM Configuration (provider + API key + model dropdown)
 *   3. Polling & Review Mode
 */
import { useState } from "react";
import { motion, AnimatePresence } from "motion/react";
import {
  type UiConfig,
  LLM_PROVIDERS,
  type LlmProviderId,
  saveConfig,
  testGithubConnection,
  testLlmConnection,
  listLlmModels,
} from "../lib/tauri";

interface WizardProps {
  initialConfig: UiConfig;
  onComplete: () => void;
}

type TestState = { state: "idle" | "testing" | "ok" | "fail"; msg: string };

const STEPS = ["GitHub", "LLM Setup", "Polling"] as const;

export default function Wizard({ initialConfig, onComplete }: WizardProps) {
  const [step, setStep] = useState(0);
  const [config, setConfig] = useState<UiConfig>({ ...initialConfig });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [ghTest, setGhTest] = useState<TestState>({ state: "idle", msg: "" });
  const [llmTest, setLlmTest] = useState<TestState>({ state: "idle", msg: "" });
  const [models, setModels] = useState<string[]>([]);
  const [fetchingModels, setFetchingModels] = useState(false);
  const [fetchError, setFetchError] = useState<string | null>(null);

  const update = <K extends keyof UiConfig>(key: K, value: UiConfig[K]) => {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setError(null);
  };

  const handleTestGithub = async () => {
    setGhTest({ state: "testing", msg: "" });
    try {
      const username = await testGithubConnection(config.githubPat);
      setGhTest({ state: "ok", msg: `Connected as @${username}` });
      update("githubUsername", username);
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

  const handleFetchModels = async () => {
    setFetchingModels(true);
    setFetchError(null);
    try {
      const list = await listLlmModels(config.llmBaseUrl, config.llmApiKey);
      setModels(list);
      if (list.length > 0 && !list.includes(config.llmModel)) {
        update("llmModel", list[0]);
      }
    } catch (e) {
      setFetchError(e instanceof Error ? e.message : String(e));
      setModels([]);
    } finally {
      setFetchingModels(false);
    }
  };

  const selectProvider = (id: LlmProviderId) => {
    const provider = LLM_PROVIDERS.find((p) => p.id === id);
    update("llmProvider", id);
    if (provider && provider.baseUrl) {
      update("llmBaseUrl", provider.baseUrl);
    }
    setModels([]);
    setFetchError(null);
  };

  const canAdvance = (): boolean => {
    switch (step) {
      case 0:
        return config.githubPat.trim().length > 0;
      case 1:
        return (
          config.llmProvider.length > 0 &&
          /^https?:\/\/[^\s]+$/i.test(config.llmBaseUrl) &&
          config.llmApiKey.trim().length > 0 &&
          config.llmModel.trim().length > 0
        );
      case 2:
        return config.pollIntervalMin > 0;
      default:
        return false;
    }
  };

  const handleFinish = async () => {
    setSaving(true);
    setError(null);
    try {
      await saveConfig(config);
      onComplete();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  };

  const next = () => {
    if (step < STEPS.length - 1 && canAdvance()) {
      setStep((s) => Math.min(STEPS.length - 1, s + 1));
    }
  };

  return (
    <section className="wizard">
      <div className="wizard-head">
        <h2>Welcome to PR Review</h2>
        <p>Let&apos;s get you set up in a few quick steps.</p>
      </div>

      <div className="wizard-progress">
        {STEPS.map((label, i) => (
          <div key={label} style={{ display: "contents" }}>
            {i > 0 && (
              <div className={`wizard-connector ${i <= step ? "done" : ""}`} />
            )}
            <div className={`wizard-step ${i === step ? "active" : ""}`}>
              <span
                className={`wizard-dot ${
                  i < step ? "done" : i === step ? "active" : ""
                }`}
              >
                {i < step ? "✓" : i + 1}
              </span>
              <span className="wizard-step-label">{label}</span>
            </div>
          </div>
        ))}
      </div>

      <div className="wizard-body">
        <AnimatePresence mode="wait">
        {step === 0 && (
          <motion.fieldset
            key="step-0"
            className="form-group"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2, ease: "easeOut" }}
          >
            <legend>Step 1 — GitHub</legend>
            <label>
              Personal Access Token (PAT)
              <input
                type="password"
                value={config.githubPat}
                onChange={(e) => update("githubPat", e.target.value)}
                placeholder="ghp_…"
                autoFocus
              />
            </label>
            <div className="test-row">
              <button
                type="button"
                className={`test-btn ${ghTest.state === "testing" ? "is-testing" : ""}`}
                disabled={
                  !config.githubPat.trim() || ghTest.state === "testing"
                }
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
              <code>repo</code> scope to read PRs and post review comments.
            </p>
          </motion.fieldset>
        )}

        {step === 1 && (
          <motion.fieldset
            key="step-1"
            className="form-group"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2, ease: "easeOut" }}
          >
            <legend>Step 2 — LLM Setup</legend>

            <label>
              Provider
              <select
                value={config.llmProvider}
                onChange={(e) =>
                  selectProvider(e.target.value as LlmProviderId)
                }
              >
                {LLM_PROVIDERS.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.label}
                  </option>
                ))}
              </select>
            </label>

            <label>
              Base URL
              <input
                type="text"
                value={config.llmBaseUrl}
                onChange={(e) => update("llmBaseUrl", e.target.value)}
                placeholder="https://api.z.ai/api/coding/paas/v4"
              />
            </label>

            <label>
              API Key
              <input
                type="password"
                value={config.llmApiKey}
                onChange={(e) => {
                  update("llmApiKey", e.target.value);
                  setModels([]);
                  setFetchError(null);
                }}
                placeholder="sk-…"
              />
            </label>

            <label>
              Model
              {models.length > 0 ? (
                <select
                  value={config.llmModel}
                  onChange={(e) => update("llmModel", e.target.value)}
                >
                  {models.map((m) => (
                    <option key={m} value={m}>
                      {m}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  type="text"
                  value={config.llmModel}
                  onChange={(e) => update("llmModel", e.target.value)}
                  placeholder="glm-4.6 또는 Fetch Models로 불러오기"
                />
              )}
            </label>

            {models.length === 0 && (
              <div className="test-row">
                <button
                  type="button"
                  className="test-btn"
                  disabled={
                    !config.llmApiKey.trim() ||
                    !config.llmBaseUrl.trim() ||
                    fetchingModels
                  }
                  onClick={handleFetchModels}
                >
                  {fetchingModels ? "불러오는 중…" : "Fetch Models"}
                </button>
                {fetchError && (
                  <span className="test-fail">✕ {fetchError}</span>
                )}
              </div>
            )}
            {models.length > 0 && (
              <p className="hint">
                ✓ {models.length}개 모델을 불러왔어요 — 다시 불러오려면 API Key를 수정하세요.
              </p>
            )}

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
          </motion.fieldset>
        )}

        {step === 2 && (
          <motion.fieldset
            key="step-2"
            className="form-group"
            initial={{ opacity: 0, x: 20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ duration: 0.2, ease: "easeOut" }}
          >
            <legend>Step 3 — Polling</legend>
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
            <label>
              Review Mode
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
            </label>
            <label>
              Custom review guidelines{" "}
              <span className="hint">(optional)</span>
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
            </label>
            <label>
              Repo include{" "}
              <span className="hint">(optional)</span>
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
            </label>
            <label>
              Repo exclude{" "}
              <span className="hint">(optional)</span>
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
            </label>
            <label>
              Trigger labels{" "}
              <span className="hint">(optional)</span>
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
            </label>
            <label>
              Skip labels{" "}
              <span className="hint">(optional)</span>
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
            </label>
            <p className="hint">
              The daemon checks for new PRs at this interval. Default: 15 min.
            </p>
          </motion.fieldset>
        )}

        {error && <p className="error">{error}</p>}
        </AnimatePresence>
      </div>

      <div className="wizard-nav">
        <button
          type="button"
          className="btn btn-secondary"
          disabled={step === 0 || saving}
          onClick={() => setStep((s) => Math.max(0, s - 1))}
        >
          Back
        </button>
        <div className="nav-right">
          {step < STEPS.length - 1 ? (
            <button
              type="button"
              className="btn btn-primary"
              disabled={!canAdvance()}
              onClick={next}
            >
              Next
            </button>
          ) : (
            <button
              type="button"
              className="btn btn-primary"
              disabled={!canAdvance() || saving}
              onClick={handleFinish}
            >
              {saving ? "Saving…" : "Finish"}
            </button>
          )}
        </div>
      </div>
    </section>
  );
}
