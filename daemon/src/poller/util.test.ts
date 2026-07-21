import { describe, it, expect } from "vitest";

import { prId, sleep } from "./util";

describe("prId", () => {
  it("is deterministic — same input always produces the same output", () => {
    const a = prId("owner/repo", 42);
    const b = prId("owner/repo", 42);
    expect(a).toBe(b);
  });

  it("always returns a non-negative value (uses >>> 0)", () => {
    const samples: Array<[string, number]> = [
      ["owner/repo", 1],
      ["a/b", 42],
      ["", 0],
      ["octocat/Hello-World", 65535],
      ["x".repeat(100), 99999],
      ["some/repo", Number.MAX_SAFE_INTEGER],
    ];
    for (const [repo, number] of samples) {
      expect(prId(repo, number)).toBeGreaterThanOrEqual(0);
    }
  });

  it("matches the known FNV-1a vector for ('owner/repo', 42)", () => {
    // Computed once from the implementation; pins the hash algorithm so a
    // silent change (e.g. swapped prime / basis) is caught.
    expect(prId("owner/repo", 42)).toBe(4115684964);
  });

  it("produces different ids for different repos with the same number", () => {
    expect(prId("owner/repo", 42)).not.toBe(prId("other/repo", 42));
  });

  it("produces different ids for the same repo with different numbers", () => {
    expect(prId("owner/repo", 42)).not.toBe(prId("owner/repo", 43));
  });

  it("returns a value within the uint32 range [0, 4294967295]", () => {
    const samples: Array<[string, number]> = [
      ["owner/repo", 42],
      ["a/b", 42],
      ["", 0],
    ];
    for (const [repo, number] of samples) {
      const id = prId(repo, number);
      expect(Number.isInteger(id)).toBe(true);
      expect(id).toBeGreaterThanOrEqual(0);
      expect(id).toBeLessThanOrEqual(4294967295);
    }
  });
});

describe("sleep", () => {
  it("resolves after approximately the given time", async () => {
    const ms = 50;
    const start = Date.now();
    await sleep(ms);
    const elapsed = Date.now() - start;

    expect(elapsed).toBeGreaterThanOrEqual(ms);
    // Generous upper bound for timer jitter / event-loop scheduling.
    expect(elapsed).toBeLessThan(ms + 100);
  });

  it("resolves with undefined", async () => {
    await expect(sleep(1)).resolves.toBeUndefined();
  });
});
