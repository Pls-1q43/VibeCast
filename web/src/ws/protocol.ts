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
  | PingMessage
  | GetConfigMessage
  | SetConfigMessage
  | TestTargetMessage
  | ListRunningAppsMessage;

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

// ---- 配置相关 ----

export interface TargetProfile {
  displayName: string;
  bundleId: string;
  activationMode: "bundle_id";
  launchIfNotRunning: boolean;
  focusMode: "shortcut" | "accessibility" | "preserve_last_focus" | "custom";
  focusShortcut: { modifiers: string[]; key: string } | null;
  focusWaitMs: number;
  sendMode: "key" | "custom_shortcut" | "accessibility_button" | "none";
  sendShortcut: { modifiers: string[]; key: string } | null;
  sendButtonTitleContains: string | null;
  clearAfterSend: boolean;
  allowEmpty: boolean;
  keepForeground: boolean;
  maxTextLength: number;
  allowSelectAllReplace: boolean;
  writeMode?: "auto" | "axvalue" | "clipboard_paste";
}

export interface GetConfigMessage {
  type: "get_config";
}
export interface SetConfigMessage {
  type: "set_config";
  targetId: TargetId;
  profile: TargetProfile;
}
export interface TestTargetMessage {
  type: "test_target";
  targetId: TargetId;
}
export interface ListRunningAppsMessage {
  type: "list_running_apps";
}

export interface ConfigMessage {
  type: "config";
  profiles: Record<string, TargetProfile>;
}
export interface TestResultMessage {
  type: "test_result";
  targetId: TargetId;
  success: boolean;
  errorCode: ErrorCode | null;
  message: string | null;
}
export interface RunningApp {
  bundleId: string;
  name: string;
}
export interface RunningAppsMessage {
  type: "running_apps";
  apps: RunningApp[];
}

export type ServerMessage =
  | HelloAckMessage
  | TargetStatusMessage
  | TextAckMessage
  | SendResultMessage
  | ErrorMessage
  | PongMessage
  | ConfigMessage
  | TestResultMessage
  | RunningAppsMessage;

export function isServerMessage(v: unknown): v is ServerMessage {
  return typeof v === "object" && v !== null && typeof (v as { type?: unknown }).type === "string";
}
