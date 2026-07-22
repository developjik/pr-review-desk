import { describe, it, expect } from "vitest";
import { parseConfig, configAffectsRuntime } from "./schema";

/** Minimal config object that satisfies all required (no-default) fields. */
const minimal = {
  githubPat: "pat",
  llmBaseUrl: "http://localhost:11434",
  llmApiKey: "sk-key",
  llmModel: "gpt-4o",
  dbPath: "/tmp/reviews.db",
  logDir: "/tmp/logs",
};

describe("parseConfig — reviewRules (AC1.1 back-compat + AC1.6 round-trip)", () => {
  it("AC1.1: reviewRules omitted ⇒ '' (loads with no error)", () => {
    const cfg = parseConfig({ ...minimal });
    expect(cfg.reviewRules).toBe("");
  });

  it("AC1.1: reviewRules explicitly undefined ⇒ ''", () => {
    const cfg = parseConfig({ ...minimal, reviewRules: undefined });
    expect(cfg.reviewRules).toBe("");
  });

  it("AC1.6: reviewRules set ⇒ round-trips unchanged through parseConfig", () => {
    const cfg = parseConfig({ ...minimal, reviewRules: "Always validate inputs." });
    expect(cfg.reviewRules).toBe("Always validate inputs.");
  });

  it("AC1.6: reviewRules preserves multiline / special characters", () => {
    const rules = "Rule one.\n- bullet\n\"quotes\" & symbols: <>&";
    const cfg = parseConfig({ ...minimal, reviewRules: rules });
    expect(cfg.reviewRules).toBe(rules);
  });

  it("rejects a non-string reviewRules (zod validation)", () => {
    expect(() => parseConfig({ ...minimal, reviewRules: 123 })).toThrow();
  });

  it("configAffectsRuntime ignores reviewRules (rules are a prompt concern, not a scheduling one)", () => {
    const a = parseConfig({ ...minimal, reviewRules: "A" });
    const b = parseConfig({ ...minimal, reviewRules: "B" });
    expect(configAffectsRuntime(a, b)).toBe(false);
  });
});

describe("parseConfig — repo/label filters (AC-Empty back-compat + round-trip + AC-HotReload no-reschedule)", () => {
  it("AC-Empty: all four filter fields omitted ⇒ '' (existing persisted configs load unchanged)", () => {
    const cfg = parseConfig({ ...minimal });
    expect(cfg.repoInclude).toBe("");
    expect(cfg.repoExclude).toBe("");
    expect(cfg.triggerLabels).toBe("");
    expect(cfg.skipLabels).toBe("");
  });

  it("AC-Empty: all four filter fields explicitly undefined ⇒ ''", () => {
    const cfg = parseConfig({
      ...minimal,
      repoInclude: undefined,
      repoExclude: undefined,
      triggerLabels: undefined,
      skipLabels: undefined,
    });
    expect(cfg.repoInclude).toBe("");
    expect(cfg.repoExclude).toBe("");
    expect(cfg.triggerLabels).toBe("");
    expect(cfg.skipLabels).toBe("");
  });

  it("round-trips provided values unchanged through parseConfig", () => {
    const cfg = parseConfig({
      ...minimal,
      repoInclude: "myorg/*\notherorg/repo",
      repoExclude: "myorg/legacy-*",
      triggerLabels: "review-requested\nneeds-review",
      skipLabels: "wip\nbot:skip",
    });
    expect(cfg.repoInclude).toBe("myorg/*\notherorg/repo");
    expect(cfg.repoExclude).toBe("myorg/legacy-*");
    expect(cfg.triggerLabels).toBe("review-requested\nneeds-review");
    expect(cfg.skipLabels).toBe("wip\nbot:skip");
  });

  it("preserves multiline / special characters", () => {
    const patterns = "MyOrg/*\n?wild-card\n\"quotes\" & <>,;";
    const cfg = parseConfig({
      ...minimal,
      repoInclude: patterns,
      triggerLabels: patterns,
    });
    expect(cfg.repoInclude).toBe(patterns);
    expect(cfg.triggerLabels).toBe(patterns);
  });

  it("rejects non-string filter fields (zod validation)", () => {
    expect(() => parseConfig({ ...minimal, repoInclude: 123 })).toThrow();
    expect(() => parseConfig({ ...minimal, repoExclude: [] })).toThrow();
    expect(() => parseConfig({ ...minimal, triggerLabels: {} })).toThrow();
    expect(() => parseConfig({ ...minimal, skipLabels: true })).toThrow();
  });

  it("AC-HotReload: configAffectsRuntime is STILL false for a filter-only diff (e.g. repoInclude a→b)", () => {
    const a = parseConfig({ ...minimal, repoInclude: "org-a/*" });
    const b = parseConfig({ ...minimal, repoInclude: "org-b/*" });
    expect(configAffectsRuntime(a, b)).toBe(false);
  });

  it("AC-HotReload: configAffectsRuntime is false for a diff across all four filters", () => {
    const a = parseConfig({ ...minimal, repoInclude: "a", repoExclude: "b", triggerLabels: "c", skipLabels: "d" });
    const b = parseConfig({ ...minimal, repoInclude: "w", repoExclude: "x", triggerLabels: "y", skipLabels: "z" });
    expect(configAffectsRuntime(a, b)).toBe(false);
  });

  it("AC-HotReload: a genuine scheduling diff (pollIntervalMin) still reschedules even alongside filter changes", () => {
    const a = parseConfig({ ...minimal, repoInclude: "a" });
    const b = parseConfig({ ...minimal, repoInclude: "b", pollIntervalMin: 30 });
    expect(configAffectsRuntime(a, b)).toBe(true);
  });
});

describe("parseConfig — review-quality cluster defaults + configAffectsRuntime (AC5.4 / AC5.5)", () => {
  it("AC5.4: the 5 review-quality fields default when omitted", () => {
    const cfg = parseConfig({ ...minimal });
    expect(cfg.fileInclude).toBe("");
    expect(cfg.fileExclude).toBe("");
    expect(cfg.maxDiffLines).toBe(5000);
    expect(cfg.maxFiles).toBe(50);
    expect(cfg.largePrPolicy).toBe("trim");
  });

  it("AC5.4: the 5 fields default even when explicitly undefined", () => {
    const cfg = parseConfig({
      ...minimal,
      fileInclude: undefined,
      fileExclude: undefined,
      maxDiffLines: undefined,
      maxFiles: undefined,
      largePrPolicy: undefined,
    });
    expect(cfg.fileInclude).toBe("");
    expect(cfg.fileExclude).toBe("");
    expect(cfg.maxDiffLines).toBe(5000);
    expect(cfg.maxFiles).toBe(50);
    expect(cfg.largePrPolicy).toBe("trim");
  });

  it("AC5.5: configAffectsRuntime is false when ONLY one of the 5 new fields differs (no reschedule)", () => {
    const a = parseConfig({ ...minimal });
    // Each of the 5 new fields changed in isolation against an otherwise-equal
    // config (mirrors how the existing configAffectsRuntime tests diff a single
    // filter field like repoInclude a→b).
    expect(configAffectsRuntime(a, parseConfig({ ...minimal, fileInclude: "*.ts" }))).toBe(false);
    expect(configAffectsRuntime(a, parseConfig({ ...minimal, fileExclude: "*.snap" }))).toBe(false);
    expect(configAffectsRuntime(a, parseConfig({ ...minimal, maxDiffLines: 1000 }))).toBe(false);
    expect(configAffectsRuntime(a, parseConfig({ ...minimal, maxFiles: 10 }))).toBe(false);
    expect(configAffectsRuntime(a, parseConfig({ ...minimal, largePrPolicy: "abort" }))).toBe(false);
  });
});

describe("parseConfig — cost & budget fields defaults + configAffectsRuntime (AC4.6–AC4.9)", () => {
  it("AC4.6: the 3 cost/budget fields default when omitted", () => {
    const cfg = parseConfig({ ...minimal });
    expect(cfg.llmPricing).toBe("");
    expect(cfg.defaultPer1M).toBe(0);
    expect(cfg.monthlyBudgetUsd).toBe(0);
  });

  it("AC4.6: the 3 fields default even when explicitly undefined", () => {
    const cfg = parseConfig({
      ...minimal,
      llmPricing: undefined,
      defaultPer1M: undefined,
      monthlyBudgetUsd: undefined,
    });
    expect(cfg.llmPricing).toBe("");
    expect(cfg.defaultPer1M).toBe(0);
    expect(cfg.monthlyBudgetUsd).toBe(0);
  });

  it("AC4.6: provided values round-trip through parseConfig", () => {
    const cfg = parseConfig({
      ...minimal,
      llmPricing: "gpt-4o:2.50,10.00\nglm-5.2:0.50,1.50",
      defaultPer1M: 1.5,
      monthlyBudgetUsd: 50,
    });
    expect(cfg.llmPricing).toBe("gpt-4o:2.50,10.00\nglm-5.2:0.50,1.50");
    expect(cfg.defaultPer1M).toBe(1.5);
    expect(cfg.monthlyBudgetUsd).toBe(50);
  });

  it("AC4.6: rejects negative defaultPer1M / monthlyBudgetUsd (zod .nonnegative)", () => {
    expect(() => parseConfig({ ...minimal, defaultPer1M: -1 })).toThrow();
    expect(() => parseConfig({ ...minimal, monthlyBudgetUsd: -5 })).toThrow();
  });

  it("AC4.9-display: configAffectsRuntime is FALSE when ONLY llmPricing differs", () => {
    const a = parseConfig({ ...minimal, llmPricing: "gpt-4o:2.50,10.00" });
    const b = parseConfig({ ...minimal, llmPricing: "glm-5.2:0.50,1.50" });
    expect(configAffectsRuntime(a, b)).toBe(false);
  });

  it("AC4.9-display: configAffectsRuntime is FALSE when ONLY defaultPer1M differs", () => {
    const a = parseConfig({ ...minimal, defaultPer1M: 1 });
    const b = parseConfig({ ...minimal, defaultPer1M: 5 });
    expect(configAffectsRuntime(a, b)).toBe(false);
  });

  it("AC4.7-runtime: configAffectsRuntime is TRUE when monthlyBudgetUsd differs", () => {
    const a = parseConfig({ ...minimal, monthlyBudgetUsd: 10 });
    const b = parseConfig({ ...minimal, monthlyBudgetUsd: 50 });
    expect(configAffectsRuntime(a, b)).toBe(true);
  });
});
