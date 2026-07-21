import { describe, it, expect } from "vitest";
import { CHARS_PER_TOKEN, estimateTokens } from "./token-budget";

describe("token-budget", () => {
  it("exposes CHARS_PER_TOKEN === 4", () => {
    expect(CHARS_PER_TOKEN).toBe(4);
  });

  it("estimates zero tokens for the empty string", () => {
    expect(estimateTokens("")).toBe(0);
  });

  it("estimates tokens proportionally to length (chars / 4, ceil)", () => {
    // 4 chars -> 1 token; 5 chars -> 2 tokens (ceil).
    expect(estimateTokens("abcd")).toBe(1);
    expect(estimateTokens("abcde")).toBe(2);
    // Doubling the length doubles the estimate.
    const short = "x".repeat(40);
    const long = "x".repeat(80);
    expect(estimateTokens(long)).toBe(estimateTokens(short) * 2);
    // Exact multiple of CHARS_PER_TOKEN has no rounding remainder.
    expect(estimateTokens("x".repeat(CHARS_PER_TOKEN * 10))).toBe(10);
  });
});
