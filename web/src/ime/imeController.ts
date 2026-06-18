// 组合输入事件处理 + 同步节流。PRD 6。
// 绑定到单个 textarea，监听输入法事件，按策略产出「需同步快照」回调。
//
// 节流策略（PRD 6.2）：
//   - 普通输入：120ms 防抖（80–150ms 区间取中）
//   - 组合输入期间：250ms 节流（200–300ms 区间取中）
//   - compositionend 后：立即同步
//   - flushNow()（点击发送/清空前）：立即同步，绕过防抖
// 只保留最新待发送快照；旧快照不覆盖新快照。

export interface Snapshot {
  text: string;
  selectionStart: number;
  selectionEnd: number;
  isComposing: boolean;
}

export interface IMEControllerOptions {
  /** 防抖：普通输入事件。默认 120ms。 */
  debounceMs?: number;
  /** 节流：组合输入期间。默认 250ms。 */
  composingThrottleMs?: number;
  /** 产出一个待同步快照（已节流/防抖后）。 */
  onSnapshot: (snap: Snapshot) => void;
  /** 组合状态变化通知 UI（用于显示「输入法编辑中」）。 */
  onComposingChange?: (isComposing: boolean) => void;
}

export class IMEController {
  private el: HTMLTextAreaElement;
  private opts: Required<Omit<IMEControllerOptions, "onComposingChange">> &
    Pick<IMEControllerOptions, "onComposingChange">;
  private isComposing = false;
  private debounceTimer: number | null = null;
  private throttleTimer: number | null = null;
  private boundHandlers: Array<[EventTarget, string, EventListener]> = [];

  constructor(el: HTMLTextAreaElement, options: IMEControllerOptions) {
    this.el = el;
    this.opts = {
      debounceMs: options.debounceMs ?? 120,
      composingThrottleMs: options.composingThrottleMs ?? 250,
      onSnapshot: options.onSnapshot,
      onComposingChange: options.onComposingChange,
    };
    this.attach();
  }

  private current(): Snapshot {
    return {
      text: this.el.value,
      selectionStart: this.el.selectionStart ?? this.el.value.length,
      selectionEnd: this.el.selectionEnd ?? this.el.value.length,
      isComposing: this.isComposing,
    };
  }

  private clearTimers(): void {
    if (this.debounceTimer !== null) {
      clearTimeout(this.debounceTimer);
      this.debounceTimer = null;
    }
    if (this.throttleTimer !== null) {
      clearTimeout(this.throttleTimer);
      this.throttleTimer = null;
    }
  }

  /** 立即同步当前快照，绕过所有节流。发送/清空前调用。 */
  flushNow(): void {
    this.clearTimers();
    this.opts.onSnapshot(this.current());
  }

  private scheduleDebounced(): void {
    if (this.debounceTimer !== null) clearTimeout(this.debounceTimer);
    this.debounceTimer = window.setTimeout(() => {
      this.debounceTimer = null;
      this.opts.onSnapshot(this.current());
    }, this.opts.debounceMs);
  }

  private scheduleThrottled(): void {
    // 节流：已有定时器则跳过，保证组合期间最多每 throttleMs 发一次。
    if (this.throttleTimer !== null) return;
    this.throttleTimer = window.setTimeout(() => {
      this.throttleTimer = null;
      // 组合期间允许发送预览快照（isComposing:true）。
      this.opts.onSnapshot(this.current());
    }, this.opts.composingThrottleMs);
  }

  private attach(): void {
    const on = (type: string, fn: EventListener) => {
      this.el.addEventListener(type, fn);
      this.boundHandlers.push([this.el, type, fn]);
    };
    const onDoc = (type: string, fn: EventListener) => {
      document.addEventListener(type, fn);
      this.boundHandlers.push([document, type, fn]);
    };

    on("compositionstart", () => {
      this.isComposing = true;
      this.opts.onComposingChange?.(true);
    });

    on("compositionupdate", () => {
      if (this.isComposing) this.scheduleThrottled();
    });

    on("compositionend", () => {
      this.isComposing = false;
      this.opts.onComposingChange?.(false);
      // 组合结束：立即同步最终文本快照（PRD 6.1）。
      this.flushNow();
    });

    on("input", () => {
      if (this.isComposing) {
        // 组合中的 input 由 compositionupdate 节流路径处理。
        this.scheduleThrottled();
      } else {
        this.scheduleDebounced();
      }
    });

    // selectionchange 只在 document 上触发；仅当本 textarea 聚焦且非组合态时处理。
    onDoc("selectionchange", () => {
      if (!this.isComposing && document.activeElement === this.el) {
        this.scheduleDebounced();
      }
    });
  }

  get composing(): boolean {
    return this.isComposing;
  }

  destroy(): void {
    this.clearTimers();
    for (const [target, type, fn] of this.boundHandlers) {
      target.removeEventListener(type, fn);
    }
    this.boundHandlers = [];
  }
}
