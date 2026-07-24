import { describe, it, expect } from "vitest";
import {
  commentKey,
  partitionByExisting,
  type ExistingComment,
  type NewComment,
} from "./dedupe";

function existing(
  overrides: Partial<ExistingComment> & { path: string; line: number; body: string },
): ExistingComment {
  return { id: 1, pull_request_review_id: 1, ...overrides };
}

function nc(path: string, line: number, body: string): NewComment {
  return { path, line, body };
}

describe("publisher/dedupe — partitionByExisting", () => {
  it("splits matched comments into `reply` and unmatched into `keep`", () => {
    const existingComments = [
      existing({ path: "a.ts", line: 1, body: "x", id: 10, pull_request_review_id: 100 }),
    ];
    const newComments = [
      nc("a.ts", 1, "x"), // matches → reply
      nc("b.ts", 2, "y"), // no match → keep
    ];

    const { keep, reply } = partitionByExisting(existingComments, newComments);

    expect(keep).toEqual([nc("b.ts", 2, "y")]);
    expect(reply).toHaveLength(1);
    expect(reply[0].new).toEqual(nc("a.ts", 1, "x"));
    expect(reply[0].target.id).toBe(10);
    expect(reply[0].target.pull_request_review_id).toBe(100);
  });

  it("empty existing → all new comments go to `keep`, none to `reply`", () => {
    const newComments = [nc("a.ts", 1, "x"), nc("b.ts", 2, "y")];

    const { keep, reply } = partitionByExisting([], newComments);

    expect(keep).toEqual(newComments);
    expect(reply).toEqual([]);
  });

  it("all new comments match → `keep` empty, `reply` full", () => {
    const existingComments = [
      existing({ path: "a.ts", line: 1, body: "x" }),
      existing({ path: "b.ts", line: 2, body: "y" }),
    ];
    const newComments = [nc("a.ts", 1, "x"), nc("b.ts", 2, "y")];

    const { keep, reply } = partitionByExisting(existingComments, newComments);

    expect(keep).toEqual([]);
    expect(reply.map((r) => r.target.id)).toEqual([1, 1]);
  });

  it("stable first-match tie-break: first existing comment wins when several share a key", () => {
    // Two existing comments with the SAME (path, line, body); the first (id=10)
    // must be chosen as the reply target, deterministically.
    const existingComments = [
      existing({ path: "a.ts", line: 1, body: "x", id: 10, pull_request_review_id: 100 }),
      existing({ path: "a.ts", line: 1, body: "x", id: 20, pull_request_review_id: 200 }),
    ];
    const newComments = [nc("a.ts", 1, "x")];

    const { keep, reply } = partitionByExisting(existingComments, newComments);

    expect(keep).toEqual([]);
    expect(reply).toHaveLength(1);
    expect(reply[0].target.id).toBe(10);
    expect(reply[0].target.pull_request_review_id).toBe(100);
  });

  it("preserves newComments order in both `keep` and `reply`", () => {
    const existingComments = [
      existing({ path: "b.ts", line: 2, body: "y", id: 2 }),
      existing({ path: "d.ts", line: 4, body: "z", id: 4 }),
    ];
    const newComments = [
      nc("a.ts", 1, "x"), // keep
      nc("b.ts", 2, "y"), // reply
      nc("c.ts", 3, "w"), // keep
      nc("d.ts", 4, "z"), // reply
    ];

    const { keep, reply } = partitionByExisting(existingComments, newComments);

    expect(keep.map(commentKey)).toEqual([
      commentKey(nc("a.ts", 1, "x")),
      commentKey(nc("c.ts", 3, "w")),
    ]);
    expect(reply.map((r) => r.target.id)).toEqual([2, 4]);
  });
});
