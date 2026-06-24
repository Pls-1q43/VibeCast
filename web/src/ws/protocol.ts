// VibeCast 同步协议 v1 — 与 shared/protocol.md 对齐。
// 前后端唯一对齐来源，修改前请同步更新 shared/protocol.md 与 Swift 端。

export const PROTOCOL_VERSION = 1;

export type TargetId = string;

export const PRESET_TARGET_IDS: TargetId[] = ["codex", "workbuddy", "notion", "obsidian", "codebuddycn", "codebuddy"];

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
  | "RATE_LIMITED"
  | "INACTIVE_SESSION";

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

export interface VoiceStartMessage {
  type: "voice_start";
  sessionId: string;
  targetId: TargetId;
  sampleRate: number;
  channels: number;
  codec: "pcm_s16le";
  clientTimestamp?: number;
}

export interface VoiceChunkMessage {
  type: "voice_chunk";
  sessionId: string;
  targetId: TargetId;
  sequence: number;
  audioBase64: string;
  clientTimestamp?: number;
}

export interface VoiceStopMessage {
  type: "voice_stop";
  sessionId: string;
  targetId: TargetId;
  reason?: "release" | "cancel" | "error" | "disconnect";
  clientTimestamp?: number;
}

export type VoiceInputProvider =
  | "shandianshuo"
  | "typeless"
  | "wechat_input"
  | "doubao_input"
  | "macos_dictation"
  | "custom";

export type VoiceTriggerMode = "toggle" | "hold";

export interface KeyShortcut {
  modifiers: string[];
  key: string;
}

export interface VoiceRelaySettings {
  enabled: boolean;
  provider: VoiceInputProvider;
  triggerMode: VoiceTriggerMode;
  shortcut: KeyShortcut;
  managedOriginalAudioDevice?: string | null;
  managedVirtualAudioDevice?: string | null;
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
  | VoiceStartMessage
  | VoiceChunkMessage
  | VoiceStopMessage
  | PingMessage
  | GetConfigMessage
  | SetConfigMessage
  | TestTargetMessage
  | ListRunningAppsMessage
  | GetStatusMessage
  | GetNetworkSettingsMessage
  | SetNetworkSettingsMessage
  | CheckPortMessage
  | GetVoiceEnvironmentMessage
  | GetVoiceSettingsMessage
  | SetVoiceSettingsMessage
  | InstallVirtualMicMessage
  | BindShanDianShuoMicMessage
  | BindTypelessMicMessage
  | OpenAccessibilitySettingsMessage
  | CreateTargetMessage
  | DeleteTargetMessage
  | SetTargetEnabledMessage;

// ---- Mac → 手机 ----

export interface TargetInfo {
  id: TargetId;
  displayName: string;
  iconDataUrl?: string | null;
  available: boolean;
  clearAfterSend: boolean;
  allowEmpty: boolean;
  syncMode: "mirror" | "editor";
}

export interface HelloAckMessage {
  type: "hello_ack";
  serverName: string;
  protocolVersion: number;
  targets: TargetInfo[];
  accessibilityGranted: boolean;
  voiceRelayEnabled: boolean;
}

export interface TargetsMessage {
  type: "targets";
  targets: TargetInfo[];
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
  message?: string | null;
  verified?: boolean | null;
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

export interface VoiceStateMessage {
  type: "voice_state";
  sessionId: string;
  targetId: TargetId;
  state: "starting" | "started" | "stopped" | "error";
  message?: string | null;
  receivedBytes?: number | null;
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
  iconDataUrl?: string | null;
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
  writeMode?: "auto" | "axvalue" | "clipboard_replace" | "clipboard_insert" | "clipboard_paste";
  syncMode?: "mirror" | "editor";
  voiceShortcut?: { modifiers: string[]; key: string };
}

export interface ConfigTarget {
  id: TargetId;
  kind: "preset" | "custom";
  enabled: boolean;
  profile: TargetProfile;
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
export interface GetStatusMessage {
  type: "get_status";
}
export interface GetNetworkSettingsMessage {
  type: "get_network_settings";
}
export type NetworkBindMode = "address" | "all";
export interface NetworkSettings {
  bindMode: NetworkBindMode;
  bindAddress?: string | null;
  port: number;
}
export interface SetNetworkSettingsMessage {
  type: "set_network_settings";
  settings: NetworkSettings;
}
export interface CheckPortMessage {
  type: "check_port";
  bindMode: NetworkBindMode;
  bindAddress?: string | null;
  port: number;
}
export interface GetVoiceEnvironmentMessage {
  type: "get_voice_environment";
}
export interface GetVoiceSettingsMessage {
  type: "get_voice_settings";
}
export interface SetVoiceSettingsMessage {
  type: "set_voice_settings";
  settings: VoiceRelaySettings;
}
export interface InstallVirtualMicMessage {
  type: "install_virtual_mic";
}
export interface BindShanDianShuoMicMessage {
  type: "bind_shandianshuo_mic";
}
export interface BindTypelessMicMessage {
  type: "bind_typeless_mic";
}
export interface OpenAccessibilitySettingsMessage {
  type: "open_accessibility_settings";
}
export interface CreateTargetMessage {
  type: "create_target";
  displayName: string;
  bundleId?: string | null;
  iconDataUrl?: string | null;
}
export interface DeleteTargetMessage {
  type: "delete_target";
  targetId: TargetId;
}
export interface SetTargetEnabledMessage {
  type: "set_target_enabled";
  targetId: TargetId;
  enabled: boolean;
}

export interface ConfigMessage {
  type: "config";
  targets: ConfigTarget[];
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
  iconDataUrl?: string | null;
}
export interface RunningAppsMessage {
  type: "running_apps";
  apps: RunningApp[];
}
export interface ServerStatusMessage {
  type: "server_status";
  serverName: string;
  accessibilityGranted: boolean;
}
export interface NetworkInterfaceInfo {
  id: string;
  name: string;
  address: string;
  isPreferred: boolean;
}
export type PortAvailabilityStatus = "available" | "unavailable" | "invalid";
export interface PortCheckResult {
  bindMode: NetworkBindMode;
  bindAddress?: string | null;
  port: number;
  status: PortAvailabilityStatus;
  message?: string | null;
}
export interface NetworkSettingsMessage {
  type: "network_settings";
  settings: NetworkSettings;
  interfaces: NetworkInterfaceInfo[];
  portStatus: PortCheckResult;
  accessUrl?: string | null;
}
export interface NetworkInterfacesMessage {
  type: "network_interfaces";
  interfaces: NetworkInterfaceInfo[];
}
export interface PortCheckMessage {
  type: "port_check";
  result: PortCheckResult;
}
export interface VoiceEnvironmentMessage {
  type: "voice_environment";
  enabled: boolean;
  provider: VoiceInputProvider;
  triggerMode: VoiceTriggerMode;
  shortcut: KeyShortcut;
  installed: boolean;
  deviceName?: string | null;
  dedicatedInstalled: boolean;
  usingCompatibilityDevice: boolean;
  defaultInputMatches: boolean;
  canAutoSwitch: boolean;
  message?: string | null;
  shandianshuoInstalled?: boolean | null;
  shandianshuoAudioDevice?: string | null;
  shandianshuoMatchesVirtualMic?: boolean | null;
  shandianshuoMessage?: string | null;
  typelessInstalled?: boolean | null;
  typelessAudioDevice?: string | null;
  typelessMatchesVirtualMic?: boolean | null;
  typelessMessage?: string | null;
  doubaoInstalled?: boolean | null;
  doubaoAudioDevice?: string | null;
  doubaoMatchesVirtualMic?: boolean | null;
  doubaoMessage?: string | null;
}

export interface VoiceSettingsMessage {
  type: "voice_settings";
  settings: VoiceRelaySettings;
}

export type ServerMessage =
  | HelloAckMessage
  | TargetsMessage
  | TargetStatusMessage
  | TextAckMessage
  | SendResultMessage
  | VoiceStateMessage
  | ErrorMessage
  | PongMessage
  | ConfigMessage
  | TestResultMessage
  | RunningAppsMessage
  | ServerStatusMessage
  | NetworkSettingsMessage
  | NetworkInterfacesMessage
  | PortCheckMessage
  | VoiceEnvironmentMessage
  | VoiceSettingsMessage;

export function isServerMessage(v: unknown): v is ServerMessage {
  return typeof v === "object" && v !== null && typeof (v as { type?: unknown }).type === "string";
}
