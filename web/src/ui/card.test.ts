import { describe, expect, it, vi } from "vitest";
import { Card } from "./card.ts";
import type { I18n } from "../i18n.ts";

const i18n: I18n = {
  lang: "zh-CN",
  t: (key, values = {}) => key === "card.aria" ? `${values.name} input card` : key,
  status: (status) => status,
  error: (code, fallback) => code ?? fallback ?? "",
};

describe("Card", () => {
  it("grows the textarea to fit restored text", () => {
    const card = makeCard();
    mockScrollHeight(card.textarea, 180);

    card.setText("line 1\nline 2\nline 3");

    expect(card.textarea.style.height).toBe("180px");
  });

  it("grows the textarea on user input", () => {
    const onInput = vi.fn();
    const card = makeCard({ onInput });
    mockScrollHeight(card.textarea, 220);

    card.textarea.value = "a longer draft";
    card.textarea.dispatchEvent(new Event("input"));

    expect(card.textarea.style.height).toBe("220px");
    expect(onInput).toHaveBeenCalledWith("codex");
  });
});

function makeCard(overrides: Partial<ConstructorParameters<typeof Card>[4]> = {}): Card {
  return new Card("codex", "Codex", null, i18n, {
    onFocusTextarea: vi.fn(),
    onInput: vi.fn(),
    onSend: vi.fn(),
    onClear: vi.fn(),
    onRefocus: vi.fn(),
    ...overrides,
  });
}

function mockScrollHeight(textarea: HTMLTextAreaElement, value: number): void {
  Object.defineProperty(textarea, "scrollHeight", {
    configurable: true,
    value,
  });
}
