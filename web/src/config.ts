// VibeCast 配置页（PRD 20）。由 Mac 托管，通过 WebSocket 读写目标 Profile。
import "./ui/styles.css";
import "./ui/config.css";
import {
  PROTOCOL_VERSION,
  type ConfigTarget,
  type RunningApp,
  type ServerMessage,
  type TargetId,
  type TargetProfile,
  isServerMessage,
} from "./ws/protocol.ts";
import { getClientId } from "./store/draftStore.ts";

const mount = document.getElementById("config")!;

const PRESET_LABELS: Record<string, string> = {
  codex: "Codex",
  workbuddy: "WorkBuddy",
  notion: "Notion",
  codebuddy: "CodeBuddy",
};

function pairingToken(): string {
  const fromUrl = new URLSearchParams(location.search).get("token");
  if (fromUrl) {
    localStorage.setItem("vibecast.token.v1", fromUrl);
    return fromUrl;
  }
  return localStorage.getItem("vibecast.token.v1") ?? "";
}

let ws: WebSocket;
let targets: ConfigTarget[] = [];
let runningApps: RunningApp[] = [];
let serverName = "Mac";
let accessibilityGranted = false;
let connected = false;
let reconnectTimer: number | null = null;
let statusTimer: number | null = null;
let lastStatus = "正在连接 VibeCast…";

function connect() {
  if (reconnectTimer !== null) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }
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
    handle(m);
  };
  ws.onerror = () => setStatus("连接异常，请确认 VibeCast 菜单栏服务仍在运行");
  ws.onclose = () => {
    connected = false;
    render();
    setStatus("连接断开，正在重连…");
    reconnectTimer = window.setTimeout(connect, 1500);
  };
}

function setStatus(s: string) {
  lastStatus = s;
  const el = document.querySelector<HTMLElement>("[data-cfg-status]");
  if (el) el.textContent = s;
}

function handle(m: ServerMessage) {
  switch (m.type) {
    case "hello_ack":
      connected = true;
      serverName = m.serverName;
      accessibilityGranted = m.accessibilityGranted;
      setStatus(`已连接 · ${serverName}`);
      send({ type: "get_config" });
      send({ type: "list_running_apps" });
      send({ type: "get_status" });
      startStatusPolling();
      render();
      break;
    case "server_status":
      serverName = m.serverName;
      accessibilityGranted = m.accessibilityGranted;
      render();
      setStatus(`已连接 · ${serverName}`);
      break;
    case "config":
      targets = m.targets;
      render();
      break;
    case "running_apps":
      runningApps = m.apps;
      render();
      break;
    case "test_result": {
      const text = m.success ? `测试成功：${m.message ?? ""}` : `测试失败：${m.message ?? m.errorCode ?? ""}`;
      setStatus(text);
      const el = document.querySelector(`[data-test-result="${cssEscape(m.targetId)}"]`);
      if (el) el.textContent = text;
      break;
    }
    case "error":
      setStatus(`${m.message}（${m.errorCode}）`);
      break;
    default:
      break;
  }
}

function startStatusPolling() {
  if (statusTimer !== null) return;
  statusTimer = window.setInterval(() => {
    if (ws.readyState === WebSocket.OPEN) send({ type: "get_status" });
  }, 2000);
}

function send(msg: object) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
}

function render() {
  mount.innerHTML = "";
  mount.append(renderHeader(), renderOnboarding(), renderAddTarget(), renderTargetList());
}

function renderHeader(): HTMLElement {
  const header = el("header", "cfg-hero");
  const titleWrap = el("div", "cfg-hero__copy");
  const brand = el("div", "cfg-brand");
  const logo = document.createElement("img");
  logo.src = "./favicon.svg";
  logo.alt = "";
  logo.setAttribute("aria-hidden", "true");
  const brandName = document.createElement("span");
  brandName.textContent = "VibeCast";
  brand.append(logo, brandName);
  const h = document.createElement("h1");
  h.textContent = "配置目标 App";
  const lead = document.createElement("p");
  lead.textContent = "启用需要的 App，绑定 Bundle ID，测试写入效果。常用设置放在列表里，风险项收在高级设置。";
  titleWrap.append(brand, h, lead);

  const panel = el("div", "cfg-hero__status");
  const conn = el("div", "cfg-statusline");
  conn.dataset.cfgStatus = "";
  conn.textContent = lastStatus;
  const permission = el("div", accessibilityGranted ? "cfg-pill cfg-pill--ok" : "cfg-pill cfg-pill--warn");
  permission.textContent = accessibilityGranted ? "辅助功能已授权" : "辅助功能未授权";
  const actions = el("div", "cfg-hero__actions");
  const refresh = button("刷新运行应用", "btn btn--ghost", () => {
    send({ type: "list_running_apps" });
    setStatus("正在刷新运行应用…");
  });
  const openSettings = button("打开辅助功能设置", accessibilityGranted ? "btn btn--ghost" : "btn btn--primary", () => {
    send({ type: "open_accessibility_settings" });
    setStatus("已请求打开 macOS 辅助功能设置");
  });
  actions.append(openSettings, refresh);
  panel.append(conn, permission, actions);
  header.append(titleWrap, panel);
  return header;
}

function renderOnboarding(): HTMLElement {
  const enabledTargets = targets.filter((t) => t.enabled);
  const configuredTargets = enabledTargets.filter((t) => t.profile.bundleId.trim());
  const testedReady = accessibilityGranted && configuredTargets.length > 0;
  const allDone = connected && accessibilityGranted && enabledTargets.length > 0 && configuredTargets.length === enabledTargets.length;

  const box = document.createElement("details");
  box.className = "cfg-onboarding";
  box.open = !allDone;
  const summary = document.createElement("summary");
  summary.textContent = allDone ? "首次配置已完成" : "首次安装清单";
  const list = el("ol", "cfg-checklist");
  list.append(
    checklistItem("连接到 Mac 菜单栏服务", connected),
    checklistItem("放通 macOS 辅助功能权限", accessibilityGranted),
    checklistItem("勾选需要在手机端显示的 App", enabledTargets.length > 0),
    checklistItem("为每个启用 App 绑定 Bundle ID", enabledTargets.length > 0 && configuredTargets.length === enabledTargets.length),
    checklistItem("逐个测试写入，不确定发送行为时先选“仅同步不发送”", testedReady),
  );
  box.append(summary, list);
  return box;
}

function renderAddTarget(): HTMLElement {
  const section = el("section", "cfg-add");
  const title = document.createElement("h2");
  title.textContent = "添加自定义 App";
  const controls = el("div", "cfg-add__controls");
  const nameInput = input("自定义 App", "App 名称");
  const bundleInput = input("", "Bundle ID，例如 com.apple.TextEdit");

  const picker = select("", [["", "从运行应用选择"], ...runningApps.map((a) => [a.bundleId, `${a.name} (${a.bundleId})`] as [string, string])], (v) => {
    if (!v) return;
    const app = runningApps.find((a) => a.bundleId === v);
    if (!app) return;
    nameInput.value = app.name;
    bundleInput.value = app.bundleId;
  });
  const addBtn = button("添加", "btn btn--primary", () => {
    const displayName = nameInput.value.trim();
    const bundleId = bundleInput.value.trim();
    if (!displayName && !bundleId) {
      setStatus("请填写 App 名称或先从运行应用选择");
      return;
    }
    send({ type: "create_target", displayName: displayName || bundleId, bundleId: bundleId || null });
    setStatus(`正在添加 ${displayName || bundleId}…`);
  });
  controls.append(wrapField("App 名称", nameInput), wrapField("Bundle ID", bundleInput), wrapField("运行应用", picker), addBtn);
  section.append(title, controls);
  return section;
}

function renderTargetList(): HTMLElement {
  const section = el("section", "cfg-list");
  const header = el("div", "cfg-list__header");
  const h = document.createElement("h2");
  h.textContent = "目标列表";
  const meta = document.createElement("p");
  const enabled = targets.filter((t) => t.enabled).length;
  const ready = targets.filter((t) => t.enabled && t.profile.bundleId.trim()).length;
  meta.textContent = `${enabled} 个已启用，${ready} 个已绑定 Bundle ID`;
  header.append(h, meta);
  section.append(header);

  if (!targets.length) {
    const empty = el("p", "cfg-empty");
    empty.textContent = "正在读取配置…";
    section.append(empty);
    return section;
  }

  for (const target of targets) {
    section.append(renderTargetRow(target));
  }
  return section;
}

function renderTargetRow(target: ConfigTarget): HTMLElement {
  const p: TargetProfile = {
    ...target.profile,
    writeMode: target.profile.writeMode === "clipboard_paste" ? "clipboard_replace" : target.profile.writeMode,
  };
  const row = el("article", "cfg-row");
  row.dataset.target = target.id;
  if (!target.enabled) row.classList.add("cfg-row--disabled");

  const main = el("div", "cfg-row__main");
  const toggle = checkbox(target.enabled, (v) => {
    send({ type: "set_target_enabled", targetId: target.id, enabled: v });
    setStatus(`${p.displayName} 已${v ? "启用" : "停用"}`);
  });
  toggle.setAttribute("aria-label", `${p.displayName} 启用状态`);

  const icon = el("div", "cfg-row__icon");
  icon.textContent = (p.displayName || target.id).charAt(0).toUpperCase();
  icon.setAttribute("aria-hidden", "true");

  const summary = el("div", "cfg-row__summary");
  const titleLine = el("div", "cfg-row__titleline");
  const title = document.createElement("h3");
  title.textContent = p.displayName || PRESET_LABELS[target.id] || target.id;
  const badge = el("span", p.bundleId.trim() ? "cfg-badge cfg-badge--ok" : "cfg-badge cfg-badge--warn");
  badge.textContent = p.bundleId.trim() ? "可测试" : "需绑定 Bundle ID";
  titleLine.append(title, badge);
  const subtitle = document.createElement("p");
  subtitle.textContent = target.kind === "preset" ? "预置目标" : "自定义目标";
  summary.append(titleLine, subtitle);
  main.append(toggle, icon, summary);

  const quick = el("div", "cfg-row__quick");
  const displayName = input(p.displayName, "显示名称");
  displayName.addEventListener("input", () => {
    p.displayName = displayName.value;
    title.textContent = p.displayName || target.id;
  });
  const bundleId = input(p.bundleId, "Bundle ID");
  bundleId.addEventListener("input", () => {
    p.bundleId = bundleId.value;
    badge.textContent = p.bundleId.trim() ? "可测试" : "需绑定 Bundle ID";
    badge.className = p.bundleId.trim() ? "cfg-badge cfg-badge--ok" : "cfg-badge cfg-badge--warn";
  });
  const picker = select("", [["", "从运行应用选择"], ...runningApps.map((a) => [a.bundleId, `${a.name} (${a.bundleId})`] as [string, string])], (v) => {
    if (!v) return;
    const app = runningApps.find((a) => a.bundleId === v);
    p.bundleId = v;
    bundleId.value = v;
    if (target.kind === "custom" && app && !displayName.value.trim()) {
      p.displayName = app.name;
      displayName.value = app.name;
      title.textContent = app.name;
    }
    badge.textContent = "可测试";
    badge.className = "cfg-badge cfg-badge--ok";
  });
  quick.append(wrapField("显示名称", displayName), wrapField("Bundle ID", bundleId), wrapField("快速选择", picker));

  const validation = el("div", "cfg-validation");
  const result = el("div", "cfg-result");
  result.setAttribute("data-test-result", target.id);

  const advanced = renderAdvanced(target.id, p);

  const actions = el("div", "cfg-row__actions");
  const saveBtn = button("保存", "btn btn--primary", () => {
    const issues = validateProfile(p);
    validation.textContent = issues.join(" · ");
    send({ type: "set_config", targetId: target.id, profile: p });
    setStatus(`已保存 ${p.displayName || target.id}`);
  });
  const testBtn = button("测试", "btn btn--ghost", () => {
    const issues = validateProfile(p);
    validation.textContent = issues.join(" · ");
    if (!p.bundleId.trim()) {
      setStatus("请先选择或填写 Bundle ID，再测试目标");
      return;
    }
    send({ type: "set_config", targetId: target.id, profile: p });
    send({ type: "test_target", targetId: target.id });
    setStatus(`正在测试 ${p.displayName || target.id}…`);
  });
  actions.append(saveBtn, testBtn);
  if (target.kind === "custom") {
    actions.append(button("删除", "btn btn--ghost btn--danger", () => {
      if (!window.confirm(`删除自定义目标“${p.displayName || target.id}”？`)) return;
      send({ type: "delete_target", targetId: target.id });
      setStatus(`已请求删除 ${p.displayName || target.id}`);
    }));
  }

  row.append(main, quick, validation, advanced, actions, result);
  return row;
}

function renderAdvanced(targetId: TargetId, p: TargetProfile): HTMLElement {
  const details = document.createElement("details");
  details.className = "cfg-advanced";
  const summary = document.createElement("summary");
  summary.textContent = "高级设置";

  const focusShortcutKey = input(p.focusShortcut?.key ?? "", "key");
  focusShortcutKey.addEventListener("input", () => {
    p.focusShortcut = focusShortcutKey.value ? { modifiers: p.focusShortcut?.modifiers ?? [], key: focusShortcutKey.value } : null;
  });
  const focusShortcutMods = input((p.focusShortcut?.modifiers ?? []).join(","), "command, option, control, shift");
  focusShortcutMods.addEventListener("input", () => {
    p.focusShortcut = { modifiers: splitList(focusShortcutMods.value), key: p.focusShortcut?.key ?? "" };
  });

  const sendShortcutKey = input(p.sendShortcut?.key ?? "", "enter");
  sendShortcutKey.addEventListener("input", () => {
    p.sendShortcut = sendShortcutKey.value ? { modifiers: p.sendShortcut?.modifiers ?? [], key: sendShortcutKey.value } : null;
  });
  const sendShortcutMods = input((p.sendShortcut?.modifiers ?? []).join(","), "command, option, control, shift");
  sendShortcutMods.addEventListener("input", () => {
    p.sendShortcut = { modifiers: splitList(sendShortcutMods.value), key: p.sendShortcut?.key ?? "enter" };
  });

  const grid = el("div", "cfg-advanced__grid");
  grid.append(
    wrapField("聚焦策略", select(p.focusMode, [
      ["shortcut", "应用快捷键"], ["preserve_last_focus", "恢复上次焦点"],
      ["accessibility", "Accessibility 查找"], ["custom", "自定义"],
    ], (v) => (p.focusMode = v as TargetProfile["focusMode"]))),
    wrapField("聚焦快捷键 key", focusShortcutKey),
    wrapField("聚焦快捷键修饰键", focusShortcutMods),
    wrapField("聚焦等待 ms", numberInput(p.focusWaitMs, (v) => (p.focusWaitMs = v))),
    wrapField("写入方式", select(p.writeMode ?? "auto", [
      ["auto", "自动：AXValue，必要时全选替换"],
      ["axvalue", "仅 AXValue 直写"],
      ["clipboard_replace", "剪贴板全选替换"],
      ["clipboard_insert", "剪贴板光标插入"],
    ], (v) => {
      p.writeMode = v as TargetProfile["writeMode"];
      if (v === "clipboard_insert") p.allowSelectAllReplace = false;
    })),
    wrapField("允许全选替换", checkbox(p.allowSelectAllReplace, (v) => (p.allowSelectAllReplace = v)), "高风险：只在确认 Cmd+A 作用于输入框时开启。"),
    wrapField("发送策略", select(p.sendMode, [
      ["key", "按键"],
      ["custom_shortcut", "自定义快捷键"],
      ["accessibility_button", "点击发送按钮"],
      ["none", "仅同步不发送"],
    ], (v) => (p.sendMode = v as TargetProfile["sendMode"]))),
    wrapField("发送快捷键 key", sendShortcutKey),
    wrapField("发送快捷键修饰键", sendShortcutMods),
    wrapField("发送按钮标题包含", inputWithChange(p.sendButtonTitleContains ?? "", (v) => (p.sendButtonTitleContains = v || null))),
    wrapField("发送后清空", checkbox(p.clearAfterSend, (v) => (p.clearAfterSend = v))),
    wrapField("允许空文本", checkbox(p.allowEmpty, (v) => (p.allowEmpty = v))),
    wrapField("保持目标前台", checkbox(p.keepForeground, (v) => (p.keepForeground = v))),
    wrapField("最大文本长度", numberInput(p.maxTextLength, (v) => (p.maxTextLength = v))),
  );
  details.append(summary, grid, advancedHint(targetId));
  return details;
}

function advancedHint(targetId: TargetId): HTMLElement {
  const p = document.createElement("p");
  p.className = "cfg-hint";
  p.textContent = targetId === "notion"
    ? "Notion AI 输入框通常适合剪贴板全选替换；普通文档块请改为仅同步或光标插入，避免覆盖页面。"
    : "不确定目标行为时，发送策略先选择“仅同步不发送”，测试写入范围后再开启发送。";
  return p;
}

function checklistItem(text: string, done: boolean): HTMLElement {
  const li = document.createElement("li");
  li.className = done ? "is-done" : "";
  li.textContent = text;
  return li;
}

function wrapField(label: string, control: HTMLElement, hint?: string): HTMLElement {
  const wrap = document.createElement("label");
  wrap.className = "cfg-field";
  const span = document.createElement("span");
  span.textContent = label;
  wrap.append(span, control);
  if (hint) {
    const small = document.createElement("small");
    small.textContent = hint;
    wrap.append(small);
  }
  return wrap;
}

function input(value: string, placeholder = ""): HTMLInputElement {
  const i = document.createElement("input");
  i.type = "text";
  i.value = value;
  i.placeholder = placeholder;
  i.autocapitalize = "off";
  i.spellcheck = false;
  return i;
}

function inputWithChange(value: string, onChange: (v: string) => void): HTMLInputElement {
  const i = input(value);
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

function button(text: string, className: string, onClick: () => void): HTMLButtonElement {
  const b = document.createElement("button");
  b.type = "button";
  b.className = className;
  b.textContent = text;
  b.addEventListener("click", onClick);
  return b;
}

function el(tag: string, className: string): HTMLElement {
  const node = document.createElement(tag);
  node.className = className;
  return node;
}

function splitList(v: string): string[] {
  return v.split(",").map((s) => s.trim()).filter(Boolean);
}

function validateProfile(p: TargetProfile): string[] {
  const issues: string[] = [];
  if (!p.bundleId.trim()) issues.push("未配置 Bundle ID");
  if (p.focusWaitMs < 50 || p.focusWaitMs > 5000) issues.push("聚焦等待将被限制到 50-5000ms");
  if (p.maxTextLength < 1 || p.maxTextLength > 50000) issues.push("最大文本长度将被限制到 1-50000");
  if ((p.writeMode === "clipboard_replace" || p.writeMode === "clipboard_paste") && !p.allowSelectAllReplace) {
    issues.push("剪贴板全选替换需要开启“允许全选替换”");
  }
  return issues.length ? issues : ["配置看起来可以保存"];
}

function cssEscape(value: string): string {
  const escape = globalThis.CSS?.escape;
  return typeof escape === "function" ? escape(value) : value.replace(/"/g, '\\"');
}

render();
connect();
