/**
 * cost — pure pricing parse + cost computation (AC4.6 / AC4.9).
 *
 * Exercises parsePricing (multiple models, blank/malformed skipping, empty) and
 * computeCost (exact math, default-rate fallback, zero usage, NaN guard).
 */
import { describe, it, expect } from "vitest";
import { parsePricing, computeCost, type Pricing } from "./cost";
import type { TokenUsage } from "../types/domain";

const U = (p: number, c: number): TokenUsage => ({ promptTokens: p, completionTokens: c, totalTokens: p + c });

describe("parsePricing — line parsing", () => {
  it("parses multiple models into the rates Map", () => {
    const pricing = parsePricing("gpt-4o:2.50,10.00\nglm-5.2:0.50,1.50", 1);
    expect(pricing.rates.size).toBe(2);
    expect(pricing.rates.get("gpt-4o")).toEqual({ promptPer1M: 2.5, completionPer1M: 10 });
    expect(pricing.rates.get("glm-5.2")).toEqual({ promptPer1M: 0.5, completionPer1M: 1.5 });
  });

  it("returns an empty Map for an empty string", () => {
    const pricing = parsePricing("", 1);
    expect(pricing.rates.size).toBe(0);
    expect(pricing.defaultPer1M).toBe(1);
  });

  it("skips blank lines without error", () => {
    const pricing = parsePricing("\n\ngpt-4o:2.50,10.00\n\n  \n", 0);
    expect(pricing.rates.size).toBe(1);
    expect(pricing.rates.has("gpt-4o")).toBe(true);
  });

  it("skips malformed lines (no colon, no comma, non-numeric, negative)", () => {
    const pricing = parsePricing(
      [
        "gpt-4o:2.50,10.00", // valid
        "no-colon-line",     // no colon
        ":1,2",              // empty model name
        "model-no-comma:5",  // no comma / single value
        "bad:abc,2",         // non-numeric prompt
        "bad2:1,xyz",        // non-numeric completion
        "neg:-1,2",          // negative
        "neg2:1,-3",         // negative
      ].join("\n"),
      0,
    );
    expect(pricing.rates.size).toBe(1);
    expect(pricing.rates.has("gpt-4o")).toBe(true);
  });

  it("carries the defaultPer1M through unchanged", () => {
    const pricing = parsePricing("gpt-4o:2.50,10.00", 3.5);
    expect(pricing.defaultPer1M).toBe(3.5);
  });

  it("trims whitespace in model names and rate values", () => {
    const pricing = parsePricing("  gpt-4o : 2.50 , 10.00  ", 0);
    expect(pricing.rates.get("gpt-4o")).toEqual({ promptPer1M: 2.5, completionPer1M: 10 });
  });
});

describe("computeCost — exact math + rate lookup (AC4.6 / AC4.9)", () => {
  const pricing: Pricing = parsePricing("gpt-4o:2.50,10.00\nglm-5.2:0.50,1.50", 1);

  it("known model: exact cost for 1M prompt + 500K completion tokens", () => {
    // gpt-4o: prompt $2.50/1M, completion $10.00/1M
    // 1M prompt × $2.50 + 500K completion × $10.00 = $2.50 + $5.00 = $7.50
    expect(computeCost(U(1_000_000, 500_000), "gpt-4o", pricing)).toBeCloseTo(7.5, 10);
  });

  it("unknown model: falls back to defaultPer1M for both rates (AC4.9)", () => {
    // defaultPer1M = 1 → 1M prompt × $1 + 500K completion × $1 = $1.50
    expect(computeCost(U(1_000_000, 500_000), "unknown-model", pricing)).toBeCloseTo(1.5, 10);
  });

  it("zero usage → 0 cost", () => {
    expect(computeCost(U(0, 0), "gpt-4o", pricing)).toBe(0);
  });

  it("never returns NaN for NaN token inputs (AC4.9)", () => {
    const nanUsage: TokenUsage = { promptTokens: NaN, completionTokens: NaN, totalTokens: NaN };
    const result = computeCost(nanUsage, "gpt-4o", pricing);
    expect(Number.isNaN(result)).toBe(false);
    expect(result).toBe(0);
  });

  it("never returns NaN for Infinity token inputs", () => {
    const infUsage: TokenUsage = { promptTokens: Infinity, completionTokens: Infinity, totalTokens: Infinity };
    const result = computeCost(infUsage, "gpt-4o", pricing);
    expect(Number.isNaN(result)).toBe(false);
    expect(Number.isFinite(result)).toBe(true);
    expect(result).toBe(0);
  });

  it("2-model scenario: modelA and modelB costs differ for the same usage", () => {
    // Same usage, different models → different costs.
    const usage = U(1_000_000, 0);
    const costA = computeCost(usage, "gpt-4o", pricing); // $2.50
    const costB = computeCost(usage, "glm-5.2", pricing); // $0.50
    expect(costA).toBeCloseTo(2.5, 10);
    expect(costB).toBeCloseTo(0.5, 10);
    expect(costA).not.toBe(costB);
  });

  it("sums across two models to the correct monthly total", () => {
    // 500K prompt + 100K completion for each model.
    const costA = computeCost(U(500_000, 100_000), "gpt-4o", pricing);
    // gpt-4o: 0.5M × $2.50 + 0.1M × $10.00 = $1.25 + $1.00 = $2.25
    expect(costA).toBeCloseTo(2.25, 10);
    const costB = computeCost(U(500_000, 100_000), "glm-5.2", pricing);
    // glm-5.2: 0.5M × $0.50 + 0.1M × $1.50 = $0.25 + $0.15 = $0.40
    expect(costB).toBeCloseTo(0.4, 10);
    expect(costA + costB).toBeCloseTo(2.65, 10);
  });
});
