import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import type { Config } from "../config/schema";
import type { PrPromptMeta } from "./prompts";

// The internal parseReviewResponse / normalizeFinding / normalizeSeverity /
// normalizeArea / isRetryable helpers are module-private, so we drive them
// through `createLlmClient` by stubbing the OpenAI SDK. `vi.hoisted` keeps the
// shared mock reference available to the (hoisted) `vi.mock` factory.
const mocks = vi.hoisted(() => ({
  create: vi.fn(),
}));

vi.mock("openai", () => ({
  default: class {
    chat = {
      completions: {
        create: mocks.create,
      },
    };
  },
}));

import { createLlmClient, type LlmFileReview } from "./llm-client";

// `createLlmClient` only reads these config fields; the rest of the Config
// shape is irrelevant to the reviewer path under test.
function makeConfig(overrides: Partial<Config> = {}): Config {
  return {
    githubUsername: "octocat",
    githubPat: "pat",
    llmBaseUrl: "https://example.test/v1",
    llmApiKey: "key",
    llmModel: "test-model",
    pollIntervalMin: 15,
    showSeverity: true,
    osNotify: false,
    dbPath: "/tmp/reviews.db",
    logDir: "/tmp/logs",
    ...overrides,
  } as Config;
}

const prMeta: PrPromptMeta = {
  title: "Fix bug",
  body: "does a thing",
  author: "octocat",
  number: 42,
  repo: "owner/repo",
};

/** Wrap a JSON string as the `choices[0].message.content` the SDK returns. */
function llmResponse(content: string, usage?: Record<string, unknown>): unknown {
  return {
    choices: [{ message: { content } }],
    ...(usage ? { usage } : {}),
  };
}

/** Call reviewFile with stubbed trivial inputs and return the parsed result. */
async function review(content: string, usage?: Record<string, unknown>): Promise<LlmFileReview> {
  mocks.create.mockResolvedValueOnce(llmResponse(content, usage));
  return createLlmClient(makeConfig()).reviewFile("src/app.ts", "code", "", prMeta, "en");
}

/**
 * Drive fake-timer-backed `sleep` calls inside `reviewFile` until `promise`
 * settles. Guarded so a non-settling promise can't hang the suite.
 */
async function settle(promise: Promise<unknown>): Promise<void> {
  let done = false;
  const mark = () => {
    done = true;
  };
  promise.then(mark, mark);
  let guard = 0;
  while (!done && guard < 50) {
    await vi.advanceTimersByTimeAsync(10_000);
    guard++;
  }
}

describe("createLlmClient — parseReviewResponse behaviors", () => {
  beforeEach(() => mocks.create.mockReset());

  it("parses a valid JSON response with findings correctly", async () => {
    const content = JSON.stringify({
      summary: "Looks mostly fine with one nit.",
      findings: [
        {
          file: "src/app.ts",
          line: 12,
          severity: "high",
          area: "bug",
          comment: "Null dereference here.",
          suggestion: "Add a null check.",
        },
        {
          file: "src/app.ts",
          line: 30,
          severity: "low",
          area: "style",
          comment: "Rename for clarity.",
        },
      ],
    });

    const result = await review(content);

    expect(result.summary).toBe("Looks mostly fine with one nit.");
    expect(result.findings).toHaveLength(2);
    expect(result.findings[0]).toEqual({
      file: "src/app.ts",
      line: 12,
      severity: "high",
      area: "bug",
      comment: "Null dereference here.",
      suggestion: "Add a null check.",
    });
    expect(result.findings[1]).toEqual({
      file: "src/app.ts",
      line: 30,
      severity: "low",
      area: "style",
      comment: "Rename for clarity.",
      suggestion: undefined,
    });
  });

  it("returns empty findings for a valid JSON response with an empty findings array", async () => {
    const result = await review(JSON.stringify({ findings: [], summary: "Clean." }));

    expect(result.findings).toEqual([]);
    expect(result.summary).toBe("Clean.");
  });

  it("does NOT throw on malformed JSON — returns empty findings + error summary", async () => {
    const result = await review("this is not { valid json");

    expect(result.findings).toEqual([]);
    expect(result.summary).toBe("Failed to parse LLM response as JSON.");
  });

  it("drops a finding missing the 'comment' field (returns null)", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [
        { file: "src/app.ts", line: 1, severity: "high", area: "bug" },
        { comment: "This one is kept.", line: 2, severity: "low", area: "style" },
      ],
    });

    const result = await review(content);

    expect(result.findings).toHaveLength(1);
    expect(result.findings[0].comment).toBe("This one is kept.");
  });

  it("drops a finding whose comment is only whitespace", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [{ comment: "   " }],
    });

    const result = await review(content);

    expect(result.findings).toEqual([]);
  });

  it("defaults an unknown severity to 'low'", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [{ comment: "x", severity: "bogus-severity", area: "bug" }],
    });

    const result = await review(content);

    expect(result.findings[0].severity).toBe("low");
  });

  it("normalizes 'critical' and 'high' severities to 'high'", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [
        { comment: "c", severity: "critical" },
        { comment: "h", severity: "HIGH" },
      ],
    });

    const result = await review(content);

    expect(result.findings.map((f) => f.severity)).toEqual(["high", "high"]);
  });

  it("defaults an unknown area to 'style'", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [{ comment: "x", severity: "low", area: "nonsense" }],
    });

    const result = await review(content);

    expect(result.findings[0].area).toBe("style");
  });

  it("accepts all valid areas", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [
        { comment: "b", area: "bug" },
        { comment: "s", area: "style" },
        { comment: "st", area: "structure" },
        { comment: "se", area: "security" },
      ],
    });

    const result = await review(content);

    expect(result.findings.map((f) => f.area)).toEqual([
      "bug",
      "style",
      "structure",
      "security",
    ]);
  });

  it("sets line to null when 'line' is missing", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [{ comment: "x", severity: "low", area: "style" }],
    });

    const result = await review(content);

    expect(result.findings[0].line).toBeNull();
  });

  it("sets line to null when 'line' is not a number", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [
        { comment: "a", line: "abc" },
        { comment: "b", line: true },
        { comment: "c", line: "42" },
      ],
    });

    const result = await review(content);

    for (const f of result.findings) {
      expect(f.line).toBeNull();
    }
  });

  it("uses the defaultFile when a finding omits 'file'", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [{ comment: "x", line: 1 }],
    });

    const result = await review(content);

    expect(result.findings[0].file).toBe("src/app.ts");
  });

  it("keeps a finite numeric line", async () => {
    const content = JSON.stringify({
      summary: "",
      findings: [{ comment: "x", line: 137 }],
    });

    const result = await review(content);

    expect(result.findings[0].line).toBe(137);
  });

  it("defaults summary to '' when the field is missing or non-string", async () => {
    const result = await review(JSON.stringify({ findings: [{ comment: "x" }] }));
    expect(result.summary).toBe("");
  });

  it("defaults findings to [] when the field is missing or not an array", async () => {
    const result = await review(JSON.stringify({ summary: "s", findings: "nope" }));
    expect(result.findings).toEqual([]);
  });

  it("treats an empty/whitespace content as malformed JSON", async () => {
    const result = await review("");
    expect(result.findings).toEqual([]);
    expect(result.summary).toBe("Failed to parse LLM response as JSON.");
  });
});

describe("createLlmClient — F1 guidelines wiring (AC1.4)", () => {
  beforeEach(() => mocks.create.mockReset());

  /** Extract the system message from the captured OpenAI `create` call. */
  const capturedSystem = (): string => {
    const arg = mocks.create.mock.calls[0]?.[0] as
      | { messages?: Array<{ role: string; content: string }> }
      | undefined;
    return arg?.messages?.find((m) => m.role === "system")?.content ?? "";
  };

  it("threads non-empty rules into the system message", async () => {
    mocks.create.mockResolvedValueOnce(llmResponse(JSON.stringify({ findings: [], summary: "" })));
    await createLlmClient(makeConfig()).reviewFile(
      "src/app.ts", "code", "", prMeta, "en", "MY-GUIDELINE-7",
    );
    const system = capturedSystem();
    expect(system).toContain("Team / project guidelines");
    expect(system).toContain("MY-GUIDELINE-7");
  });

  it("omits the guidelines section when rules is empty", async () => {
    mocks.create.mockResolvedValueOnce(llmResponse(JSON.stringify({ findings: [], summary: "" })));
    await createLlmClient(makeConfig()).reviewFile(
      "src/app.ts", "code", "", prMeta, "en", "",
    );
    expect(capturedSystem()).not.toContain("Team / project guidelines");
  });

  it("omits the guidelines section when rules is omitted (undefined)", async () => {
    mocks.create.mockResolvedValueOnce(llmResponse(JSON.stringify({ findings: [], summary: "" })));
    await createLlmClient(makeConfig()).reviewFile("src/app.ts", "code", "", prMeta, "en");
    expect(capturedSystem()).not.toContain("Team / project guidelines");
  });
});

describe("createLlmClient — retry behavior (isRetryable)", () => {
  beforeEach(() => {
    mocks.create.mockReset();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  // MAX_RETRIES = 3 in llm-client.ts; a retryable error exhausts all attempts.
  const MAX_RETRIES = 3;

  const retryableCases: Array<{ name: string; error: unknown }> = [
    { name: "HTTP 429", error: Object.assign(new Error("rate limited"), { status: 429 }) },
    { name: "HTTP 500", error: Object.assign(new Error("server error"), { status: 500 }) },
    { name: "HTTP 503", error: Object.assign(new Error("unavailable"), { status: 503 }) },
    { name: "name 'APIConnectionError'", error: Object.assign(new Error("conn"), { name: "APIConnectionError" }) },
    {
      name: "name 'APIConnectionTimeoutError'",
      error: Object.assign(new Error("conn"), { name: "APIConnectionTimeoutError" }),
    },
    { name: "message containing 'timeout'", error: new Error("operation timed out") },
    { name: "message containing 'fetch failed'", error: new Error("fetch failed") },
  ];

  for (const { name, error } of retryableCases) {
    it(`retries on ${name} (exhausts all attempts, then throws)`, async () => {
      mocks.create.mockRejectedValue(error);

      const client = createLlmClient(makeConfig());
      const promise = client.reviewFile("src/app.ts", "code", "", prMeta, "en");

      await settle(promise);

      await expect(promise).rejects.toThrow();
      expect(mocks.create).toHaveBeenCalledTimes(MAX_RETRIES);
    });
  }

  it("does NOT retry on HTTP 400 (single attempt, then throws)", async () => {
    const error = Object.assign(new Error("bad request"), { status: 400 });
    mocks.create.mockRejectedValue(error);

    const client = createLlmClient(makeConfig());
    const promise = client.reviewFile("src/app.ts", "code", "", prMeta, "en");

    // No fake-timer drain needed — a non-retryable error breaks immediately.
    await expect(promise).rejects.toThrow();
    expect(mocks.create).toHaveBeenCalledTimes(1);
  });

  it("does NOT retry on a plain non-transient error with no status/name match", async () => {
    mocks.create.mockRejectedValue(new Error("something else entirely"));

    const client = createLlmClient(makeConfig());
    const promise = client.reviewFile("src/app.ts", "code", "", prMeta, "en");

    await expect(promise).rejects.toThrow();
    expect(mocks.create).toHaveBeenCalledTimes(1);
  });

  it("recovers after a transient failure then succeeds on a later attempt", async () => {
    mocks.create
      .mockRejectedValueOnce(Object.assign(new Error("rate"), { status: 429 }))
      .mockResolvedValueOnce(
        llmResponse(JSON.stringify({ findings: [{ comment: "ok" }], summary: "fine" })),
      );

    const client = createLlmClient(makeConfig());
    const promise = client.reviewFile("src/app.ts", "code", "", prMeta, "en");

    await settle(promise);
    const result = await promise;

    expect(mocks.create).toHaveBeenCalledTimes(2);
    expect(result.findings).toHaveLength(1);
    expect(result.findings[0].comment).toBe("ok");
  });
});

describe("createLlmClient — token usage capture (#4, AC4.7)", () => {
  beforeEach(() => mocks.create.mockReset());

  const EMPTY = JSON.stringify({ findings: [], summary: "" });

  it("(a) numeric usage: maps snake_case prompt_tokens/completion_tokens/total_tokens → TokenUsage", async () => {
    const result = await review(EMPTY, {
      prompt_tokens: 100,
      completion_tokens: 20,
      total_tokens: 120,
    });
    expect(result.usage).toEqual({ promptTokens: 100, completionTokens: 20, totalTokens: 120 });
  });

  it("(b) string usage (vLLM/Ollama compat — the reason toFiniteNumber exists): coerces numeric strings to numbers", async () => {
    const result = await review(EMPTY, {
      prompt_tokens: "1500",
      completion_tokens: "300",
      total_tokens: "1800",
    });
    expect(result.usage).toEqual({ promptTokens: 1500, completionTokens: 300, totalTokens: 1800 });
  });

  it("(c) non-numeric junk: coerces to 0 (never NaN — safe for SUM, SQLite INTEGER, review:summary)", async () => {
    const result = await review(EMPTY, {
      prompt_tokens: "abc",
      completion_tokens: null,
      total_tokens: undefined,
    });
    expect(result.usage).toEqual({ promptTokens: 0, completionTokens: 0, totalTokens: 0 });
  });

  it("(d) absent resp.usage: returns null (not an empty object, not undefined)", async () => {
    const result = await review(EMPTY);
    expect(result.usage).toBeNull();
  });
});
