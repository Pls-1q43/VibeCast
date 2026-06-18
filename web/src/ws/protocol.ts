// VibeCast 同步协议 v1 — 与 shared/protocol.md 对齐。
// 前后端唯一对齐来源，修改前请同步更新 shared/protocol.md 与 Swift 端。

export const PROTOCOL_VERSION = 1;

export type TargetId = "codex" | "workbuddy" | "notion" | "codebuddy";

export const TARGET_IDS: TargetId[] = ["codex", "workbuddy", "notion", "codebuddy"];

export type ErrorCode =
  | "UNPAIRED"
  | "BAD_TOKEN"
  | "BAD_MESSAGE"
  | "UNKNOWN_TARGET"
  | "APP_NOT_RUNNING"
  | "APP_LAUNCH_FAILED"
  | "TARGET_NOT_FOCUSED"
  | "NO_ACCESSIBILITY_PERMISSION"
  | "STALE_REVISION"
  | "WRITE_FAILED"
  | "SEND_FAILED"
  | "SEND_UNKNOWN"
  | "RATE_LIMITED";

export type TargetStatus =
  | "focusing"
  | "focused"
  | "app_not_running"
  | "not_focused"
  | "no_permission"
  | "error";

// ---- 手机 → Mac ----

export interface HelloMessage {
  type: "hello";
  protocolVersion: number;
  clientId: string;
  deviceName: string;
  pairingToken: string;
}

export interface SelectTargetMessage {
  type: "select_target";
  sessionId: string;
  targetId: TargetId;
}

export interface TextSnapshotMessage {
  type: "text_snapshot";
  sessionId: string;
  targetId: TargetId;
  revision: number;
  text: string;
  selectionStart: number;
  selectionEnd: number;
  isComposing: boolean;
  clientTimestamp?: number;
}

export interface SendMessage {
  type: "send";
  sessionId: string;
  targetId: TargetId;
  revision: number;
}

export interface ClearMessage {
  type: "clear";
  sessionId: string;
  targetId: TargetId;
  revision: number;
}

export interface PingMessage {
  type: "ping";
  t: number;
}

export type ClientMessage =
  | HelloMessage
  | SelectTargetMessage
  | TextSnapshotMessage
  | SendMessage
  | ClearMessage
  | PingMessage;

// ---- Mac → 手机 ----

export interface TargetInfo {
  id: TargetId;
  displayName: string;
  available: boolean;
}

export interface HelloAckMessage {
  type: "hello_ack";
  serverName: string;
  protocolVersion: number;
  targets: TargetInfo[];
  accessibilityGranted: boolean;
}

export interface TargetStatusMessage {
  type: "target_status";
  sessionId: string;
  targetId: TargetId;
  status: TargetStatus;
  errorCode: ErrorCode | null;
  message: string | null;
}

export interface TextAckMessage {
  type: "text_ack";
  sessionId: string;
  targetId: TargetId;
  revision: number;
  applied: boolean;
  errorCode: ErrorCode | null;
}

export interface SendResultMessage {
  type: "send_result";
  sessionId: string;
  targetId: TargetId;
  revision: number;
  success: boolean;
  errorCode?: ErrorCode;
  message?: string;
}

export interface ErrorMessage {
  type: "error";
  errorCode: ErrorCode;
  message: string;
}

export interface PongMessage {
  type: "pong";
  t: number;
}

export type ServerMessage =
  | HelloAckMessage
  | TargetStatusMessage
  | TextAckMessage
  | SendResultMessage
  | ErrorMessage
  | PongMessage;

export function isServerMessage(v: unknown): v is ServerMessage {
  return typeof v === "object" && v !== null && typeof (v as { type?: unknown }).type === "string";
}
