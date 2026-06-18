// VibeCast 手机端主编排：串联 DraftStore + IMEController + WSClient + Cards。
// PRD 4.2 / 4.3 / 5 / 6 / 11 / 12 / 16。

import { TARGET_IDS, type TargetId, type ServerMessage } from "./ws/protocol.ts";
import { WSClient, type ConnectionState } from "./ws/client.ts";
import { DraftStore, getClientId } from "./store/draftStore.ts";
import { IMEController } from "./ime/imeController.ts";
import { Card } from "./ui/card.ts";
import type { SyncStatus } from "./ui/status.ts";

const DISPLAY_NAMES: Record<TargetId, string> = {
  codex: "Codex",
  workbuddy: "WorkBuddy",
  notion: "Notion",
  codebuddy: "CodeBuddy",
};

export class App {
  private store = new DraftStore();
  private cards = new Map<TargetId, Card>();
  private imeControllers = new Map<TargetId, IMEController>();
  private ws: WSClient;
  private connState: ConnectionState = "disconnected";

  /** 当前活动目标（单一活动会话，PRD 12.2）。 */
  private activeTarget: TargetId | null = null;
  /** 每目标的会话 ID（切目标 = 新会话，PRD 4.3）。 */
  private sessions = new Map<TargetId, string>();
  /** 每目标最近一次 target_status 状态，用于判断是否已聚焦。 */
  private targetFocused = new Map<TargetId, boolean>();

  private connbar!: HTMLElement;
  private serverName = "Mac";

  constructor(private mount: HTMLElement) {
    this.ws = new WSClient({
      url: this.wsUrl(),
      clientId: getClientId(),
      deviceName: navigator.userAgent.includes("Android") ? "Android Phone" : "Phone",
      pairingToken: this.pairingToken(),
      onState: (s) => this.onConnState(s),
      onMessage: (m) => this.onServerMessage(m),
      onOpen: () => this.onWsOpen(),
    });
  }

  private wsUrl(): string {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    return `${proto}//${location.host}/ws`;
  }

  private pairingToken(): string {
    // MVP：从 URL 查询参数或 localStorage 读取配对令牌（二维码配对在二期）。
    const fromUrl = new URLSearchParams(location.search).get("token");
    if (fromUrl) {
      localStorage.setItem("vibecast.token.v1", fromUrl);
      return fromUrl;
    }
    return localStorage.getItem("vibecast.token.v1") ?? "";
  }

  start(): void {
    this.render();
    this.ws.connect();
  }

  private render(): void {
    this.mount.innerHTML = "";

    const hint = document.createElement("p");
    hint.className = "hint";
    hint.textContent = "点击某个应用的文本框后，在输入法中点击语音按钮开始说话。识别出的文字会实时镜像到 Mac 对应应用。";
    this.mount.append(hint);

    for (const id of TARGET_IDS) {
      const card = new Card(id, DISPLAY_NAMES[id], {
        onFocusTextarea: (t) => this.selectTarget(t),
        onInput: (t) => this.onCardInput(t),
        onSend: (t) => this.onSend(t),
        onClear: (t) => this.onClear(t),
        onRefocus: (t) => this.refocus(t),
      });
      this.cards.set(id, card);
      this.mount.append(card.element);

      // 恢复持久化草稿
      const d = this.store.get(id);
      card.setText(d.text);
      card.refreshButtons();

      // 绑定 IME 控制器
      const ime = new IMEController(card.textarea, {
        onSnapshot: (snap) => this.syncSnapshot(id, snap),
        onComposingChange: (composing) => {
          if (this.activeTarget === id && composing) card.setStatus("composing");
        },
      });
      this.imeControllers.set(id, ime);
    }

    this.connbar = document.createElement("div");
    this.connbar.className = "connbar";
    document.body.append(this.connbar);
    this.updateConnbar();
  }

  // ---- 目标选择（PRD 4.3）----

  private selectTarget(targetId: TargetId): void {
    if (this.activeTarget === targetId) return;
    this.activeTarget = targetId;
    for (const [id, card] of this.cards) card.setSelected(id === targetId);

    // 新建会话
    const sessionId = crypto.randomUUID();
    this.sessions.set(targetId, sessionId);
    this.targetFocused.set(targetId, false);

    const card = this.cards.get(targetId)!;
    card.setStatus(this.connState === "connected" ? "focusing" : "disconnected");

    if (this.connState === "connected") {
      this.ws.send({ type: "select_target", sessionId, targetId });
    }
  }

  private refocus(targetId: TargetId): void {
    const sessionId = this.sessions.get(targetId);
    if (sessionId && this.connState === "connected") {
      this.cards.get(targetId)?.setStatus("focusing");
      this.ws.send({ type: "select_target", sessionId, targetId });
    }
  }

  // ---- 输入与同步（PRD 6）----

  private onCardInput(targetId: TargetId): void {
    // 仅刷新按钮（空↔非空）；实际同步由 IMEController 节流后经 syncSnapshot 触发。
    this.cards.get(targetId)?.refreshButtons();
  }

  private syncSnapshot(
    targetId: TargetId,
    snap: { text: string; selectionStart: number; selectionEnd: number; isComposing: boolean },
  ): void {
    const card = this.cards.get(targetId);
    if (!card) return;
    const d = this.store.update(targetId, snap.text, snap.selectionStart, snap.selectionEnd);
    card.refreshButtons();

    if (this.connState !== "connected" || this.activeTarget !== targetId) {
      // 断线或非活动目标：保留草稿，不上报，不显示已同步（PRD 16.4）。
      return;
    }
    const sessionId = this.sessions.get(targetId)!;
    if (!snap.isComposing) card.setStatus("syncing");
    this.ws.send({
      type: "text_snapshot",
      sessionId,
      targetId,
      revision: d.revision,
      text: snap.text,
      selectionStart: snap.selectionStart,
      selectionEnd: snap.selectionEnd,
      isComposing: snap.isComposing,
      clientTimestamp: Date.now(),
    });
  }

  // ---- 发送（PRD 3.3 / 5.6 / 11.4）----

  private onSend(targetId: TargetId): void {
    const card = this.cards.get(targetId);
    if (!card || this.connState !== "connected") return;
    const ime = this.imeControllers.get(targetId);

    // 若仍在组合态，等组合结束再发（PRD 6.1）。
    if (ime?.composing) {
      window.setTimeout(() => this.onSend(targetId), 60);
      return;
    }

    card.lockSend();
    card.setStatus("sending");

    // 发送前立即同步最新完整快照（绕过节流，PRD 6.2）。
    ime?.flushNow();

    const d = this.store.get(targetId);
    const sessionId = this.sessions.get(targetId)!;
    this.ws.send({ type: "send", sessionId, targetId, revision: d.revision });
  }

  private onClear(targetId: TargetId): void {
    const card = this.cards.get(targetId);
    if (!card) return;
    if (!window.confirm("确认清空当前草稿？")) return;
    const d = this.store.clear(targetId);
    card.setText("");
    card.refreshButtons();
    if (this.connState === "connected" && this.activeTarget === targetId) {
      const sessionId = this.sessions.get(targetId)!;
      this.ws.send({ type: "clear", sessionId, targetId, revision: d.revision });
    }
  }

  // ---- 连接事件 ----

  private onWsOpen(): void {
    this.ws.sendHello();
  }

  private onConnState(state: ConnectionState): void {
    this.connState = state;
    this.updateConnbar();
    if (state === "disconnected") {
      // 断线：所有卡片标记未连接/等待重连，禁用发送（PRD 16.4）。
      for (const card of this.cards.values()) card.setStatus("reconnecting");
    }
  }

  private onServerMessage(msg: ServerMessage): void {
    switch (msg.type) {
      case "hello_ack": {
        this.serverName = msg.serverName;
        this.updateConnbar();
        // 重连后恢复活动目标 + 发送最新完整快照（PRD 16.4）。
        if (this.activeTarget) {
          this.refocus(this.activeTarget);
        } else {
          for (const card of this.cards.values()) card.setStatus("idle");
        }
        break;
      }
      case "target_status": {
        const card = this.cards.get(msg.targetId);
        if (!card) break;
        const focused = msg.status === "focused";
        this.targetFocused.set(msg.targetId, focused);
        card.setStatus(this.mapTargetStatus(msg.status));
        if (focused && this.activeTarget === msg.targetId) {
          // 聚焦成功后补发当前完整快照。
          this.imeControllers.get(msg.targetId)?.flushNow();
        }
        break;
      }
      case "text_ack": {
        const card = this.cards.get(msg.targetId);
        if (!card) break;
        if (msg.applied) {
          this.store.markAcked(msg.targetId, msg.revision);
          if (this.store.isSynced(msg.targetId)) card.setStatus("synced");
        } else if (msg.errorCode && msg.errorCode !== "STALE_REVISION") {
          card.setStatus("sync_failed");
        }
        break;
      }
      case "send_result": {
        const card = this.cards.get(msg.targetId);
        if (!card) break;
        if (msg.success) {
          card.setStatus("sent");
          // 是否清空草稿由 Mac 端 Profile 决定；M1 暂不本地清空，等 M7 接配置回传。
        } else {
          card.setStatus("send_failed");
        }
        card.refreshButtons();
        break;
      }
      case "error":
        // 握手/校验错误：连接条提示。
        this.connbar.title = `${msg.errorCode}: ${msg.message}`;
        break;
    }
  }

  private mapTargetStatus(s: string): SyncStatus {
    switch (s) {
      case "focusing":
        return "focusing";
      case "focused":
        return "focused";
      case "app_not_running":
        return "app_not_running";
      case "not_focused":
        return "target_lost";
      case "no_permission":
        return "sync_failed";
      default:
        return "sync_failed";
    }
  }

  private updateConnbar(): void {
    if (!this.connbar) return;
    const label =
      this.connState === "connected"
        ? `已连接 · ${this.serverName}`
        : this.connState === "connecting"
          ? "连接中…"
          : "未连接";
    this.connbar.dataset.state = this.connState;
    this.connbar.textContent = "";
    const left = document.createElement("span");
    left.textContent = label;
    const right = document.createElement("span");
    right.textContent = this.activeTarget ? `目标：${DISPLAY_NAMES[this.activeTarget]}` : "未选择目标";
    this.connbar.append(left, right);
  }
}
