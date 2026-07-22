import { describe, it, expect } from "vitest";
import { matchPath, matchAnyPath } from "./glob";

describe("matchPath — glob translation", () => {
  it("`src/**` matches a nested path under src/", () => {
    expect(matchPath("src/**", "src/a/b.ts")).toBe(true);
  });

  it("`**/*.generated.ts` matches a nested generated file", () => {
    expect(matchPath("**/*.generated.ts", "x/y/a.generated.ts")).toBe(true);
  });

  it("`**/*.ts` matches a root-level file (M1 fix)", () => {
    expect(matchPath("**/*.ts", "app.ts")).toBe(true);
  });

  it("`**/*.ts` matches a nested file", () => {
    expect(matchPath("**/*.ts", "src/a.ts")).toBe(true);
  });

  it("`vendor/**` matches a file under vendor/", () => {
    expect(matchPath("vendor/**", "vendor/lib.js")).toBe(true);
  });

  it("an exact path matches only that exact path", () => {
    expect(matchPath("dist/index.js", "dist/index.js")).toBe(true);
    expect(matchPath("dist/index.js", "dist/index.jsx")).toBe(false);
    expect(matchPath("dist/index.js", "other/dist/index.js")).toBe(false);
  });

  it("`*.ts` is segment-local (matches root file, NOT a nested file)", () => {
    expect(matchPath("*.ts", "a.ts")).toBe(true);
    expect(matchPath("*.ts", "a/b.ts")).toBe(false);
  });

  it("is case-insensitive", () => {
    expect(matchPath("SRC/**", "src/a.ts")).toBe(true);
    expect(matchPath("src/**", "SRC/a.ts")).toBe(true);
    expect(matchPath("**/*.TS", "app.ts")).toBe(true);
  });

  it("`?` matches exactly one non-slash char (segment-local)", () => {
    expect(matchPath("a?c.ts", "abc.ts")).toBe(true);
    expect(matchPath("a?c.ts", "ac.ts")).toBe(false);
    expect(matchPath("a?c.ts", "a/c.ts")).toBe(false);
  });

  it("does not match a path that shares a prefix but diverges", () => {
    expect(matchPath("src/*.ts", "src/a.ts")).toBe(true);
    expect(matchPath("src/*.ts", "src/sub/a.ts")).toBe(false);
  });
});

describe("matchAnyPath", () => {
  it("returns false for an empty patterns array (inert)", () => {
    expect(matchAnyPath("anything.ts", [])).toBe(false);
  });

  it("returns true when ANY pattern matches", () => {
    expect(matchAnyPath("src/a.ts", ["docs/**", "src/**"])).toBe(true);
  });

  it("returns false when NO pattern matches", () => {
    expect(matchAnyPath("src/a.ts", ["docs/**", "vendor/**"])).toBe(false);
  });

  it("one matching + one non-matching ⇒ true", () => {
    expect(matchAnyPath("src/a.ts", ["docs/**", "src/**"])).toBe(true);
    expect(matchAnyPath("vendor/x.js", ["src/**", "vendor/**"])).toBe(true);
  });
});
