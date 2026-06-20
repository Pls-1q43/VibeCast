import { describe, it, expect, beforeEach, vi, afterEach } from "vitest";
import { DraftStore, uuid } from "./draftStore.ts";

describe("uuid fallback (non-secure context)", () => {
  afterEach(() => vi.unstubAllGlobals());

  it("returns a valid v4 uuid via crypto.randomUUID when available", () => {
    expect(uuid()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });

  it("does not throw when crypto.randomUUID is missing (http LAN context)", () => {
    // 模拟 http://<ip> 非安全上下文：randomUUID 不存在，仅有 getRandomValues。
    vi.stubGlobal("crypto", {
      getRandomValues: (arr: Uint8Array) => {
        for (let i = 0; i < arr.length; i++) arr[i] = i;
        return arr;
      },
    });
    expect(uuid()).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
  });
});

describe("DraftStore", () => {
  beforeEach(() => {
    localStorage.clear();
  });

  it("starts with empty drafts for all targets", () => {
    const s = new DraftStore();
    expect(s.get("codex").text).toBe("");
    expect(s.get("codex").revision).toBe(0);
    expect(s.get("notion").text).toBe("");
  });

  it("increments revision only on text change", () => {
    const s = new DraftStore();
    const d1 = s.update("codex", "hello", 5, 5);
    expect(d1.revision).toBe(1);
    // 相同文本不递增
    const d2 = s.update("codex", "hello", 3, 3);
    expect(d2.revision).toBe(1);
    const d3 = s.update("codex", "hello world", 11, 11);
    expect(d3.revision).toBe(2);
  });

  it("keeps drafts independent across targets (no cross-write)", () => {
    const s = new DraftStore();
    s.update("codex", "Codex 草稿", 0, 0);
    s.update("workbuddy", "WorkBuddy 草稿", 0, 0);
    expect(s.get("codex").text).toBe("Codex 草稿");
    expect(s.get("workbuddy").text).toBe("WorkBuddy 草稿");
    expect(s.get("notion").text).toBe("");
  });

  it("persists and restores drafts across instances (page reload)", () => {
    const s1 = new DraftStore();
    s1.update("codex", "持久化测试", 6, 6);
    // 新实例模拟刷新后重建
    const s2 = new DraftStore();
    expect(s2.get("codex").text).toBe("持久化测试");
    expect(s2.get("codex").revision).toBe(1);
  });

  it("persists custom target drafts across instances", () => {
    const s1 = new DraftStore();
    s1.update("custom_textedit", "自定义目标草稿", 7, 7);
    const s2 = new DraftStore();
    expect(s2.get("custom_textedit").text).toBe("自定义目标草稿");
    expect(s2.get("custom_textedit").selectionStart).toBe(7);
  });

  it("clear empties text and bumps revision", () => {
    const s = new DraftStore();
    s.update("codex", "to be cleared", 0, 0);
    const d = s.clear("codex");
    expect(d.text).toBe("");
    expect(d.revision).toBe(2); // update=1, clear=2
  });

  it("isSynced reflects acked revision", () => {
    const s = new DraftStore();
    s.update("codex", "abc", 3, 3); // revision 1
    expect(s.isSynced("codex")).toBe(false);
    s.markAcked("codex", 1);
    expect(s.isSynced("codex")).toBe(true);
    s.update("codex", "abcd", 4, 4); // revision 2
    expect(s.isSynced("codex")).toBe(false);
  });

  it("markAcked only moves forward (ignores stale ack)", () => {
    const s = new DraftStore();
    s.update("codex", "abcd", 4, 4); // rev 1
    s.update("codex", "abcde", 5, 5); // rev 2
    s.markAcked("codex", 2);
    s.markAcked("codex", 1); // 迟到的旧 ack 不应回退
    expect(s.isSynced("codex")).toBe(true);
  });
});
