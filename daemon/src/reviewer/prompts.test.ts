import { describe, it, expect } from "vitest";
import {
  buildSystemPrompt,
  composeGuidelines,
  detectLanguage,
  MAX_GUIDELINES_TOKENS,
  SEPARATOR_GUIDELINES,
} from "./prompts";
import { estimateTokens } from "./token-budget";

// --- Backward-compat snapshots (AC1.3) -------------------------------------
//
// Capture the legacy two-arg output first (the function signature still accepts
// two args; `rules` defaults to ""). These snapshots are the byte-for-byte
// baseline the three-arg-empty form must reproduce exactly.
const LEGACY_WITH_SEVERITY = buildSystemPrompt(true, "en");
const LEGACY_WITHOUT_SEVERITY = buildSystemPrompt(false, "ja");

describe("buildSystemPrompt — backward compatibility (AC1.3)", () => {
  it("three-arg empty rules is byte-identical to legacy two-arg output", () => {
    expect(buildSystemPrompt(true, "en", "")).toBe(LEGACY_WITH_SEVERITY);
    expect(buildSystemPrompt(false, "ja", "")).toBe(LEGACY_WITHOUT_SEVERITY);
  });

  it("whitespace-only rules is also byte-identical (treated as absent)", () => {
    expect(buildSystemPrompt(true, "en", "   ")).toBe(LEGACY_WITH_SEVERITY);
    expect(buildSystemPrompt(true, "en", "\n\t")).toBe(LEGACY_WITH_SEVERITY);
  });

  it("legacy output has no guidelines section", () => {
    expect(LEGACY_WITH_SEVERITY).not.toContain("Team / project guidelines");
    expect(LEGACY_WITH_SEVERITY).not.toContain("guidelines");
  });

  it("legacy structure is intact (no accidental template edits)", () => {
    expect(LEGACY_WITH_SEVERITY.startsWith(
      "You are a senior software engineer performing a code review on a pull request. Examine the changed file carefully.",
    )).toBe(true);
    expect(LEGACY_WITH_SEVERITY).toContain("Review across four areas:");
    expect(LEGACY_WITH_SEVERITY).toContain("- ACCURACY IS THE TOP PRIORITY.");
    expect(LEGACY_WITH_SEVERITY).toContain("- Write every comment in English.");
    expect(LEGACY_WITH_SEVERITY).toContain(
      `- Assign a severity to each finding: "high" (bugs, security, data loss), "medium" (meaningful improvement), or "low" (minor nit).`,
    );
    expect(LEGACY_WITH_SEVERITY).toContain("Respond with JSON only, using exactly this shape:");
    expect(LEGACY_WITH_SEVERITY).toContain('"summary": "One or two sentences summarizing the review."');
    expect(LEGACY_WITH_SEVERITY.endsWith(
      'If there are no issues, return { "findings": [], "summary": "..." }.',
    )).toBe(true);
  });

  it("no guidelines injected between the rules list and the JSON spec", () => {
    // The severity rule line must be immediately followed by a single blank
    // line and then "Respond with JSON only" — proving nothing was injected.
    expect(LEGACY_WITH_SEVERITY).toContain(
      `- Assign a severity to each finding: "high" (bugs, security, data loss), "medium" (meaningful improvement), or "low" (minor nit).\n\nRespond with JSON only, using exactly this shape:`,
    );
  });
});

describe("buildSystemPrompt — guidelines injection (F1)", () => {
  it("non-empty rules injects a Team / project guidelines section", () => {
    const rules = "Never use `any`. Prefer named exports.";
    const out = buildSystemPrompt(true, "en", rules);
    expect(out).toContain("Team / project guidelines");
    expect(out).toContain("apply where relevant; per-repo rules below take precedence where they conflict");
    expect(out).toContain(rules);
  });

  it("non-empty rules output differs from legacy only by the injected section", () => {
    const rules = "Prefer early returns.";
    const out = buildSystemPrompt(true, "en", rules);
    // Legacy still present verbatim as a prefix up to the severity rule.
    expect(out.startsWith(LEGACY_WITH_SEVERITY)).toBe(false);
    // The injected section sits after the rules list, before the JSON spec.
    expect(out).toContain(
      `- Assign a severity to each finding: "high" (bugs, security, data loss), "medium" (meaningful improvement), or "low" (minor nit).\nTeam / project guidelines`,
    );
    // JSON spec still follows the guidelines block.
    expect(out).toContain("Respond with JSON only, using exactly this shape:");
    expect(out).toContain('"findings"');
  });

  it("guidelines rule text is rendered verbatim (no trimming of the body)", () => {
    const rules = "RULE_LINE_42";
    const out = buildSystemPrompt(false, "en", rules);
    expect(out).toContain(`RULE_LINE_42`);
  });
});

describe("composeGuidelines (AC1.2)", () => {
  it("returns empty string when both sources are empty/whitespace", () => {
    expect(composeGuidelines("", null)).toBe("");
    expect(composeGuidelines("  ", null)).toBe("");
    expect(composeGuidelines("", "")).toBe("");
    expect(composeGuidelines("   \n\t  ", "  ")).toBe("");
  });

  it("treats null repoRules as absent", () => {
    expect(composeGuidelines("global rule", null)).toBe("global rule");
  });

  it("treats whitespace-only repoRules as absent (global still used)", () => {
    expect(composeGuidelines("global rule", "   ")).toBe("global rule");
  });

  it("joins config (global) first, repo last with the separator", () => {
    expect(composeGuidelines("a", "b")).toBe(`a${SEPARATOR_GUIDELINES}b`);
    expect(composeGuidelines("a", "b")).toBe("a\n\n---\n\nb");
  });

  it("trims each part before joining", () => {
    expect(composeGuidelines("  a  ", "  b  ")).toBe("a\n\n---\n\nb");
  });

  it("uses only the repo rule when the global rule is empty", () => {
    expect(composeGuidelines("", "repo-only")).toBe("repo-only");
  });

  it("truncates oversized input to the token budget and appends a marker", () => {
    // > 1500 tokens (> 6000 chars).
    const oversized = "a".repeat(MAX_GUIDELINES_TOKENS * 4 + 1000);
    const result = composeGuidelines(oversized, null);
    expect(result.endsWith("[... guidelines truncated]")).toBe(true);
    // Total stays within the char budget (marker included).
    expect(result.length).toBeLessThanOrEqual(MAX_GUIDELINES_TOKENS * 4);
    expect(estimateTokens(result)).toBeLessThanOrEqual(MAX_GUIDELINES_TOKENS);
  });

  it("does not truncate input exactly at the budget boundary", () => {
    // Exactly 1500 tokens (6000 chars) — not oversized.
    const atBoundary = "a".repeat(MAX_GUIDELINES_TOKENS * 4);
    expect(composeGuidelines(atBoundary, null)).toBe(atBoundary);
  });

  it("truncates when composed (joined) input exceeds the budget even if parts are small", () => {
    const globalPart = "g".repeat(MAX_GUIDELINES_TOKENS * 2);
    const repoPart = "r".repeat(MAX_GUIDELINES_TOKENS * 2);
    const result = composeGuidelines(globalPart, repoPart);
    expect(result.endsWith("[... guidelines truncated]")).toBe(true);
    expect(result.length).toBeLessThanOrEqual(MAX_GUIDELINES_TOKENS * 4);
    expect(estimateTokens(result)).toBeLessThanOrEqual(MAX_GUIDELINES_TOKENS);
  });
});

describe("detectLanguage — regression (no behavior change)", () => {
  it("detects Korean via Hangul", () => {
    expect(detectLanguage("버그 수정", "")).toBe("ko");
  });

  it("detects Japanese via Katakana/Hiragana", () => {
    expect(detectLanguage("コードレビュー", "")).toBe("ja");
  });

  it("detects Chinese via CJK ideographs", () => {
    expect(detectLanguage("请审查这段代码", "")).toBe("zh");
  });

  it("defaults to English for latin scripts", () => {
    expect(detectLanguage("Fix a null pointer", "")).toBe("en");
    expect(detectLanguage("", "")).toBe("en");
  });

  it("checks Korean before Japanese before Chinese", () => {
    // Mixed: a Hangul char present → ko wins regardless of other scripts.
    expect(detectLanguage("안녕 コード", "")).toBe("ko");
  });
});
