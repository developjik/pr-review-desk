import { describe, it, expect } from "vitest";

import {
  splitLines,
  repoGlob,
  matchRepo,
  shouldFilterPR,
  shouldSkipBotAuthor,
  type FilterInput,
} from "./filter";

/** Minimal input with all rule strings empty (inert). */
function baseInput(overrides: Partial<FilterInput> = {}): FilterInput {
  return {
    repo: "org/widget",
    labels: [],
    repoInclude: "",
    repoExclude: "",
    triggerLabels: "",
    skipLabels: "",
    ...overrides,
  };
}

describe("splitLines", () => {
  it("splits on \\n, trims, drops empties", () => {
    expect(splitLines("a\n b \n\n  c\n")).toEqual(["a", "b", "c"]);
  });
  it("empty/whitespace input is inert", () => {
    expect(splitLines("")).toEqual([]);
    expect(splitLines("   \n\t\n ")).toEqual([]);
  });
});

describe("repoGlob / matchRepo", () => {
  it("`org/*` matches org/widget, rejects other/widget", () => {
    expect(repoGlob("org/*", "org/widget")).toBe(true);
    expect(repoGlob("org/*", "other/widget")).toBe(false);
  });
  it("`org/legacy-*` matches org/legacy-x", () => {
    expect(repoGlob("org/legacy-*", "org/legacy-x")).toBe(true);
    expect(repoGlob("org/legacy-*", "org/widget")).toBe(false);
  });
  it("`*/widget` matches acme/widget", () => {
    expect(repoGlob("*/widget", "acme/widget")).toBe(true);
    expect(repoGlob("*/widget", "acme/other")).toBe(false);
  });
  it("literal ./+/( are NOT regex specials", () => {
    // `.` matches a literal dot only — not a regex wildcard.
    expect(repoGlob("org/foo.bar", "org/foo.bar")).toBe(true);
    expect(repoGlob("org/foo.bar", "org/foobar")).toBe(false);
    expect(repoGlob("org/foo.bar", "org/fooXbar")).toBe(false);
    // `+` literal.
    expect(repoGlob("org/foo+bar", "org/foo+bar")).toBe(true);
    expect(repoGlob("org/foo+bar", "org/fooobar")).toBe(false);
    // `(` literal.
    expect(repoGlob("org/foo(bar)", "org/foo(bar)")).toBe(true);
  });
  it("anchored full match (org/wid ≠ org/widget)", () => {
    expect(repoGlob("org/wid", "org/widget")).toBe(false);
  });
  it("bare `*` matches a single segment but is segment-local", () => {
    // Segment-local `*` (per the owner/repo domain note): it never spans `/`,
    // so a bare `*` matches any one segment but not a full owner/repo.
    expect(repoGlob("*", "widget")).toBe(true);
    expect(repoGlob("*", "")).toBe(true);
    expect(repoGlob("*", "org/widget")).toBe(false);
  });
  it("`?` matches exactly one non-slash char", () => {
    expect(repoGlob("org/widge?", "org/widget")).toBe(true);
    expect(repoGlob("org/widge?", "org/widg")).toBe(false);
  });

  it("CASE-INSENSITIVE repo matching", () => {
    expect(repoGlob("Org/*", "org/widget")).toBe(true);
    expect(repoGlob("org/Widget", "org/widget")).toBe(true);
    expect(repoGlob("ORG/*", "org/repo")).toBe(true);
  });

  it("matchRepo: any-match + empty-is-inert", () => {
    expect(matchRepo("org/widget", ["org/*", "other/*"])).toBe(true);
    expect(matchRepo("org/widget", ["other/*"])).toBe(false);
    expect(matchRepo("org/widget", [])).toBe(false);
  });
});

describe("shouldFilterPR", () => {
  it("empty rule sets are inert (filtered:false, no reason)", () => {
    expect(shouldFilterPR(baseInput())).toEqual({ filtered: false });
  });

  it("repoExclude hit → repo:exclude", () => {
    expect(
      shouldFilterPR(baseInput({ repoExclude: "org/*" })),
    ).toEqual({ filtered: true, reason: "repo:exclude" });
  });

  it("repoInclude miss → repo:include", () => {
    expect(
      shouldFilterPR(baseInput({ repo: "other/widget", repoInclude: "org/*" })),
    ).toEqual({ filtered: true, reason: "repo:include" });
  });

  it("repoInclude hit → pass", () => {
    expect(
      shouldFilterPR(baseInput({ repo: "org/widget", repoInclude: "org/*" })),
    ).toEqual({ filtered: false });
  });

  it("repoInclude empty → inert (default = all repos)", () => {
    expect(shouldFilterPR(baseInput({ repoInclude: "" }))).toEqual({
      filtered: false,
    });
  });

  it("trigger absent on PR → label:trigger", () => {
    expect(
      shouldFilterPR(baseInput({ labels: ["bug"], triggerLabels: "needs-review" })),
    ).toEqual({ filtered: true, reason: "label:trigger" });
  });

  it("trigger present on PR → pass", () => {
    expect(
      shouldFilterPR(baseInput({ labels: ["needs-review"], triggerLabels: "needs-review" })),
    ).toEqual({ filtered: false });
  });

  it("skipLabel hit → label:skip", () => {
    expect(
      shouldFilterPR(baseInput({ labels: ["wip"], skipLabels: "wip" })),
    ).toEqual({ filtered: true, reason: "label:skip" });
  });

  it("CASE-INSENSITIVE labels (WIP matches wip)", () => {
    expect(
      shouldFilterPR(baseInput({ labels: ["WIP"], skipLabels: "wip" })),
    ).toEqual({ filtered: true, reason: "label:skip" });
    expect(
      shouldFilterPR(baseInput({ labels: ["needs-review"], triggerLabels: "Needs-Review" })),
    ).toEqual({ filtered: false });
  });

  // TWO-PHASE PRECEDENCE (load-bearing).
  it("precedence: repoExclude + skipLabel → repo:exclude (Phase 1 short-circuits)", () => {
    const res = shouldFilterPR(
      baseInput({
        repo: "org/widget",
        labels: ["wip"],
        repoExclude: "org/*",
        skipLabels: "wip",
      }),
    );
    expect(res).toEqual({ filtered: true, reason: "repo:exclude" });
  });

  it("precedence: within Phase 2, skipLabel before trigger", () => {
    // PR has both the skip label and the trigger label: skip wins.
    expect(
      shouldFilterPR(
        baseInput({
          labels: ["wip", "needs-review"],
          skipLabels: "wip",
          triggerLabels: "needs-review",
        }),
      ),
    ).toEqual({ filtered: true, reason: "label:skip" });
  });

  it("precedence: repoInclude miss + skipLabel → repo:include (Phase 1 first)", () => {
    expect(
      shouldFilterPR(
        baseInput({
          repo: "other/widget",
          labels: ["wip"],
          repoInclude: "org/*",
          skipLabels: "wip",
        }),
      ),
    ).toEqual({ filtered: true, reason: "repo:include" });
  });
});

describe("shouldSkipBotAuthor", () => {
  it("skips a configured bot when policy=skip", () => {
    expect(shouldSkipBotAuthor("dependabot", "dependabot", "skip")).toBe(true);
  });
  it("matches case-insensitively", () => {
    expect(shouldSkipBotAuthor("Dependabot", "dependabot", "skip")).toBe(true);
    expect(shouldSkipBotAuthor("dependabot", "Dependabot\nRenovate", "skip")).toBe(true);
  });
  it("does not skip a non-bot author", () => {
    expect(shouldSkipBotAuthor("alice", "dependabot", "skip")).toBe(false);
  });
  it("does not skip when policy=review", () => {
    expect(shouldSkipBotAuthor("dependabot", "dependabot", "review")).toBe(false);
  });
  it("is inert when botAuthors is empty", () => {
    expect(shouldSkipBotAuthor("dependabot", "", "skip")).toBe(false);
    expect(shouldSkipBotAuthor("dependabot", "  \n ", "skip")).toBe(false);
  });
});

describe("shouldFilterPR — Phase 0 bot-author skip", () => {
  it("filters a bot author with reason author:bot when policy=skip", () => {
    expect(
      shouldFilterPR(
        baseInput({ author: "dependabot", botAuthors: "dependabot", botPolicy: "skip" }),
      ),
    ).toEqual({ filtered: true, reason: "author:bot" });
  });
  it("does not filter when policy=review even if author is a bot", () => {
    expect(
      shouldFilterPR(
        baseInput({ author: "dependabot", botAuthors: "dependabot", botPolicy: "review" }),
      ),
    ).toEqual({ filtered: false });
  });
  it("does not filter a non-bot author", () => {
    expect(
      shouldFilterPR(
        baseInput({ author: "alice", botAuthors: "dependabot", botPolicy: "skip" }),
      ),
    ).toEqual({ filtered: false });
  });
  it("bot Phase 0 runs before repo/label phases (precedence)", () => {
    // A bot that would ALSO match repoExclude still filters as author:bot first.
    expect(
      shouldFilterPR(
        baseInput({
          author: "renovate",
          botAuthors: "renovate",
          botPolicy: "skip",
          repoExclude: "org/*",
          repo: "org/widget",
        }),
      ),
    ).toEqual({ filtered: true, reason: "author:bot" });
  });
});
