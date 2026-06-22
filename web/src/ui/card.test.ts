import { afterEach, describe, expect, it, vi } from "vitest";
import { Card } from "./card.ts";
import type { I18n } from "../i18n.ts";

const i18n: I18n = {
  lang: "zh-CN",
  t: (key, values = {}) => key === "card.aria" ? `${values.name} input card` : key,
  status: (status) => status,
  error: (code, fallback) => code ?? fallback ?? "",
};

describe("Card", () => {
  afterEach(() => {
    vi.useRealTimers();
  });

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

  it("uses the done label in editor mode", () => {
    const card = makeCard();

    card.setText("draft");
    card.setSyncMode("editor");
    card.setStatus("focused");

    expect(card.element.querySelector(".btn--primary")?.textContent).toBe("card.done");
  });

  it("starts voice mode on long press from compact input", () => {
    vi.useFakeTimers();
    const onVoiceHoldStart = vi.fn();
    const card = makeCard({ onVoiceHoldStart });
    card.setStatus("focused");

    const pressLayer = card.element.querySelector<HTMLElement>(".card__voicepress")!;
    const event = new Event("pointerdown", { bubbles: true }) as PointerEvent;
    Object.defineProperty(event, "button", { value: 0 });
    Object.defineProperty(event, "pointerId", { value: 1 });
    pressLayer.dispatchEvent(event);
    vi.advanceTimersByTime(451);

    expect(onVoiceHoldStart).toHaveBeenCalledWith("codex");
  });
});

function makeCard(overrides: Partial<ConstructorParameters<typeof Card>[4]> = {}): Card {
  return new Card("codex", "Codex", null, i18n, {
    onFocusTextarea: vi.fn(),
    onInput: vi.fn(),
    onSend: vi.fn(),
    onClear: vi.fn(),
    onRefocus: vi.fn(),
    onVoiceHoldStart: vi.fn(),
    onVoiceHoldEnd: vi.fn(),
    ...overrides,
  });
}

function mockScrollHeight(textarea: HTMLTextAreaElement, value: number): void {
  Object.defineProperty(textarea, "scrollHeight", {
    configurable: true,
    value,
  });
}
