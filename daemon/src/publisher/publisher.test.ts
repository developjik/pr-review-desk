import { describe, it, expect, beforeEach, vi } from "vitest";
import type { Octokit } from "@octokit/rest";
import type { Finding } from "../types/domain";
import { publishReview, createPendingReview, submitPendingReview, discardPendingReview, type PublisherConfig } from "./publisher";

// Silence the logger so test output stays clean.
vi.mock("../logging/logger", () => ({
  getLogger: () => ({
    warn() {},
    info() {},
    error() {},
    debug() {},
    trace() {},
    fatal() {},
  }),
}));

const config: PublisherConfig = { showSeverity: false };

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeFinding(overrides: Partial<Finding> = {}): Finding {
  return {
    file: "src/index.ts",
    line: 10,
    severity: "medium",
    area: "bug",
    comment: "This looks wrong",
    ...overrides,
  };
}

/** Generate `n` distinct inline findings (different file + line each). */
function makeFindings(n: number): Finding[] {
  return Array.from({ length: n }, (_, i) =>
    makeFinding({ file: `file${i}.ts`, line: i + 1, comment: `issue ${i}` }),
  );
}

type MockFn = ReturnType<typeof vi.fn>;

interface MockOctokit {
  rest: {
    pulls: {
      createReview: MockFn;
      listReviewComments: MockFn;
      submitReview: MockFn;
      deletePendingReview: MockFn;
    };
    issues: {
      createComment: MockFn;
    };
  };
}

function makeMockOctokit(): MockOctokit {
  return {
    rest: {
      pulls: {
        createReview: vi.fn().mockResolvedValue({ data: { id: 1 } }),
        listReviewComments: vi.fn().mockResolvedValue({ data: [] }),
        submitReview: vi.fn().mockResolvedValue({ data: { id: 1 } }),
        deletePendingReview: vi.fn().mockResolvedValue({ data: {} }),
      },
      issues: {
        createComment: vi.fn().mockResolvedValue({ data: { id: 2 } }),
      },
    },
  };
}

/** Cast the mock to the real Octokit type so `publishReview` type-checks. */
function asOctokit(m: MockOctokit): Octokit {
  return m as unknown as Octokit;
}

/** Error shaped like @octokit/rest's RequestError for a 422. */
function err422(extra?: Record<string, unknown>): { status: number } & Record<string, unknown> {
  return { status: 422, ...extra };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("publisher / publishReview", () => {
  let octokit: MockOctokit;

  beforeEach(() => {
    octokit = makeMockOctokit();
  });

  // -- R24: nothing to say, say nothing -------------------------------------

  it("R24: returns zeros and makes no API calls when there is nothing to post", async () => {
    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline: [], degraded: [], summary: "LGTM" },
      config,
    );

    expect(result).toEqual({ posted: 0, degraded: 0, retried: 0 });
    expect(octokit.rest.pulls.createReview).not.toHaveBeenCalled();
    expect(octokit.rest.pulls.listReviewComments).not.toHaveBeenCalled();
    expect(octokit.rest.issues.createComment).not.toHaveBeenCalled();
  });

  // -- Happy path -----------------------------------------------------------

  it("posts all inline comments when createReview succeeds on the first try", async () => {
    const inline = makeFindings(3);
    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline, degraded: [], summary: "Summary" },
      config,
    );

    expect(result).toEqual({ posted: 3, degraded: 0, retried: 0 });
    expect(octokit.rest.pulls.createReview).toHaveBeenCalledTimes(1);

    // No degraded findings → no standalone issue comment.
    expect(octokit.rest.issues.createComment).not.toHaveBeenCalled();
  });

  // -- Degraded as standalone issue comment ---------------------------------

  it("posts degraded findings as a standalone PR issue comment", async () => {
    const degraded = [
      makeFinding({ file: "degraded0.ts", line: null, comment: "cant place 0" }),
      makeFinding({ file: "degraded1.ts", line: null, comment: "cant place 1" }),
    ];
    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline: [makeFinding({ file: "ok.ts", line: 5 })], degraded, summary: "Summary" },
      config,
    );

    expect(result).toEqual({ posted: 1, degraded: 2, retried: 0 });
    expect(octokit.rest.issues.createComment).toHaveBeenCalledTimes(1);

    const issueCall = octokit.rest.issues.createComment.mock.calls[0][0];
    expect(issueCall.issue_number).toBe(1);
    expect(issueCall.body).toContain("degraded0.ts");
    expect(issueCall.body).toContain("degraded1.ts");
  });

  // -- Progressive trim: 422 then success -----------------------------------

  it("progressive trim: 422 on first POST trims half, second POST succeeds", async () => {
    const inline = makeFindings(2);
    octokit.rest.pulls.createReview
      .mockRejectedValueOnce(err422())
      .mockResolvedValueOnce({ data: { id: 1 } });

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline, degraded: [], summary: "Summary" },
      config,
    );

    // 1 of 2 posted inline; 1 trimmed to degraded; 1 trim round.
    expect(result).toEqual({ posted: 1, degraded: 1, retried: 1 });
    expect(octokit.rest.pulls.createReview).toHaveBeenCalledTimes(2);

    // The second POST should carry only the kept (front-half) finding.
    const secondCall = octokit.rest.pulls.createReview.mock.calls[1][0];
    expect(secondCall.comments).toHaveLength(1);
    expect(secondCall.comments[0].path).toBe("file0.ts");

    // Degraded findings are also posted as a standalone comment.
    expect(octokit.rest.issues.createComment).toHaveBeenCalledTimes(1);
  });

  // -- pickToTrim binary search through the loop ----------------------------

  it("pickToTrim binary search: 4 findings, all 422 → trimmed over 3 rounds", async () => {
    const inline = makeFindings(4);
    octokit.rest.pulls.createReview.mockRejectedValue(err422());

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline, degraded: [], summary: "Summary" },
      config,
    );

    // Round 1: keep 2, trim 2.  Round 2: keep 1, trim 1.  Round 3: trim last 1.
    expect(result).toEqual({ posted: 0, degraded: 4, retried: 3 });
    expect(octokit.rest.issues.createComment).toHaveBeenCalledTimes(1);
  });

  // -- pickToTrim with offending hints from 422 error body ------------------

  it("pickToTrim: identifies the offending comment from 422 error hints", async () => {
    const good = makeFinding({ file: "src/a.ts", line: 5, comment: "good comment" });
    const bad = makeFinding({ file: "src/b.ts", line: 10, comment: "bad comment" });

    octokit.rest.pulls.createReview
      .mockRejectedValueOnce(
        err422({ response: { data: { errors: [{ field: "line", value: 10 }] } } }),
      )
      .mockResolvedValueOnce({ data: { id: 1 } });

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline: [good, bad], degraded: [], summary: "Summary" },
      config,
    );

    // Only the offending comment (line 10) is trimmed; the good one is posted.
    expect(result).toEqual({ posted: 1, degraded: 1, retried: 1 });

    const secondCall = octokit.rest.pulls.createReview.mock.calls[1][0];
    expect(secondCall.comments).toHaveLength(1);
    expect(secondCall.comments[0].path).toBe("src/a.ts");
  });

  // -- MAX_TRIM_ROUNDS cap ---------------------------------------------------

  it("MAX_TRIM_ROUNDS cap: every 422 → all inline moved to degraded", async () => {
    // 32 findings: binary search takes 5 rounds to reduce to 1; the 6th 422
    // hits the cap (retried > MAX_TRIM_ROUNDS=5) and the last one is degraded.
    const inline = makeFindings(32);
    octokit.rest.pulls.createReview.mockRejectedValue(err422());

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline, degraded: [], summary: "Summary" },
      config,
    );

    expect(result.posted).toBe(0);
    expect(result.degraded).toBe(32);
    expect(result.retried).toBe(6); // 5 successful trims + 1 that hits the cap
    // Degraded comment is still posted.
    expect(octokit.rest.issues.createComment).toHaveBeenCalledTimes(1);
  });

  // -- Dedupe: filters out inline findings already on the PR -----------------

  it("filters out inline findings that already exist as review comments", async () => {
    const dup = makeFinding({ file: "src/a.ts", line: 10, comment: "fix this" });
    const unique = makeFinding({ file: "src/b.ts", line: 20, comment: "another" });

    octokit.rest.pulls.listReviewComments.mockResolvedValueOnce({
      data: [{ path: "src/a.ts", line: 10, body: "fix this" }],
    });

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline: [dup, unique], degraded: [], summary: "Summary" },
      config,
    );

    expect(result).toEqual({ posted: 1, degraded: 0, retried: 0 });

    const reviewCall = octokit.rest.pulls.createReview.mock.calls[0][0];
    expect(reviewCall.comments).toHaveLength(1);
    expect(reviewCall.comments[0].path).toBe("src/b.ts");
  });

  // -- All inline deduped → summary-only review for degraded -----------------

  it("posts a summary-only review when all inline are deduped but degraded remain", async () => {
    const dup = makeFinding({ file: "src/a.ts", line: 10, comment: "dup" });

    octokit.rest.pulls.listReviewComments.mockResolvedValueOnce({
      data: [{ path: "src/a.ts", line: 10, body: "dup" }],
    });

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      {
        inline: [dup],
        degraded: [makeFinding({ file: "d.ts", line: null, comment: "degraded" })],
        summary: "Summary",
      },
      config,
    );

    // No inline posted (deduped), but degraded posted as issue comment.
    expect(result).toEqual({ posted: 0, degraded: 1, retried: 0 });

    // createReview called once (summary-only, empty comments array).
    expect(octokit.rest.pulls.createReview).toHaveBeenCalledTimes(1);
    const reviewCall = octokit.rest.pulls.createReview.mock.calls[0][0];
    expect(reviewCall.comments).toEqual([]);
    expect(octokit.rest.issues.createComment).toHaveBeenCalledTimes(1);
  });

  // -- Non-422 error: does not retry, bails gracefully -----------------------

  it("non-422 error on createReview: bails without trim, still posts degraded", async () => {
    octokit.rest.pulls.createReview.mockRejectedValue({ status: 404 });

    const result = await publishReview(
      asOctokit(octokit),
      "owner",
      "repo",
      1,
      { inline: makeFindings(2), degraded: [makeFinding({ line: null })], summary: "Summary" },
      config,
    );

    // No inline posted; degraded posted as standalone comment.
    expect(result.posted).toBe(0);
    expect(result.degraded).toBe(1);
    expect(result.retried).toBe(0);
    expect(octokit.rest.issues.createComment).toHaveBeenCalledTimes(1);
  });
});
// ---------------------------------------------------------------------------
// createPendingReview
// ---------------------------------------------------------------------------

describe("publisher / createPendingReview", () => {
  let octokit: MockOctokit;

  beforeEach(() => {
    octokit = makeMockOctokit();
  });

  it("creates a PENDING review with inline comments and returns the review id", async () => {
    const inline = makeFindings(3);
    const result = await createPendingReview(
      asOctokit(octokit), "owner", "repo", 1,
      { inline, degraded: [], summary: "Summary" }, config,
    );

    expect(result.reviewId).toBe(1);
    expect(result.posted).toBe(3);
    expect(result.degraded).toBe(0);
    expect(result.retried).toBe(0);

    const call = octokit.rest.pulls.createReview.mock.calls[0][0];
    // GitHub creates a pending review by omitting `event` (not "PENDING").
    expect(call.event).toBeUndefined();
    expect(call.comments).toHaveLength(3);
    // Never posts a standalone issue comment (degraded stays in the review body).
    expect(octokit.rest.issues.createComment).not.toHaveBeenCalled();
  });

  it("throws when there is nothing to post", async () => {
    await expect(createPendingReview(
      asOctokit(octokit), "owner", "repo", 1,
      { inline: [], degraded: [], summary: "LGTM" }, config,
    )).rejects.toThrow();
    expect(octokit.rest.pulls.createReview).not.toHaveBeenCalled();
  });

  it("propagates fatal (non-422) errors", async () => {
    octokit.rest.pulls.createReview.mockRejectedValue({ status: 404 });
    await expect(createPendingReview(
      asOctokit(octokit), "owner", "repo", 1,
      { inline: makeFindings(2), degraded: [], summary: "S" }, config,
    )).rejects.toThrow();
  });

  it("progressive trim on 422: posts kept inline, degrades the rest (PENDING)", async () => {
    const inline = makeFindings(2);
    octokit.rest.pulls.createReview
      .mockRejectedValueOnce(err422())
      .mockResolvedValueOnce({ data: { id: 7 } });

    const result = await createPendingReview(
      asOctokit(octokit), "owner", "repo", 1,
      { inline, degraded: [], summary: "S" }, config,
    );

    expect(result.reviewId).toBe(7);
    expect(result.posted).toBe(1);
    expect(result.degraded).toBe(1);
    expect(result.retried).toBe(1);
    expect(octokit.rest.issues.createComment).not.toHaveBeenCalled();
  });

  it("summary-only PENDING fallback when all inline are trimmed", async () => {
    // 422 only when there are inline comments; a body-only review succeeds.
    octokit.rest.pulls.createReview.mockImplementation(async (params: { comments?: unknown[] }) => {
      if (params.comments && params.comments.length > 0) throw err422();
      return { data: { id: 9 } };
    });

    const result = await createPendingReview(
      asOctokit(octokit), "owner", "repo", 1,
      { inline: makeFindings(2), degraded: [], summary: "S" }, config,
    );

    expect(result.reviewId).toBe(9);
    expect(result.posted).toBe(0);
    expect(result.degraded).toBe(2);

    const lastCall = octokit.rest.pulls.createReview.mock.calls.at(-1)![0];
    expect(lastCall.event).toBeUndefined();
    expect(lastCall.comments).toEqual([]);
    expect(octokit.rest.issues.createComment).not.toHaveBeenCalled();
  });

  it("folds degraded findings into the review body, no standalone comment", async () => {
    const degraded = [makeFinding({ file: "d.ts", line: null, comment: "cant place" })];
    const result = await createPendingReview(
      asOctokit(octokit), "owner", "repo", 1,
      { inline: [makeFinding({ file: "ok.ts", line: 5 })], degraded, summary: "S" }, config,
    );

    expect(result.posted).toBe(1);
    expect(result.degraded).toBe(1);
    expect(octokit.rest.issues.createComment).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// submitPendingReview / discardPendingReview
// ---------------------------------------------------------------------------

describe("publisher / submitPendingReview & discardPendingReview", () => {
  let octokit: MockOctokit;

  beforeEach(() => {
    octokit = makeMockOctokit();
  });

  it("submitPendingReview calls submitReview with COMMENT", async () => {
    await submitPendingReview(asOctokit(octokit), "o", "r", 5, 99);

    const call = octokit.rest.pulls.submitReview.mock.calls[0][0];
    expect(call.review_id).toBe(99);
    expect(call.pull_number).toBe(5);
    expect(call.event).toBe("COMMENT");
  });

  it("discardPendingReview calls deletePendingReview", async () => {
    await discardPendingReview(asOctokit(octokit), "o", "r", 5, 99);

    const call = octokit.rest.pulls.deletePendingReview.mock.calls[0][0];
    expect(call.review_id).toBe(99);
    expect(call.pull_number).toBe(5);
  });
});
