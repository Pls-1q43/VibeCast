import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { IMEController, type Snapshot } from "./imeController.ts";

function makeTextarea(): HTMLTextAreaElement {
  const ta = document.createElement("textarea");
  document.body.append(ta);
  return ta;
}

describe("IMEController", () => {
  let ta: HTMLTextAreaElement;
  let snaps: Snapshot[];

  beforeEach(() => {
    vi.useFakeTimers();
    ta = makeTextarea();
    snaps = [];
  });

  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = "";
  });

  function attach(opts: Partial<{ debounceMs: number; composingThrottleMs: number }> = {}) {
    return new IMEController(ta, {
      debounceMs: opts.debounceMs ?? 120,
      composingThrottleMs: opts.composingThrottleMs ?? 250,
      onSnapshot: (s) => snaps.push(s),
    });
  }

  it("debounces normal input", () => {
    attach();
    ta.value = "a";
    ta.dispatchEvent(new Event("input"));
    ta.value = "ab";
    ta.dispatchEvent(new Event("input"));
    // 防抖期内不应触发
    expect(snaps.length).toBe(0);
    vi.advanceTimersByTime(120);
    // 只发最新一次
    expect(snaps.length).toBe(1);
    expect(snaps[0].text).toBe("ab");
  });

  it("flushNow emits immediately, bypassing debounce", () => {
    const ime = attach();
    ta.value = "立即同步";
    ta.dispatchEvent(new Event("input"));
    ime.flushNow();
    expect(snaps.length).toBe(1);
    expect(snaps[0].text).toBe("立即同步");
    expect(snaps[0].isComposing).toBe(false);
  });

  it("emits final snapshot on compositionend", () => {
    attach();
    ta.dispatchEvent(new Event("compositionstart"));
    ta.value = "组合中";
    ta.dispatchEvent(new Event("compositionupdate"));
    ta.value = "组合完成";
    ta.dispatchEvent(new Event("compositionend"));
    // compositionend 立即同步最终文本
    const last = snaps[snaps.length - 1];
    expect(last.text).toBe("组合完成");
    expect(last.isComposing).toBe(false);
  });

  it("throttles during composition", () => {
    attach({ composingThrottleMs: 250 });
    ta.dispatchEvent(new Event("compositionstart"));
    ta.value = "拼";
    ta.dispatchEvent(new Event("compositionupdate"));
    ta.value = "拼音";
    ta.dispatchEvent(new Event("compositionupdate"));
    // 节流：尚未到时间窗，最多一次待发
    expect(snaps.length).toBe(0);
    vi.advanceTimersByTime(250);
    expect(snaps.length).toBe(1);
    expect(snaps[0].isComposing).toBe(true);
  });
});
