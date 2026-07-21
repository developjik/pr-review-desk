import { describe, it, expect } from "vitest";
import {
  pushToast,
  dismissToast,
  initialToastQueueState,
  type ToastQueueState,
} from "./toastQueue";
import type { ToastVariant } from "../components/ui/Toast";

/** Structural snapshot used for the immutability deep-equal checks. */
function snapshot(s: ToastQueueState): unknown {
  return JSON.parse(JSON.stringify(s));
}

/** Simulates a caller's synchronous id counter (mirrors ToastProvider's nextIdRef). */
function* counter(start = 1): Generator<number> {
  let n = start;
  while (true) yield n++;
}

describe("pushToast", () => {
  it("appends a toast with the injected id and advances nextId", () => {
    const next = pushToast(initialToastQueueState, 1, "info", "hi", undefined, 5, 1000);
    expect(next.toasts).toHaveLength(1);
    expect(next.toasts[0]).toMatchObject({
      id: 1,
      variant: "info",
      title: "hi",
      desc: undefined,
    });
    expect(next.nextId).toBe(2);
  });

  it("uses the injected `now` as createdAt", () => {
    const next = pushToast(initialToastQueueState, 1, "info", "hi", undefined, 5, 4242);
    expect(next.toasts[0]?.createdAt).toBe(4242);
  });

  it("stores the optional desc when provided", () => {
    const next = pushToast(initialToastQueueState, 1, "info", "hi", "details", 5, 1);
    expect(next.toasts[0]?.desc).toBe("details");
  });

  it("stores desc as undefined when omitted", () => {
    const next = pushToast(initialToastQueueState, 1, "info", "hi", undefined, 5, 1);
    expect(next.toasts[0]?.desc).toBeUndefined();
  });

  it("advances nextId across successive pushes (ids are sequential)", () => {
    const ids = counter();
    let s = pushToast(initialToastQueueState, ids.next().value, "info", "a", undefined, 5, 1);
    s = pushToast(s, ids.next().value, "info", "b", undefined, 5, 2);
    s = pushToast(s, ids.next().value, "info", "c", undefined, 5, 3);
    expect(s.toasts.map((t) => t.id)).toEqual([1, 2, 3]);
    expect(s.nextId).toBe(4);
  });

  it("maps each variant correctly", () => {
    const variants: ToastVariant[] = ["success", "warning", "error", "info"];
    const ids = counter();
    let s = initialToastQueueState;
    for (const v of variants) {
      s = pushToast(s, ids.next().value, v, v, undefined, 5, 1);
    }
    expect(s.toasts.map((t) => t.variant)).toEqual(variants);
  });

  it("does not mutate the input state", () => {
    const before = snapshot(initialToastQueueState);
    pushToast(initialToastQueueState, 1, "info", "hi", undefined, 5, 1);
    expect(JSON.parse(JSON.stringify(initialToastQueueState))).toEqual(before);
  });
});

describe("pushToast cap-at-max", () => {
  it("retains exactly `max` toasts once the limit is reached", () => {
    const ids = counter();
    let s = initialToastQueueState;
    for (let i = 0; i < 5; i++) s = pushToast(s, ids.next().value, "info", `t${i}`, undefined, 5, i);
    expect(s.toasts).toHaveLength(5);
  });

  it("drops the OLDEST on overflow and keeps the newest", () => {
    const ids = counter();
    let s = initialToastQueueState;
    for (let i = 0; i < 6; i++) s = pushToast(s, ids.next().value, "info", `t${i}`, undefined, 5, i);
    // The first-pushed (id 1) is dropped; ids 2..6 are kept.
    expect(s.toasts).toHaveLength(5);
    expect(s.toasts.map((t) => t.id)).toEqual([2, 3, 4, 5, 6]);
    expect(s.toasts.map((t) => t.title)).toEqual(["t1", "t2", "t3", "t4", "t5"]);
  });

  it("still advances nextId past dropped entries (no id reuse)", () => {
    const ids = counter();
    let s = initialToastQueueState;
    for (let i = 0; i < 7; i++) s = pushToast(s, ids.next().value, "info", `t${i}`, undefined, 5, i);
    expect(s.nextId).toBe(8);
  });

  it("respects a custom max", () => {
    const ids = counter();
    let s = initialToastQueueState;
    for (let i = 0; i < 4; i++) s = pushToast(s, ids.next().value, "info", `t${i}`, undefined, 2, i);
    expect(s.toasts.map((t) => t.id)).toEqual([3, 4]);
  });
});

describe("dismissToast", () => {
  function seeded(): ToastQueueState {
    const ids = counter();
    let s = initialToastQueueState;
    s = pushToast(s, ids.next().value, "info", "a", undefined, 5, 1);
    s = pushToast(s, ids.next().value, "info", "b", undefined, 5, 2);
    s = pushToast(s, ids.next().value, "info", "c", undefined, 5, 3);
    return s;
  }

  it("removes only the matching id", () => {
    const next = dismissToast(seeded(), 2);
    expect(next.toasts.map((t) => t.id)).toEqual([1, 3]);
  });

  it("is a no-op for an unknown id (returns an equivalent queue)", () => {
    const before = seeded();
    const next = dismissToast(before, 999);
    expect(next.toasts.map((t) => t.id)).toEqual([1, 2, 3]);
    // nextId is unchanged on the no-op path too.
    expect(next.nextId).toBe(before.nextId);
  });

  it("does not mutate the input state", () => {
    const state = seeded();
    const before = snapshot(state);
    dismissToast(state, 2);
    expect(JSON.parse(JSON.stringify(state))).toEqual(before);
  });

  it("returns a new state object (referential inequality)", () => {
    const state = seeded();
    const next = dismissToast(state, 999);
    expect(next).not.toBe(state);
    expect(next.toasts).not.toBe(state.toasts);
  });
});
