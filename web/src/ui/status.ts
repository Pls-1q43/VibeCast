// 卡片同步状态（PRD 5.5）。状态必须用文字表示，不能只靠颜色。

export type SyncStatus =
  | "disconnected" // 未连接
  | "idle" // 待选择
  | "focusing" // 正在聚焦
  | "focused" // 已聚焦
  | "syncing" // 正在同步
  | "synced" // 已同步
  | "composing" // 输入法编辑中
  | "target_lost" // 目标失焦
  | "app_not_running" // Mac 应用未运行
  | "sync_failed" // 同步失败
  | "reconnecting" // 等待重连
  | "sending" // 正在发送
  | "sent" // 已发送
  | "send_failed"; // 发送失败

export const STATUS_LABEL: Record<SyncStatus, string> = {
  disconnected: "未连接",
  idle: "待选择",
  focusing: "正在聚焦",
  focused: "已聚焦",
  syncing: "正在同步",
  synced: "已同步",
  composing: "输入法编辑中",
  target_lost: "目标失焦",
  app_not_running: "Mac 应用未运行",
  sync_failed: "同步失败",
  reconnecting: "等待重连",
  sending: "正在发送",
  sent: "已发送",
  send_failed: "发送失败",
};

/** 状态对应的语义色（仅作辅助，文字始终在场）。 */
export const STATUS_TONE: Record<SyncStatus, "neutral" | "ok" | "warn" | "error" | "active"> = {
  disconnected: "neutral",
  idle: "neutral",
  focusing: "active",
  focused: "ok",
  syncing: "active",
  synced: "ok",
  composing: "active",
  target_lost: "warn",
  app_not_running: "warn",
  sync_failed: "error",
  reconnecting: "warn",
  sending: "active",
  sent: "ok",
  send_failed: "error",
};
