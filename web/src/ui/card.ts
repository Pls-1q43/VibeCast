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
}

export class Card {
  readonly targetId: TargetId;
  readonly textarea: HTMLTextAreaElement;
  private root: HTMLElement;
  private statusEl: HTMLElement;
  private sendBtn: HTMLButtonElement;
  private clearBtn: HTMLButtonElement;
  private refocusBtn: HTMLButtonElement;
  private status: SyncStatus = "disconnected";
  private allowEmpty = false;

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
    this.textarea = document.createElement("textarea");
    this.textarea.className = "card__textarea";
    this.textarea.rows = 4;
    this.textarea.setAttribute("aria-labelledby", labelId);
    this.textarea.placeholder = i18n.t("card.placeholder");
    this.textarea.autocapitalize = "off";
    this.textarea.spellcheck = false;
    this.textarea.addEventListener("focus", () => cb.onFocusTextarea(targetId));
    this.textarea.addEventListener("input", () => cb.onInput(targetId));

    // 操作区
    const actions = el("div", "card__actions");
    this.sendBtn = button(i18n.t("card.send"), "btn btn--primary", () => cb.onSend(targetId));
    this.clearBtn = button(i18n.t("card.clear"), "btn btn--ghost", () => cb.onClear(targetId));
    this.refocusBtn = button(i18n.t("card.refocus"), "btn btn--ghost", () => cb.onRefocus(targetId));
    actions.append(this.sendBtn, this.clearBtn, this.refocusBtn);

    this.root.append(header, this.textarea, actions);
    this.setStatus("disconnected");
  }

  get element(): HTMLElement {
    return this.root;
  }

  setSelected(selected: boolean): void {
    this.root.classList.toggle("card--selected", selected);
  }

  setText(text: string, selStart?: number, selEnd?: number): void {
    if (this.textarea.value !== text) this.textarea.value = text;
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
          : this.i18n.t("card.send");

    this.clearBtn.disabled = locked || !hasText;
    // 重新聚焦：仅在失焦/失败相关状态下提供
    const showRefocus = ["target_lost", "app_not_running", "sync_failed", "send_failed"].includes(this.status);
    this.refocusBtn.style.display = showRefocus ? "" : "none";
  }

  /** 文本变化后需重算按钮（空↔非空）。 */
  refreshButtons(): void {
    this.updateButtons();
  }

  /** 锁定发送按钮，防重复点击（PRD 5.6）。 */
  lockSend(): void {
    this.sendBtn.disabled = true;
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
