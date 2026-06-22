import { beforeEach, describe, expect, it } from "vitest";
import { applyTheme, normalizeTheme, readTheme, writeTheme } from "./theme.ts";

describe("theme", () => {
  beforeEach(() => {
    localStorage.clear();
    delete document.documentElement.dataset.theme;
  });

  it("defaults to automatic device theme", () => {
    expect(readTheme()).toBe("auto");
    expect(normalizeTheme("surprise")).toBe("auto");
  });

  it("persists the E-Ink theme choice", () => {
    writeTheme("eink");

    expect(readTheme()).toBe("eink");
  });

  it("applies and clears the document theme marker", () => {
    applyTheme("eink");
    expect(document.documentElement.dataset.theme).toBe("eink");

    applyTheme("auto");
    expect(document.documentElement.dataset.theme).toBeUndefined();
  });
});
