// 卡片同步状态（PRD 5.5）。状态必须用文字表示，不能只靠颜色。

import type { SyncStatus } from "../i18n.ts";

export type { SyncStatus };

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
