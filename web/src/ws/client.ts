// WebSocket 客户端：握手、重连、心跳、消息分发。PRD 11 / 16.4 / 6.6。
// 设计要点：
//   - 连接失败/断开时降级为「未连接」，UI 仍可编辑草稿（M1 可脱离 Mac 独立运行）。
//   - 重连后由上层重新 hello + select_target + 发送最新完整快照，不重放历史。
//   - 只保留最新待发送文本快照，旧快照不覆盖新快照（在发送层去重由 revision 保证）。

import {
  PROTOCOL_VERSION,
  isServerMessage,
  type ClientMessage,
  type ServerMessage,
} from "./protocol.ts";

export type ConnectionState = "disconnected" | "connecting" | "connected";

export interface WSClientOptions {
  url: string;
  clientId: string;
  deviceName: string;
  pairingToken: string;
  onState: (state: ConnectionState) => void;
  onMessage: (msg: ServerMessage) => void;
  /** 连接建立（WebSocket open）后回调，上层在此发 hello。 */
  onOpen: () => void;
}

const PING_INTERVAL_MS = 15_000;
const RECONNECT_BASE_MS = 500;
const RECONNECT_MAX_MS = 8_000;

export class WSClient {
  private opts: WSClientOptions;
  private ws: WebSocket | null = null;
  private state: ConnectionState = "disconnected";
  private reconnectAttempt = 0;
  private reconnectTimer: number | null = null;
  private pingTimer: number | null = null;
  private manuallyClosed = false;

  constructor(opts: WSClientOptions) {
    this.opts = opts;
  }

  get connectionState(): ConnectionState {
    return this.state;
  }

  private setState(s: ConnectionState): void {
    if (this.state !== s) {
      this.state = s;
      this.opts.onState(s);
    }
  }

  connect(): void {
    this.manuallyClosed = false;
    this.open();
  }

  private open(): void {
    this.setState("connecting");
    try {
      this.ws = new WebSocket(this.opts.url);
    } catch {
      this.scheduleReconnect();
      return;
    }

    this.ws.onopen = () => {
      this.reconnectAttempt = 0;
      this.setState("connected");
      this.startPing();
      this.opts.onOpen();
    };

    this.ws.onmessage = (ev) => {
      let parsed: unknown;
      try {
        parsed = JSON.parse(typeof ev.data === "string" ? ev.data : "");
      } catch {
        return;
      }
      if (isServerMessage(parsed)) {
        if (parsed.type === "pong") return; // 心跳应答无需上抛。
        this.opts.onMessage(parsed);
      }
    };

    this.ws.onclose = () => {
      this.stopPing();
      this.ws = null;
      this.setState("disconnected");
      if (!this.manuallyClosed) this.scheduleReconnect();
    };

    this.ws.onerror = () => {
      // 错误后 onclose 会触发重连，这里不重复处理。
      this.ws?.close();
    };
  }

  /** 上层在 onOpen 中调用，发送握手。 */
  sendHello(): void {
    this.send({
      type: "hello",
      protocolVersion: PROTOCOL_VERSION,
      clientId: this.opts.clientId,
      deviceName: this.opts.deviceName,
      pairingToken: this.opts.pairingToken,
    });
  }

  send(msg: ClientMessage): boolean {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(msg));
      return true;
    }
    return false;
  }

  private startPing(): void {
    this.stopPing();
    this.pingTimer = window.setInterval(() => {
      this.send({ type: "ping", t: Date.now() });
    }, PING_INTERVAL_MS);
  }

  private stopPing(): void {
    if (this.pingTimer !== null) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer !== null) return;
    const delay = Math.min(
      RECONNECT_BASE_MS * 2 ** this.reconnectAttempt,
      RECONNECT_MAX_MS,
    );
    this.reconnectAttempt += 1;
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = null;
      this.open();
    }, delay);
  }

  close(): void {
    this.manuallyClosed = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.stopPing();
    this.ws?.close();
    this.ws = null;
    this.setState("disconnected");
  }
}
