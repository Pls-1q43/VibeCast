// 每目标独立草稿 + 每目标独立单调 revision，localStorage 持久化。
// PRD 5.4 / 12.1：切换目标不清空原草稿，刷新恢复未发送草稿，revision 单调递增。

import { type TargetId } from "../ws/protocol.ts";

export interface Draft {
  text: string;
  /** 已写入本地的版本号；每次本地文本变更自增。 */
  revision: number;
  /** 最近一次成功被 Mac 应用 (text_ack applied) 的版本号；用于判断「已同步」。 */
  ackedRevision: number;
  selectionStart: number;
  selectionEnd: number;
}

type DraftMap = Record<TargetId, Draft>;

const STORAGE_KEY = "vibecast.drafts.v1";
const CLIENT_ID_KEY = "vibecast.clientId.v1";

function emptyDraft(): Draft {
  return { text: "", revision: 0, ackedRevision: 0, selectionStart: 0, selectionEnd: 0 };
}

/**
 * 生成 UUID。优先用 crypto.randomUUID（仅 HTTPS/localhost 等安全上下文可用），
 * 否则降级用 getRandomValues，再不行用 Math.random 兜底。
 * 局域网内以 http://<ip> 访问时属于非安全上下文，randomUUID 不存在，必须兜底，
 * 否则会抛异常导致整个页面初始化失败（白屏）。
 */
export function uuid(): string {
  const c = globalThis.crypto as Crypto | undefined;
  if (c && typeof c.randomUUID === "function") {
    return c.randomUUID();
  }
  const bytes = new Uint8Array(16);
  if (c && typeof c.getRandomValues === "function") {
    c.getRandomValues(bytes);
  } else {
    for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  }
  // 按 RFC4122 v4 置位
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0"));
  return `${hex.slice(0, 4).join("")}-${hex.slice(4, 6).join("")}-${hex.slice(6, 8).join("")}-${hex.slice(8, 10).join("")}-${hex.slice(10, 16).join("")}`;
}

/** 稳定的设备标识，用于 hello.clientId。首访生成并持久化。 */
export function getClientId(): string {
  let id = localStorage.getItem(CLIENT_ID_KEY);
  if (!id) {
    id = uuid();
    localStorage.setItem(CLIENT_ID_KEY, id);
  }
  return id;
}

export class DraftStore {
  private drafts: DraftMap;

  constructor() {
    this.drafts = this.load();
  }

  private load(): DraftMap {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return {};
      const parsed = JSON.parse(raw) as Partial<DraftMap>;
      const map: DraftMap = {};
      for (const [id, d] of Object.entries(parsed)) {
        if (d && typeof d.text === "string" && typeof d.revision === "number") {
          map[id] = {
            text: d.text,
            revision: d.revision,
            ackedRevision: typeof d.ackedRevision === "number" ? d.ackedRevision : 0,
            selectionStart: typeof d.selectionStart === "number" ? d.selectionStart : d.text.length,
            selectionEnd: typeof d.selectionEnd === "number" ? d.selectionEnd : d.text.length,
          };
        }
      }
      return map;
    } catch {
      return {};
    }
  }

  private persist(): void {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(this.drafts));
    } catch {
      // 存储满或隐私模式：忽略，内存态仍可用。
    }
  }

  get(targetId: TargetId): Draft {
    if (!this.drafts[targetId]) {
      this.drafts[targetId] = emptyDraft();
      this.persist();
    }
    return this.drafts[targetId];
  }

  /** 是否已完全同步：当前 revision 已被 Mac ack 且无更新内容。 */
  isSynced(targetId: TargetId): boolean {
    const d = this.get(targetId);
    return d.ackedRevision >= d.revision;
  }

  /**
   * 更新某目标文本，返回新版本号（单调递增）。
   * 仅当文本或选区实际变化时递增 revision。
   */
  update(targetId: TargetId, text: string, selectionStart: number, selectionEnd: number): Draft {
    const d = this.get(targetId);
    const changed = d.text !== text;
    d.text = text;
    d.selectionStart = selectionStart;
    d.selectionEnd = selectionEnd;
    if (changed) {
      d.revision += 1;
    }
    this.persist();
    return d;
  }

  /** 清空某目标草稿，递增 revision（清空也是一次需同步的变更）。 */
  clear(targetId: TargetId): Draft {
    const d = this.get(targetId);
    d.text = "";
    d.selectionStart = 0;
    d.selectionEnd = 0;
    d.revision += 1;
    this.persist();
    return d;
  }

  /** 记录 Mac 已应用的版本号（仅允许前进，旧 ack 不回退）。 */
  markAcked(targetId: TargetId, revision: number): void {
    const d = this.get(targetId);
    if (revision > d.ackedRevision) {
      d.ackedRevision = revision;
      this.persist();
    }
  }
}
