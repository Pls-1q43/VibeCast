// VibeCast 手机端主编排：串联 DraftStore + IMEController + WSClient + Cards。
// PRD 4.2 / 4.3 / 5 / 6 / 11 / 12 / 16。

import { type TargetId, type ServerMessage, type TargetInfo } from "./ws/protocol.ts";
import { WSClient, type ConnectionState } from "./ws/client.ts";
import { DraftStore, getClientId, uuid } from "./store/draftStore.ts";
import { IMEController } from "./ime/imeController.ts";
import { Card } from "./ui/card.ts";
import type { SyncStatus } from "./ui/status.ts";
import { LANGUAGES, createI18n, setLang, type I18n, type Lang } from "./i18n.ts";
import { applyTheme, readTheme, writeTheme, type AppTheme } from "./ui/theme.ts";
import { VoiceRecorder, type VoiceRecorderChunk } from "./voice/voiceRecorder.ts";

interface ActiveVoiceSession {
  targetId: TargetId;
  sessionId: string;
  recorder: VoiceRecorder;
  ready: boolean;
  startSent: boolean;
  pendingChunks: VoiceRecorderChunk[];
}

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
  private targetOptions = new Map<TargetId, { clearAfterSend: boolean; allowEmpty: boolean; syncMode: "mirror" | "editor" }>();
  private targetNames = new Map<TargetId, string>();
  private pendingSends = new Map<TargetId, { sessionId: string; revision: number }>();
  private activeVoice: ActiveVoiceSession | null = null;
  private voiceRelayEnabled = false;

  private connbar!: HTMLElement;
  private cardList!: HTMLElement;
  private emptyState!: HTMLElement;
  private serverName = "Mac";
  private i18n: I18n = createI18n();
  private theme: AppTheme = readTheme();

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
    applyTheme(this.theme);
    this.render();
    this.ws.connect();
  }

  private render(): void {
    document.title = this.i18n.t("app.title");
    this.mount.innerHTML = "";

    const brand = document.createElement("header");
    brand.className = "brandbar";
    const logo = document.createElement("img");
    logo.src = "./favicon.svg";
    logo.alt = "";
    logo.setAttribute("aria-hidden", "true");
    const name = document.createElement("strong");
    name.textContent = "VibeCast";
    const tools = document.createElement("div");
    tools.className = "brandbar__tools";
    tools.append(this.renderThemeSwitch(), this.renderLanguagePicker());
    brand.append(logo, name, tools);
    this.mount.append(brand);

    const hint = document.createElement("p");
    hint.className = "hint";
    hint.textContent = this.i18n.t("app.hint");
    this.mount.append(hint);

    this.emptyState = document.createElement("section");
    this.emptyState.className = "empty-state";
    this.emptyState.textContent = this.i18n.t("app.empty");
    this.mount.append(this.emptyState);

    this.cardList = document.createElement("div");
    this.cardList.className = "card-list";
    this.mount.append(this.cardList);

    this.connbar = document.createElement("div");
    this.connbar.className = "connbar";
    document.body.append(this.connbar);
    this.updateConnbar();
  }

  private renderLanguagePicker(): HTMLLabelElement {
    const wrap = document.createElement("label");
    wrap.className = "language-picker";
    const span = document.createElement("span");
    span.textContent = this.i18n.t("app.language");
    const select = document.createElement("select");
    for (const lang of LANGUAGES) {
      const option = document.createElement("option");
      option.value = lang.code;
      option.textContent = lang.label;
      option.selected = lang.code === this.i18n.lang;
      select.append(option);
    }
    select.addEventListener("change", () => {
      setLang(select.value as Lang);
      location.reload();
    });
    wrap.append(span, select);
    return wrap;
  }

  private renderThemeSwitch(): HTMLElement {
    const wrap = document.createElement("div");
    wrap.className = "theme-switch";
    wrap.setAttribute("role", "group");
    wrap.setAttribute("aria-label", this.i18n.t("app.theme"));

    const buttons: HTMLButtonElement[] = [];
    const update = () => {
      for (const button of buttons) {
        const active = button.dataset.themeValue === this.theme;
        button.classList.toggle("is-active", active);
        button.setAttribute("aria-pressed", String(active));
      }
    };

    const addOption = (theme: AppTheme, label: string) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "theme-switch__option";
      button.dataset.themeValue = theme;
      button.textContent = label;
      button.addEventListener("click", () => {
        this.theme = theme;
        writeTheme(theme);
        applyTheme(theme);
        update();
      });
      buttons.push(button);
      wrap.append(button);
    };

    addOption("auto", this.i18n.t("app.themeAuto"));
    addOption("eink", this.i18n.t("app.themeEink"));
    update();
    return wrap;
  }

  private reconcileTargets(targets: TargetInfo[]): void {
    const nextIds = new Set(targets.filter((t) => t.available).map((t) => t.id));

    for (const [id, ime] of this.imeControllers) {
      if (!nextIds.has(id)) {
        ime.destroy();
        this.imeControllers.delete(id);
        this.cards.get(id)?.element.remove();
        this.cards.delete(id);
        this.targetOptions.delete(id);
        this.targetNames.delete(id);
        this.targetFocused.delete(id);
        this.pendingSends.delete(id);
        if (this.activeTarget === id) this.activeTarget = null;
      }
    }

    for (const target of targets) {
      if (!target.available) continue;
      this.targetNames.set(target.id, target.displayName);
      this.targetOptions.set(target.id, {
        clearAfterSend: target.clearAfterSend,
        allowEmpty: target.allowEmpty,
        syncMode: target.syncMode,
      });
      if (!this.cards.has(target.id)) {
        this.addCard(target);
      } else {
        this.cards.get(target.id)?.setAllowEmpty(target.allowEmpty);
        this.cards.get(target.id)?.setSyncMode(target.syncMode);
        this.cards.get(target.id)?.setVoiceRelayEnabled(this.voiceRelayEnabled);
      }
    }

    this.emptyState.hidden = this.cards.size > 0;
    if (!this.activeTarget) {
      for (const card of this.cards.values()) card.setStatus(this.connState === "connected" ? "idle" : "disconnected");
    }
    this.updateConnbar();
  }

  private addCard(target: TargetInfo): void {
    const id = target.id;
    const card = new Card(id, target.displayName, target.iconDataUrl, this.i18n, {
      onFocusTextarea: (t) => this.selectTarget(t),
      onInput: (t) => this.onCardInput(t),
      onSend: (t) => this.onSend(t),
      onClear: (t) => this.onClear(t),
      onRefocus: (t) => this.refocus(t),
      onVoiceHoldStart: (t) => void this.onVoiceHoldStart(t),
      onVoiceHoldEnd: (t, reason) => this.onVoiceHoldEnd(t, reason),
    });
    this.cards.set(id, card);
    this.cardList.append(card.element);

    const d = this.store.get(id);
    card.setText(d.text, d.selectionStart, d.selectionEnd);
    card.setAllowEmpty(target.allowEmpty);
    card.setSyncMode(target.syncMode);
    card.setVoiceRelayEnabled(this.voiceRelayEnabled);
    card.refreshButtons();

    const ime = new IMEController(card.textarea, {
      onSnapshot: (snap) => this.syncSnapshot(id, snap),
      onComposingChange: (composing) => {
        if (this.activeTarget === id && composing) card.setStatus("composing");
      },
    });
    this.imeControllers.set(id, ime);
  }

  // ---- 目标选择（PRD 4.3）----

  private selectTarget(targetId: TargetId): void {
    if (this.activeTarget === targetId && this.sessions.has(targetId)) return;
    this.activeTarget = targetId;
    for (const [id, card] of this.cards) card.setSelected(id === targetId);

    // 新建会话
    const sessionId = uuid();
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
    if (this.store.isSynced(targetId)) {
      this.ws.send({ type: "send", sessionId, targetId, revision: d.revision });
    } else {
      this.pendingSends.set(targetId, { sessionId, revision: d.revision });
    }
  }

  private onClear(targetId: TargetId): void {
    const card = this.cards.get(targetId);
    if (!card) return;
    if (!window.confirm(this.i18n.t("app.clearConfirm"))) return;
    const d = this.store.clear(targetId);
    card.setText("");
    card.refreshButtons();
    if (this.connState === "connected") {
      if (this.activeTarget !== targetId || !this.sessions.get(targetId)) {
        this.selectTarget(targetId);
        card.setStatus("focusing");
        return;
      }
      const sessionId = this.sessions.get(targetId)!;
      this.ws.send({ type: "clear", sessionId, targetId, revision: d.revision });
      card.setStatus("syncing");
    }
  }

  // ---- 语音传递（实验）----

  private async onVoiceHoldStart(targetId: TargetId): Promise<void> {
    if (this.connState !== "connected" || this.activeVoice) return;
    const card = this.cards.get(targetId);
    if (!card) return;

    if (!this.voiceRelayEnabled) {
      card.setStatus("sync_failed", this.i18n.t("voice.disabled"));
      return;
    }

    if (!VoiceRecorder.isSupported()) {
      card.setStatus("sync_failed", this.i18n.t("voice.errorCaptureUnavailable", { details: VoiceRecorder.diagnostics() }));
      return;
    }

    const sessionId = uuid();
    this.activeTarget = targetId;
    this.sessions.set(targetId, sessionId);
    for (const [id, c] of this.cards) c.setSelected(id === targetId);
    card.setStatus("voice_starting");
    this.updateConnbar();

    const recorder = new VoiceRecorder({
      onChunk: (chunk) => this.onVoiceChunk(chunk),
      onError: (message) => this.failVoice(targetId, message),
    });
    this.activeVoice = { targetId, sessionId, recorder, ready: false, startSent: false, pendingChunks: [] };

    try {
      const sampleRate = await recorder.start();
      this.ws.send({
        type: "voice_start",
        sessionId,
        targetId,
        sampleRate,
        channels: 1,
        codec: "pcm_s16le",
        clientTimestamp: Date.now(),
      });
      if (this.activeVoice?.sessionId === sessionId) this.activeVoice.startSent = true;
    } catch (error) {
      const message = error instanceof Error && error.message ? error.message : this.i18n.t("voice.errorMicrophone");
      card.setStatus("sync_failed", message);
      const voice = this.activeVoice;
      voice?.recorder.stop();
      if (voice?.sessionId === sessionId) this.activeVoice = null;
    }
  }

  private onVoiceHoldEnd(targetId: TargetId, reason: "release" | "cancel"): void {
    if (this.activeVoice?.targetId !== targetId) return;
    this.stopVoice(reason);
  }

  private onVoiceChunk(chunk: VoiceRecorderChunk): void {
    const voice = this.activeVoice;
    if (!voice) return;
    if (!voice.ready) {
      voice.pendingChunks.push(chunk);
      if (voice.pendingChunks.length > 32) voice.pendingChunks.shift();
      return;
    }
    this.sendVoiceChunk(voice, chunk);
  }

  private sendVoiceChunk(voice: ActiveVoiceSession, chunk: VoiceRecorderChunk): void {
    this.ws.send({
      type: "voice_chunk",
      sessionId: voice.sessionId,
      targetId: voice.targetId,
      sequence: chunk.sequence,
      audioBase64: chunk.audioBase64,
      clientTimestamp: Date.now(),
    });
  }

  private stopVoice(reason: "release" | "cancel" | "error" | "disconnect"): void {
    const voice = this.activeVoice;
    if (!voice) return;
    voice.recorder.stop();
    if (voice.startSent) {
      this.ws.send({
        type: "voice_stop",
        sessionId: voice.sessionId,
        targetId: voice.targetId,
        reason,
        clientTimestamp: Date.now(),
      });
    }
    this.cards.get(voice.targetId)?.setStatus(reason === "release" ? "synced" : "focused");
    this.activeVoice = null;
  }

  private failVoice(targetId: TargetId, message: string): void {
    this.cards.get(targetId)?.setStatus("sync_failed", message);
    this.stopVoice("error");
  }

  // ---- 连接事件 ----

  private onWsOpen(): void {
    this.ws.sendHello();
  }

  private onConnState(state: ConnectionState): void {
    this.connState = state;
    this.updateConnbar();
    if (state === "disconnected") {
      this.stopVoice("disconnect");
      // 断线：所有卡片标记未连接/等待重连，禁用发送（PRD 16.4）。
      for (const card of this.cards.values()) card.setStatus("reconnecting");
    }
  }

  private onServerMessage(msg: ServerMessage): void {
    switch (msg.type) {
      case "hello_ack": {
        this.serverName = msg.serverName;
        this.voiceRelayEnabled = msg.voiceRelayEnabled;
        this.reconcileTargets(msg.targets);
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
        if (focused && this.activeTarget === msg.targetId && this.activeVoice?.targetId !== msg.targetId) {
          // 聚焦成功后补发当前完整快照。
          this.imeControllers.get(msg.targetId)?.flushNow();
        }
        break;
      }
      case "voice_state": {
        const card = this.cards.get(msg.targetId);
        if (!card) break;
        if (msg.state === "started" && this.activeVoice?.sessionId === msg.sessionId) {
          this.activeVoice.ready = true;
          card.setStatus("voice_recording");
          for (const chunk of this.activeVoice.pendingChunks.splice(0)) {
            this.sendVoiceChunk(this.activeVoice, chunk);
          }
        } else if (msg.state === "stopped") {
          card.setStatus("synced");
        } else if (msg.state === "error") {
          card.setStatus("sync_failed", msg.message ?? null);
          this.activeVoice?.recorder.stop();
          this.activeVoice = null;
        }
        break;
      }
      case "voice_settings": {
        this.voiceRelayEnabled = msg.settings.enabled;
        for (const card of this.cards.values()) card.setVoiceRelayEnabled(this.voiceRelayEnabled);
        this.updateConnbar();
        break;
      }
      case "text_ack": {
        const card = this.cards.get(msg.targetId);
        if (!card) break;
        if (msg.applied) {
          this.store.markAcked(msg.targetId, msg.revision);
          if (this.store.isSynced(msg.targetId)) card.setStatus("synced");
          const pending = this.pendingSends.get(msg.targetId);
          if (pending && msg.revision >= pending.revision) {
            this.pendingSends.delete(msg.targetId);
            card.setStatus("sending");
            this.ws.send({
              type: "send",
              sessionId: pending.sessionId,
              targetId: msg.targetId,
              revision: pending.revision,
            });
          }
        } else if (msg.errorCode && msg.errorCode !== "STALE_REVISION") {
          this.pendingSends.delete(msg.targetId);
          card.setStatus("sync_failed", this.i18n.error(msg.errorCode, msg.message));
        }
        break;
      }
      case "send_result": {
        const card = this.cards.get(msg.targetId);
        if (!card) break;
        if (msg.success) {
          card.setStatus("sent");
          if (this.targetOptions.get(msg.targetId)?.clearAfterSend) {
            this.store.clear(msg.targetId);
            card.setText("");
          }
        } else {
          card.setStatus("send_failed", this.i18n.error(msg.errorCode, msg.message));
        }
        card.refreshButtons();
        break;
      }
      case "error":
        // 握手/校验错误：连接条提示。
        this.connbar.title = `${msg.errorCode}: ${msg.message}`;
        this.connbar.dataset.state = "disconnected";
        this.connbar.textContent = this.i18n.error(msg.errorCode, msg.message);
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
        ? this.i18n.t("app.connected", { name: this.serverName })
        : this.connState === "connecting"
          ? this.i18n.t("app.connecting")
          : this.i18n.t("app.disconnected");
    this.connbar.dataset.state = this.connState;
    this.connbar.textContent = "";
    const left = document.createElement("span");
    left.textContent = label;
    const right = document.createElement("span");
    right.textContent = this.activeTarget
      ? this.i18n.t("app.target", { name: this.targetNames.get(this.activeTarget) ?? this.activeTarget })
      : this.i18n.t("app.noTarget");
    this.connbar.append(left, right);
  }
}
