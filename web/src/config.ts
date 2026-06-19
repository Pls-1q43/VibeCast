// VibeCast 配置页（PRD 20）。由 Mac 托管，通过 WebSocket 读写目标 Profile。
import "./ui/styles.css";
import "./ui/config.css";
import {
  PROTOCOL_VERSION,
  TARGET_IDS,
  type TargetId,
  type TargetProfile,
  type RunningApp,
  type ServerMessage,
  isServerMessage,
} from "./ws/protocol.ts";
import { getClientId } from "./store/draftStore.ts";

const mount = document.getElementById("config")!;

function pairingToken(): string {
  const fromUrl = new URLSearchParams(location.search).get("token");
  if (fromUrl) {
    localStorage.setItem("vibecast.token.v1", fromUrl);
    return fromUrl;
  }
  return localStorage.getItem("vibecast.token.v1") ?? "";
}

let ws: WebSocket;
let profiles: Record<string, TargetProfile> = {};
let runningApps: RunningApp[] = [];
const statusLine = document.createElement("div");
statusLine.className = "cfg-status";

function connect() {
  const proto = location.protocol === "https:" ? "wss:" : "ws:";
  ws = new WebSocket(`${proto}//${location.host}/ws`);
  ws.onopen = () => {
    ws.send(JSON.stringify({
      type: "hello", protocolVersion: PROTOCOL_VERSION,
      clientId: getClientId(), deviceName: "Config Page", pairingToken: pairingToken(),
    }));
  };
  ws.onmessage = (e) => {
    let m: unknown;
    try { m = JSON.parse(e.data); } catch { return; }
    if (!isServerMessage(m)) return;
    handle(m as ServerMessage);
  };
  ws.onclose = () => setStatus("连接断开，正在重连…");
}

function setStatus(s: string) {
  statusLine.textContent = s;
}

function handle(m: ServerMessage) {
  switch (m.type) {
    case "hello_ack":
      setStatus(`已连接 · ${m.serverName}${m.accessibilityGranted ? "" : "（辅助功能未授权）"}`);
      send({ type: "get_config" });
      send({ type: "list_running_apps" });
      break;
    case "config":
      profiles = m.profiles;
      render();
      break;
    case "running_apps":
      runningApps = m.apps;
      render();
      break;
    case "test_result": {
      const text = m.success ? `测试成功：${m.message ?? ""}` : `测试失败：${m.message ?? m.errorCode ?? ""}`;
      setStatus(text);
      const el = document.querySelector(`[data-test-result="${m.targetId}"]`);
      if (el) el.textContent = text;
      break;
    }
    default:
      break;
  }
}

function send(msg: object) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

function render() {
  mount.innerHTML = "";
  const h = document.createElement("h1");
  h.className = "cfg-title";
  h.textContent = "VibeCast 目标配置";
  mount.append(h, statusLine);

  for (const id of TARGET_IDS) {
    const p = profiles[id];
    if (!p) continue;
    mount.append(renderTargetForm(id, p));
  }
}

function field(label: string, control: HTMLElement): HTMLElement {
  const wrap = document.createElement("label");
  wrap.className = "cfg-field";
  const span = document.createElement("span");
  span.textContent = label;
  wrap.append(span, control);
  return wrap;
}

function textInput(value: string, onChange: (v: string) => void): HTMLInputElement {
  const i = document.createElement("input");
  i.type = "text";
  i.value = value;
  i.addEventListener("input", () => onChange(i.value));
  return i;
}

function numberInput(value: number, onChange: (v: number) => void): HTMLInputElement {
  const i = document.createElement("input");
  i.type = "number";
  i.value = String(value);
  i.addEventListener("input", () => onChange(parseInt(i.value, 10) || 0));
  return i;
}

function checkbox(value: boolean, onChange: (v: boolean) => void): HTMLInputElement {
  const i = document.createElement("input");
  i.type = "checkbox";
  i.checked = value;
  i.addEventListener("change", () => onChange(i.checked));
  return i;
}

function select(value: string, options: [string, string][], onChange: (v: string) => void): HTMLSelectElement {
  const s = document.createElement("select");
  for (const [val, label] of options) {
    const o = document.createElement("option");
    o.value = val; o.textContent = label;
    if (val === value) o.selected = true;
    s.append(o);
  }
  s.addEventListener("change", () => onChange(s.value));
  return s;
}

function renderTargetForm(id: TargetId, profile: TargetProfile): HTMLElement {
  const p: TargetProfile = { ...profile };
  const card = document.createElement("section");
  card.className = "card cfg-card";

  const title = document.createElement("h2");
  title.className = "card__title";
  title.textContent = profile.displayName || id;
  card.append(title);

  card.append(field("显示名称", textInput(p.displayName, (v) => (p.displayName = v))));

  // Bundle ID + 从运行应用选择
  const bundleInput = textInput(p.bundleId, (v) => (p.bundleId = v));
  card.append(field("Bundle ID", bundleInput));
  if (runningApps.length) {
    const picker = select("", [["", "— 从运行应用选择 —"], ...runningApps.map((a) => [a.bundleId, `${a.name} (${a.bundleId})`] as [string, string])], (v) => {
      if (v) { p.bundleId = v; bundleInput.value = v; }
    });
    card.append(field("快速选择", picker));
  }

  card.append(field("未运行时启动", checkbox(p.launchIfNotRunning, (v) => (p.launchIfNotRunning = v))));

  card.append(field("聚焦策略", select(p.focusMode, [
    ["shortcut", "应用快捷键"], ["preserve_last_focus", "恢复上次焦点"],
    ["accessibility", "Accessibility 查找"], ["custom", "自定义"],
  ], (v) => (p.focusMode = v as TargetProfile["focusMode"]))));

  card.append(field("聚焦快捷键(key)", textInput(p.focusShortcut?.key ?? "", (v) => {
    p.focusShortcut = v ? { modifiers: p.focusShortcut?.modifiers ?? [], key: v } : null;
  })));
  card.append(field("聚焦快捷键(修饰键,逗号分隔)", textInput((p.focusShortcut?.modifiers ?? []).join(","), (v) => {
    const mods = v.split(",").map((s) => s.trim()).filter(Boolean);
    p.focusShortcut = { modifiers: mods, key: p.focusShortcut?.key ?? "" };
  })));
  card.append(field("聚焦等待(ms)", numberInput(p.focusWaitMs, (v) => (p.focusWaitMs = v))));

  card.append(field("发送策略", select(p.sendMode, [
    ["key", "按键(Enter等)"], ["custom_shortcut", "自定义快捷键"],
    ["accessibility_button", "点击发送按钮"], ["none", "仅同步不发送"],
  ], (v) => (p.sendMode = v as TargetProfile["sendMode"]))));
  card.append(field("发送快捷键(key)", textInput(p.sendShortcut?.key ?? "", (v) => {
    p.sendShortcut = v ? { modifiers: p.sendShortcut?.modifiers ?? [], key: v } : null;
  })));
  card.append(field("发送快捷键(修饰键)", textInput((p.sendShortcut?.modifiers ?? []).join(","), (v) => {
    const mods = v.split(",").map((s) => s.trim()).filter(Boolean);
    p.sendShortcut = { modifiers: mods, key: p.sendShortcut?.key ?? "enter" };
  })));
  card.append(field("发送按钮标题包含", textInput(p.sendButtonTitleContains ?? "", (v) => (p.sendButtonTitleContains = v || null))));

  card.append(field("发送后清空", checkbox(p.clearAfterSend, (v) => (p.clearAfterSend = v))));
  card.append(field("允许空文本", checkbox(p.allowEmpty, (v) => (p.allowEmpty = v))));
  card.append(field("保持目标前台", checkbox(p.keepForeground, (v) => (p.keepForeground = v))));
  card.append(field("允许全选替换(Notion 文本块应关闭)", checkbox(p.allowSelectAllReplace, (v) => (p.allowSelectAllReplace = v))));
  card.append(field("最大文本长度", numberInput(p.maxTextLength, (v) => (p.maxTextLength = v))));

  const actions = document.createElement("div");
  actions.className = "card__actions";
  const saveBtn = document.createElement("button");
  saveBtn.className = "btn btn--primary";
  saveBtn.textContent = "保存";
  saveBtn.addEventListener("click", () => {
    send({ type: "set_config", targetId: id, profile: p });
    setStatus(`已保存 ${p.displayName}`);
  });
  const testBtn = document.createElement("button");
  testBtn.className = "btn btn--ghost";
  testBtn.textContent = "测试目标";
  testBtn.addEventListener("click", () => {
    // 测试前先保存，确保用最新配置测试。
    send({ type: "set_config", targetId: id, profile: p });
    send({ type: "test_target", targetId: id });
    setStatus(`正在测试 ${p.displayName}…`);
  });
  actions.append(saveBtn, testBtn);
  card.append(actions);

  const result = document.createElement("div");
  result.className = "cfg-status";
  result.setAttribute("data-test-result", id);
  card.append(result);

  return card;
}

connect();
