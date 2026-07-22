/**
 * LLM prompts for code review.
 *
 * The system prompt instructs the model to:
 *   - Cover four areas: bug, style, structure, security.
 *   - Prioritize accuracy and avoid false positives (R12).
 *   - Write in a human tone without AI self-reference (R26).
 *   - Include a suggestion block for each finding (R28).
 *   - Assign severity when `showSeverity` is on.
 *   - Write comments in the PR/codebase language (R21).
 *   - Prefer lines that appear in the diff (Architect recommendation).
 *
 * The user prompt bundles PR metadata, the per-file diff hunks, and the full
 * file content, then requests a strict JSON response.
 */

import { CHARS_PER_TOKEN, estimateTokens } from "./token-budget";

/** Map a language code to a human-readable name for the prompt. */
function languageName(code: string): string {
  switch (code) {
    case "ko":
      return "Korean";
    case "ja":
      return "Japanese";
    case "zh":
      return "Chinese";
    default:
      return "English";
  }
}

/**
 * Heuristically detect the PR/codebase language from the title and body.
 *
 * Checks for CJK scripts; defaults to English. This determines which language
 * the LLM writes review comments in (R21).
 */
export function detectLanguage(title: string, body: string): string {
  const text = `${title} ${body}`;
  // Korean Hangul syllables / jamo.
  if (/[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f]/.test(text)) return "ko";
  // Japanese Hiragana / Katakana.
  if (/[\u3040-\u30ff]/.test(text)) return "ja";
  // Chinese CJK ideographs.
  if (/[\u4e00-\u9fff]/.test(text)) return "zh";
  return "en";
}

/** Metadata about the PR passed into the user prompt. */
export interface PrPromptMeta {
  title: string;
  body: string;
  author: string;
  number: number;
  repo: string;
}

/** Canonical review areas in priority order (bug/style/structure/security). */
const AREA_LINES: Record<string, string> = {
  bug: "- bug: logic errors, race conditions, off-by-one, null dereferences, incorrect types, unhandled edge cases",
  style: "- style: naming, consistency, readability, dead code",
  structure: "- structure: duplication, tight coupling, missing abstraction, excessive complexity",
  security: "- security: injection, hardcoded secrets, unsafe deserialization, permission issues",
};
const ALL_AREA_KEYS = ["bug", "style", "structure", "security"];

/**
 * Build the review-areas section of the system prompt from a comma-separated
 * `areas` subset (e.g. "bug,security"). When all four areas are enabled (the
 * default / empty), emits the literal "Review across four areas:" block
 * byte-identical to the legacy prompt so existing snapshots stay green (G003).
 * A strict subset uses "Review across the following areas:" with only the
 * enabled lines, in canonical order. Unknown areas are ignored.
 */
function buildAreasSection(areas: string): string {
  const enabled = new Set(
    areas
      .split(",")
      .map((a) => a.trim().toLowerCase())
      .filter((a) => ALL_AREA_KEYS.includes(a)),
  );
  const ordered = ALL_AREA_KEYS.filter((k) => enabled.has(k));
  // Empty or all-four → the legacy byte-identical block.
  if (ordered.length === 0 || ordered.length === 4) {
    return "Review across four areas:\n" + ALL_AREA_KEYS.map((k) => AREA_LINES[k]).join("\n");
  }
  return "Review across the following areas:\n" + ordered.map((k) => AREA_LINES[k]).join("\n");
}

/**
 * Build the system prompt. `showSeverity` controls whether the model is asked
 * to assign severity labels; `language` controls the comment language.
 */
export function buildSystemPrompt(showSeverity: boolean, language: string, rules = "", areas = "bug,style,structure,security"): string {
  const lang = languageName(language);

  const severityRule = showSeverity
    ? `- Assign a severity to each finding: "high" (bugs, security, data loss), "medium" (meaningful improvement), or "low" (minor nit).`
    : `- Do not include a severity field.`;

  // F1: inject team/project guidelines after the rules list and before the
  // JSON-shape spec. Empty when `rules` is blank so output stays byte-identical
  // to the legacy two-arg call (backward-compat invariant).
  const guidelinesSection = rules.trim()
    ? `\nTeam / project guidelines (apply where relevant; per-repo rules below take precedence where they conflict):\n${rules}\n`
    : "";
  const areasSection = buildAreasSection(areas);
  return `You are a senior software engineer performing a code review on a pull request. Examine the changed file carefully.

${areasSection}

Rules:
- ACCURACY IS THE TOP PRIORITY. Only report issues you are confident are real problems. If you are unsure, do not report it. Never fabricate issues. If the code is correct, return an empty findings array.
- Write naturally, as a human reviewer would in a PR comment. Do not use phrases like "As an AI", "I analyzed", "Upon reviewing", "Let me", or any AI self-reference.
- Be specific and concise. Point to the exact line and explain the impact.
- Prefer findings on lines that appear in the diff (added or context lines).
- Include a concrete "suggestion" for each finding: the corrected code or a specific fix. If no code change is needed, describe the action.
- Write every comment in ${lang}.
${severityRule}${guidelinesSection}

Respond with JSON only, using exactly this shape:
{
  "findings": [
    {
      "file": "path/to/file",
      "line": 42,
      "severity": "high",
      "area": "bug",
      "comment": "Clear description of the problem and its impact.",
      "suggestion": "Corrected code or a specific recommended fix."
    }
  ],
  "summary": "One or two sentences summarizing the review."
}

If there are no issues, return { "findings": [], "summary": "..." }.`;
}

// --- F1: custom review guidelines -----------------------------------------

/** Maximum token budget for composed review guidelines (~6000 chars). */
export const MAX_GUIDELINES_TOKENS = 1500;

/** Separator between global (config) and per-repo guideline sections. */
export const SEPARATOR_GUIDELINES = "\n\n---\n\n";

/** Marker appended when composed guidelines exceed the token budget. */
const GUIDELINES_TRUNCATED_MARKER = "\n[... guidelines truncated]";

/**
 * Compose the review-guidelines string injected into the system prompt.
 *
 * Sources are ordered global-first, repo-last (per-repo `.prreview/rules.md`
 * rules are most specific and take precedence where they conflict). Each part
 * is trimmed; whitespace-only inputs are treated as absent. When both sources
 * are absent the result is the empty string (no section is injected).
 *
 * If the composed string exceeds {@link MAX_GUIDELINES_TOKENS} tokens it is
 * truncated to fit (char budget minus the truncation marker) so the final
 * string — marker included — stays within the token budget.
 */
export function composeGuidelines(configRules: string, repoRules: string | null): string {
  const parts = [configRules.trim(), (repoRules ?? "").trim()].filter((p) => p.length > 0);
  if (parts.length === 0) return "";

  const composed = parts.join(SEPARATOR_GUIDELINES);
  if (estimateTokens(composed) <= MAX_GUIDELINES_TOKENS) return composed;

  // Truncate the body so body + marker stays within the token budget.
  const budget = MAX_GUIDELINES_TOKENS * CHARS_PER_TOKEN;
  const truncated = composed.slice(0, Math.max(0, budget - GUIDELINES_TRUNCATED_MARKER.length));
  return `${truncated}${GUIDELINES_TRUNCATED_MARKER}`;
}

/**
 * Build the user prompt: PR metadata, per-file diff hunks, and the full file
 * content.
 */
export function buildUserPrompt(
  fileName: string,
  fileContent: string,
  diffHunks: string,
  prMeta: PrPromptMeta,
): string {
  return `## Pull Request #${prMeta.number}
Title: ${prMeta.title}
Repository: ${prMeta.repo}
Author: ${prMeta.author || "(unknown)"}

## Description
${prMeta.body || "(no description provided)"}

## Diff for ${fileName}
\`\`\`diff
${diffHunks || "(no changes)"}
\`\`\`

## Full file content — ${fileName}
\`\`\`
${fileContent || "(empty file)"}
\`\`\`

Review this file and respond with JSON only.`;
}
