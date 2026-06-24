// 单个目标应用卡片。PRD 5.1 / 5.2 / 5.5 / 5.6 / 5.7 / 19。

import { type TargetId } from "../ws/protocol.ts";
import type { I18n } from "../i18n.ts";
import { STATUS_TONE, type SyncStatus } from "./status.ts";
import { renderTargetIcon } from "./targetIcon.ts";

export interface CardCallbacks {
  onFocusTextarea: (targetId: TargetId) => void;
  onInput: (targetId: TargetId) => void;
  onSend: (targetId: TargetId) => void;
  onClear: (targetId: TargetId) => void;
  onRefocus: (targetId: TargetId) => void;
  onVoiceHoldStart: (targetId: TargetId) => void;
  onVoiceHoldEnd: (targetId: TargetId, reason: "release" | "cancel") => void;
}

export class Card {
  readonly targetId: TargetId;
  readonly textarea: HTMLTextAreaElement;
  private root: HTMLElement;
  private inputWrap: HTMLElement;
  private statusEl: HTMLElement;
  private sendBtn: HTMLButtonElement;
  private clearBtn: HTMLButtonElement;
  private refocusBtn: HTMLButtonElement;
  private status: SyncStatus = "disconnected";
  private allowEmpty = false;
  private syncMode: "mirror" | "editor" = "mirror";
  private voiceTimer: number | null = null;
  private voicePointerId: number | null = null;
  private voiceActive = false;
  private voiceRelayEnabled = false;
  private readonly placeholderText: string;

  constructor(targetId: TargetId, displayName: string, iconDataUrl: string | null | undefined, private i18n: I18n, cb: CardCallbacks) {
    this.targetId = targetId;

    this.root = el("section", "card");
    this.root.dataset.target = targetId;
    this.root.setAttribute("aria-label", i18n.t("card.aria", { name: displayName }));

    // 头部：图标 + 名称 + 状态
    const header = el("header", "card__header");
    const icon = renderTargetIcon(targetId, displayName, "card__icon", iconDataUrl);
    const titleWrap = el("div", "card__titlewrap");
    const title = el("h2", "card__title");
    title.textContent = displayName;
    const labelId = `label-${targetId}`;
    title.id = labelId;
    this.statusEl = el("div", "card__status");
    this.statusEl.setAttribute("role", "status");
    this.statusEl.setAttribute("aria-live", "polite");
    titleWrap.append(title, this.statusEl);
    header.append(icon, titleWrap);

    // 文本框（标准 textarea，PRD 5.2）
    this.inputWrap = el("div", "card__inputwrap");
    this.textarea = document.createElement("textarea");
    this.textarea.className = "card__textarea";
    this.textarea.rows = 4;
    this.textarea.setAttribute("aria-labelledby", labelId);
    this.placeholderText = i18n.t("card.placeholder");
    this.textarea.placeholder = this.placeholderText;
    this.textarea.autocapitalize = "off";
    this.textarea.spellcheck = false;
    this.textarea.addEventListener("focus", () => cb.onFocusTextarea(targetId));
    this.textarea.addEventListener("input", () => {
      this.syncTextareaHeight();
      cb.onInput(targetId);
    });
    this.textarea.addEventListener("contextmenu", (event) => {
      if (this.voiceActive || this.voiceTimer !== null) event.preventDefault();
    });
    const voicePressLayer = el("div", "card__voicepress");
    voicePressLayer.textContent = i18n.t("card.placeholder");
    voicePressLayer.addEventListener("pointerdown", (event) => this.onVoicePointerDown(event, cb));
    voicePressLayer.addEventListener("pointerup", () => this.finishVoiceHold(cb, "release"));
    voicePressLayer.addEventListener("pointercancel", () => this.finishVoiceHold(cb, "cancel"));
    voicePressLayer.addEventListener("pointerleave", () => this.finishVoiceHold(cb, "cancel"));
    voicePressLayer.addEventListener("contextmenu", (event) => event.preventDefault());
    this.inputWrap.append(this.textarea, voicePressLayer);

    // 操作区
    const actions = el("div", "card__actions");
    this.sendBtn = button(i18n.t("card.send"), "btn btn--primary", () => cb.onSend(targetId));
    this.clearBtn = button(i18n.t("card.clear"), "btn btn--ghost", () => cb.onClear(targetId));
    this.refocusBtn = button(i18n.t("card.refocus"), "btn btn--ghost", () => cb.onRefocus(targetId));
    actions.append(this.sendBtn, this.clearBtn, this.refocusBtn);

    this.root.append(header, this.inputWrap, actions);
    this.setStatus("disconnected");
    this.syncTextareaHeight();
  }

  get element(): HTMLElement {
    return this.root;
  }

  setSelected(selected: boolean): void {
    this.root.classList.toggle("card--selected", selected);
  }

  setText(text: string, selStart?: number, selEnd?: number): void {
    if (this.textarea.value !== text) this.textarea.value = text;
    this.syncTextareaHeight();
    if (selStart !== undefined && selEnd !== undefined && document.activeElement === this.textarea) {
      try {
        this.textarea.setSelectionRange(selStart, selEnd);
      } catch {
        /* 忽略越界 */
      }
    }
  }

  get text(): string {
    return this.textarea.value;
  }

  setAllowEmpty(allowEmpty: boolean): void {
    this.allowEmpty = allowEmpty;
    this.updateButtons();
  }

  setSyncMode(syncMode: "mirror" | "editor"): void {
    this.syncMode = syncMode;
    this.updateButtons();
  }

  setVoiceRelayEnabled(enabled: boolean): void {
    this.voiceRelayEnabled = enabled;
    this.inputWrap.classList.toggle("card__inputwrap--voice-enabled", enabled);
    if (!enabled) {
      this.clearVoiceTimer();
      this.voiceActive = false;
      this.root.classList.remove("card--voice-active");
    }
    this.syncTextareaHeight();
  }

  setStatus(status: SyncStatus, detail?: string | null): void {
    this.status = status;
    const label = this.i18n.status(status);
    this.statusEl.textContent = detail ? `${label}: ${detail}` : label;
    this.statusEl.dataset.tone = STATUS_TONE[status];
    this.updateButtons();
  }

  /** 根据连接 + 状态 + 文本，刷新按钮可用性（PRD 5.6）。 */
  private updateButtons(): void {
    const connected = this.status !== "disconnected" && this.status !== "reconnecting";
    const focused = ["focused", "syncing", "synced", "composing", "sending", "sent", "send_failed"].includes(this.status);
    const hasText = this.allowEmpty || this.text.trim().length > 0;
    const locked = this.status === "sending";

    // 发送：未连接/未聚焦/空文本/锁定时禁用
    this.sendBtn.disabled = !connected || !focused || !hasText || locked;
    this.sendBtn.textContent =
      this.status === "sending"
        ? this.i18n.t("card.sending")
        : this.status === "syncing"
          ? this.i18n.t("card.syncing")
          : this.syncMode === "editor"
            ? this.i18n.t("card.done")
            : this.i18n.t("card.send");

    this.clearBtn.disabled = locked || !hasText;
    // 重新聚焦：仅在失焦/失败相关状态下提供
    const showRefocus = ["target_lost", "app_not_running", "sync_failed", "send_failed"].includes(this.status);
    this.refocusBtn.style.display = showRefocus ? "" : "none";
  }

  /** 文本变化后需重算按钮（空↔非空）。 */
  refreshButtons(): void {
    this.syncTextareaHeight();
    this.updateButtons();
  }

  /** 锁定发送按钮，防重复点击（PRD 5.6）。 */
  lockSend(): void {
    this.sendBtn.disabled = true;
  }

  private syncTextareaHeight(): void {
    this.textarea.style.height = "auto";
    const compact = this.voiceRelayEnabled && this.text.trim().length === 0 && document.activeElement !== this.textarea;
    this.inputWrap.classList.toggle("card__inputwrap--compact", compact);
    this.textarea.placeholder = compact ? "" : this.placeholderText;
    const minHeight = compact ? 46 : this.textarea.scrollHeight;
    this.textarea.style.height = `${minHeight}px`;
  }

  private onVoicePointerDown(event: PointerEvent, cb: CardCallbacks): void {
    if (!this.voiceRelayEnabled) return;
    if (event.button !== 0 || this.status === "disconnected" || this.status === "reconnecting") return;
    event.preventDefault();
    this.clearVoiceTimer();
    this.voicePointerId = event.pointerId;
    const target = event.currentTarget as HTMLElement | null;
    target?.setPointerCapture?.(event.pointerId);
    this.voiceTimer = window.setTimeout(() => {
      this.voiceTimer = null;
      this.voiceActive = true;
      this.root.classList.add("card--voice-active");
      this.textarea.blur();
      cb.onVoiceHoldStart(this.targetId);
    }, 450);
  }

  private finishVoiceHold(cb: CardCallbacks, reason: "release" | "cancel"): void {
    const wasPendingTextTap = this.voiceTimer !== null && !this.voiceActive && reason === "release";
    this.clearVoiceTimer();
    if (this.voicePointerId !== null) {
      try {
        this.root.querySelector<HTMLElement>(".card__voicepress")?.releasePointerCapture?.(this.voicePointerId);
      } catch {
        /* pointer capture may already be gone */
      }
      this.voicePointerId = null;
    }
    if (wasPendingTextTap) {
      this.textarea.focus();
      this.syncTextareaHeight();
      return;
    }
    if (!this.voiceActive) return;
    this.voiceActive = false;
    this.root.classList.remove("card--voice-active");
    cb.onVoiceHoldEnd(this.targetId, reason);
  }

  private clearVoiceTimer(): void {
    if (this.voiceTimer !== null) {
      clearTimeout(this.voiceTimer);
      this.voiceTimer = null;
    }
  }
}

function el(tag: string, className: string): HTMLElement {
  const e = document.createElement(tag);
  e.className = className;
  return e;
}

function button(text: string, className: string, onClick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.className = className;
  b.textContent = text;
  b.addEventListener("click", onClick);
  return b;
}
