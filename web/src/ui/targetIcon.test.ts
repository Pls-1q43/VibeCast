import { describe, expect, it } from "vitest";
import { isSafeImageDataUrl, renderTargetIcon, targetIconSrc } from "./targetIcon.ts";

describe("targetIcon", () => {
  it("prefers safe configured data urls", () => {
    expect(targetIconSrc("codex", "data:image/png;base64,ZmFrZQ==")).toBe("data:image/png;base64,ZmFrZQ==");
  });

  it("falls back to preset icons for known targets", () => {
    expect(targetIconSrc("notion", null)).toBe("./target-icons/notion.svg");
    expect(targetIconSrc("codebuddycn", null)).toBe("./target-icons/codebuddy.svg");
  });

  it("rejects remote icon urls", () => {
    expect(isSafeImageDataUrl("https://example.com/icon.png")).toBe(false);
    expect(targetIconSrc("custom_app", "https://example.com/icon.png")).toBeNull();
  });

  it("renders an image when an icon source is available", () => {
    const icon = renderTargetIcon("workbuddy", "WorkBuddy", "card__icon", null);
    expect(icon.querySelector("img")?.getAttribute("src")).toBe("./target-icons/workbuddy.svg");
  });
});
