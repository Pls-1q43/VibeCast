// VibeCast 配置页（PRD 20）。由 Mac 托管，通过 WebSocket 读写目标 Profile。
import "./ui/styles.css";
import "./ui/config.css";
import {
  PROTOCOL_VERSION,
  type ConfigTarget,
  type NetworkInterfaceInfo,
  type NetworkSettings,
  type PortCheckResult,
  type RunningApp,
  type ServerMessage,
  type TargetId,
  type TargetProfile,
  type VoiceEnvironmentMessage,
  isServerMessage,
} from "./ws/protocol.ts";
import { getClientId } from "./store/draftStore.ts";
import { LANGUAGES, createI18n, setLang, type Lang } from "./i18n.ts";
import { isSafeImageDataUrl, renderTargetIcon } from "./ui/targetIcon.ts";

const mount = document.getElementById("config")!;
const i18n = createI18n();

const PRESET_LABELS: Record<string, string> = {
  codex: "Codex",
  workbuddy: "WorkBuddy",
  notion: "Notion",
  obsidian: "Obsidian",
  codebuddycn: "CodeBuddyCN",
  codebuddy: "CodeBuddy",
};

type VoiceShortcut = NonNullable<TargetProfile["voiceShortcut"]>;

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
let networkDraft: NetworkSettings | null = null;
let networkInterfaces: NetworkInterfaceInfo[] = [];
let portStatus: PortCheckResult | null = null;
let voiceEnvironment: VoiceEnvironmentMessage | null = null;
let awaitingNetworkSave = false;
let reconnectTimer: number | null = null;
let statusTimer: number | null = null;
let portCheckTimer: number | null = null;
let lastStatus = i18n.t("cfg.connecting");

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
  ws.onerror = () => setStatus(i18n.t("cfg.errorConnect"));
  ws.onclose = () => {
    connected = false;
    render();
    setStatus(i18n.t("cfg.reconnecting"));
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
      setStatus(i18n.t("cfg.connected", { name: serverName }));
      send({ type: "get_config" });
      send({ type: "list_running_apps" });
      send({ type: "get_status" });
      send({ type: "get_network_settings" });
      send({ type: "get_voice_environment" });
      startStatusPolling();
      render();
      break;
    case "server_status":
      {
        const shouldRender = serverName !== m.serverName || accessibilityGranted !== m.accessibilityGranted;
        serverName = m.serverName;
        accessibilityGranted = m.accessibilityGranted;
        if (shouldRender) render();
      }
      setStatus(i18n.t("cfg.connected", { name: serverName }));
      break;
    case "config":
      targets = m.targets;
      render();
      break;
    case "running_apps":
      runningApps = m.apps;
      render();
      break;
    case "network_settings":
      networkDraft = { ...m.settings };
      networkInterfaces = m.interfaces;
      portStatus = m.portStatus;
      render();
      if (awaitingNetworkSave) {
        awaitingNetworkSave = false;
        setStatus(i18n.t("cfg.networkSaved"));
      }
      break;
    case "network_interfaces":
      networkInterfaces = m.interfaces;
      render();
      break;
    case "port_check":
      portStatus = m.result;
      updatePortStatus();
      break;
    case "voice_environment":
      voiceEnvironment = m;
      render();
      break;
    case "test_result": {
      const text = m.success
        ? i18n.t("cfg.testOk", { message: "" })
        : i18n.t("cfg.testFailed", { message: i18n.error(m.errorCode, m.message) });
      setStatus(text);
      const el = document.querySelector(`[data-test-result="${cssEscape(m.targetId)}"]`);
      if (el) el.textContent = text;
      break;
    }
    case "error":
      setStatus(i18n.error(m.errorCode, m.message));
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
  document.title = i18n.t("cfg.pageTitle");
  mount.innerHTML = "";
  mount.append(renderHeader(), renderOnboarding(), renderNetworkSettings(), renderVoiceEnvironment(), renderAddTarget(), renderTargetList());
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
  brand.append(logo, brandName, renderLanguagePicker());
  const h = document.createElement("h1");
  h.textContent = i18n.t("cfg.title");
  const lead = document.createElement("p");
  lead.textContent = i18n.t("cfg.lead");
  titleWrap.append(brand, h, lead);

  const panel = el("div", "cfg-hero__status");
  const conn = el("div", "cfg-statusline");
  conn.dataset.cfgStatus = "";
  conn.textContent = lastStatus;
  const allNormal = connected && accessibilityGranted;
  const status = el("div", allNormal ? "cfg-pill cfg-pill--ok" : "cfg-pill cfg-pill--warn");
  status.textContent = allNormal
    ? i18n.t("cfg.statusOk")
    : connected
      ? i18n.t("cfg.statusNeedsPermission")
      : i18n.t("cfg.statusConnecting");
  const statusHint = document.createElement("p");
  statusHint.className = allNormal ? "cfg-permission-hint" : "cfg-permission-hint cfg-permission-hint--warn";
  statusHint.textContent = allNormal
    ? i18n.t("cfg.statusOkHint")
    : connected
      ? i18n.t("cfg.statusNeedsPermissionHint")
      : i18n.t("cfg.statusConnectingHint");
  const actions = el("div", "cfg-hero__actions");
  const refresh = button(i18n.t("cfg.refreshApps"), "btn btn--ghost", () => {
    send({ type: "list_running_apps" });
    setStatus(i18n.t("cfg.refreshingApps"));
  });
  const openSettings = button(i18n.t("cfg.openAccessibility"), accessibilityGranted ? "btn btn--ghost" : "btn btn--primary", () => {
    send({ type: "open_accessibility_settings" });
    setStatus(i18n.t("cfg.openAccessibilityRequested"));
  });
  actions.append(openSettings, refresh);
  panel.append(conn, status, statusHint, actions);
  header.append(titleWrap, panel);
  return header;
}

function renderLanguagePicker(): HTMLLabelElement {
  const wrap = document.createElement("label");
  wrap.className = "language-picker";
  const span = document.createElement("span");
  span.textContent = i18n.t("app.language");
  const select = document.createElement("select");
  for (const lang of LANGUAGES) {
    const option = document.createElement("option");
    option.value = lang.code;
    option.textContent = lang.label;
    option.selected = lang.code === i18n.lang;
    select.append(option);
  }
  select.addEventListener("change", () => {
    setLang(select.value as Lang);
    location.reload();
  });
  wrap.append(span, select);
  return wrap;
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
  summary.textContent = allDone ? i18n.t("cfg.onboardingDone") : i18n.t("cfg.onboarding");
  const list = el("ol", "cfg-checklist");
  list.append(
    checklistItem(i18n.t("cfg.checkConnect"), connected),
    checklistItem(i18n.t("cfg.checkPermission"), accessibilityGranted),
    checklistItem(i18n.t("cfg.checkEnabled"), enabledTargets.length > 0),
    checklistItem(i18n.t("cfg.checkBundle"), enabledTargets.length > 0 && configuredTargets.length === enabledTargets.length),
    checklistItem(i18n.t("cfg.checkTest"), testedReady),
  );
  box.append(summary, list);
  return box;
}

function renderAddTarget(): HTMLElement {
  const section = el("section", "cfg-add");
  const title = document.createElement("h2");
  title.textContent = i18n.t("cfg.addCustom");
  const controls = el("div", "cfg-add__controls");
  const nameInput = input(i18n.t("cfg.customApp"), i18n.t("cfg.appName"));
  const bundleInput = input("", i18n.t("cfg.bundleExample"));
  let iconDataUrl: string | null = null;
  let iconPreview = renderTargetIcon("custom", nameInput.value, "cfg-row__icon", iconDataUrl);

  const updatePreview = () => {
    const next = renderTargetIcon("custom", nameInput.value || bundleInput.value || "App", "cfg-row__icon", iconDataUrl);
    iconPreview.replaceWith(next);
    iconPreview = next;
  };
  nameInput.addEventListener("input", updatePreview);

  const picker = select("", [["", i18n.t("cfg.pickRunning")], ...runningApps.map((a) => [a.bundleId, `${a.name} (${a.bundleId})`] as [string, string])], (v) => {
    if (!v) return;
    const app = runningApps.find((a) => a.bundleId === v);
    if (!app) return;
    nameInput.value = app.name;
    bundleInput.value = app.bundleId;
    iconDataUrl = app.iconDataUrl ?? null;
    updatePreview();
  });
  const iconPicker = renderIconPicker(
    () => iconDataUrl,
    (v) => {
      iconDataUrl = v;
      updatePreview();
    },
  );
  const addBtn = button(i18n.t("cfg.add"), "btn btn--primary", () => {
    const displayName = nameInput.value.trim();
    const bundleId = bundleInput.value.trim();
    if (!displayName && !bundleId) {
      setStatus(i18n.t("cfg.needName"));
      return;
    }
    send({ type: "create_target", displayName: displayName || bundleId, bundleId: bundleId || null, iconDataUrl });
    setStatus(i18n.t("cfg.adding", { name: displayName || bundleId }));
  });
  controls.append(iconPreview, wrapField(i18n.t("cfg.appName"), nameInput), wrapField("Bundle ID", bundleInput), wrapField(i18n.t("cfg.runningApp"), picker), iconPicker, addBtn);
  section.append(title, controls);
  return section;
}

function renderNetworkSettings(): HTMLElement {
  const section = el("section", "cfg-network");
  const title = document.createElement("h2");
  title.textContent = i18n.t("cfg.networkTitle");
  const hint = document.createElement("p");
  hint.className = "cfg-hint";
  hint.textContent = i18n.t("cfg.networkHint");

  if (!networkDraft) {
    const empty = el("p", "cfg-empty");
    empty.textContent = i18n.t("cfg.loading");
    section.append(title, empty);
    return section;
  }

  const controls = el("div", "cfg-network__grid");
  const bindValue = networkDraft.bindMode === "all" ? "all" : (networkDraft.bindAddress ?? "");
  const bindOptions: [string, string][] = [
    ["all", i18n.t("cfg.bindAll")],
    ...networkInterfaces.map((iface) => [
      iface.address,
      `${iface.address} · ${iface.name}${iface.isPreferred ? ` · ${i18n.t("cfg.preferred")}` : ""}`,
    ] as [string, string]),
  ];
  if (networkDraft.bindMode === "address" && networkDraft.bindAddress && !bindOptions.some(([v]) => v === networkDraft?.bindAddress)) {
    bindOptions.push([networkDraft.bindAddress, `${networkDraft.bindAddress} · ${i18n.t("cfg.unavailableInterface")}`]);
  }
  const bind = select(bindValue, bindOptions, (v) => {
    if (!networkDraft) return;
    if (v === "all") {
      networkDraft.bindMode = "all";
      networkDraft.bindAddress = null;
    } else {
      networkDraft.bindMode = "address";
      networkDraft.bindAddress = v;
    }
    schedulePortCheck();
  });

  const port = numberInput(networkDraft.port, (v) => {
    if (!networkDraft) return;
    networkDraft.port = v;
    schedulePortCheck();
  });
  port.min = "1";
  port.max = "65535";
  port.step = "1";

  const status = el("div", "cfg-port-status");
  status.setAttribute("data-port-status", "");
  status.dataset.tone = "neutral";
  status.textContent = i18n.t("cfg.portUnknown");
  controls.append(
    wrapField(i18n.t("cfg.bindAddress"), bind, i18n.t("cfg.bindAddressHint")),
    wrapField(i18n.t("cfg.port"), port, i18n.t("cfg.portHint")),
  );

  const actions = el("div", "cfg-network__actions");
  const check = button(i18n.t("cfg.checkPort"), "btn btn--ghost", () => {
    sendPortCheck();
    setStatus(i18n.t("cfg.checkingPort"));
  });
  const save = button(i18n.t("cfg.saveNetwork"), "btn btn--primary", () => {
    if (!networkDraft) return;
    const next = normalizeNetworkDraft(networkDraft);
    if (next.bindMode === "all" && !window.confirm(i18n.t("cfg.bindAllConfirm"))) return;
    if (portStatus && portStatus.status !== "available" && portStatus.port === next.port) {
      setStatus(i18n.t("cfg.portUnavailable"));
      return;
    }
    awaitingNetworkSave = true;
    send({ type: "set_network_settings", settings: next });
    setStatus(i18n.t("cfg.savingNetwork"));
  });
  actions.append(status, check, save);
  section.append(title, hint, controls, actions);
  window.setTimeout(updatePortStatus, 0);
  return section;
}

function renderVoiceEnvironment(): HTMLElement {
  const section = el("section", "cfg-network");
  const title = document.createElement("h2");
  title.textContent = i18n.t("cfg.voiceTitle");
  const hint = document.createElement("p");
  hint.className = "cfg-hint";
  hint.textContent = i18n.t("cfg.voiceHint");

  const status = el("div", voiceEnvironment?.installed ? "cfg-pill cfg-pill--ok" : "cfg-pill cfg-pill--warn");
  status.textContent = voiceEnvironment?.installed
    ? i18n.t("cfg.voiceInstalled", { name: voiceEnvironment.deviceName ?? "Virtual Mic" })
    : i18n.t("cfg.voiceMissing");

  const detail = document.createElement("p");
  detail.className = "cfg-hint";
  detail.textContent = voiceEnvironment
    ? [
        voiceEnvironment.defaultInputMatches ? i18n.t("cfg.voiceDefaultInputOk") : i18n.t("cfg.voiceDefaultInputWillSwitch"),
        voiceEnvironment.message ?? "",
      ].filter(Boolean).join(" · ")
    : i18n.t("cfg.loading");

  const currentShortcut = currentGlobalVoiceShortcut();
  const keyInput = input(currentShortcut.key, "right_command");
  const modsInput = input(currentShortcut.modifiers.join(","), "command, option, control, shift");
  const preset = select(voiceShortcutPresetValue(currentShortcut), [
    ["right_command", i18n.t("cfg.voiceShortcutRightCommand")],
    ["right_option", i18n.t("cfg.voiceShortcutRightOption")],
    ["left_command", i18n.t("cfg.voiceShortcutLeftCommand")],
    ["left_option", i18n.t("cfg.voiceShortcutLeftOption")],
    ["custom", i18n.t("cfg.voiceShortcutCustom")],
  ], (v) => {
    const next = voiceShortcutFromPreset(v, { modifiers: splitList(modsInput.value), key: keyInput.value || currentShortcut.key });
    keyInput.value = next.key;
    modsInput.value = next.modifiers.join(",");
  });
  keyInput.addEventListener("input", () => {
    preset.value = voiceShortcutPresetValue({ modifiers: splitList(modsInput.value), key: keyInput.value });
  });
  modsInput.addEventListener("input", () => {
    preset.value = voiceShortcutPresetValue({ modifiers: splitList(modsInput.value), key: keyInput.value });
  });
  const controls = el("div", "cfg-row__quick");
  controls.append(
    wrapField(i18n.t("cfg.voiceWakeShortcut"), preset, i18n.t("cfg.voiceWakeShortcutHint")),
    wrapField(i18n.t("cfg.voiceShortcutKey"), keyInput),
    wrapField(i18n.t("cfg.voiceShortcutMods"), modsInput),
  );

  const actions = el("div", "cfg-row__actions");
  actions.append(
    button(i18n.t("cfg.refreshVoice"), "btn btn--ghost", () => {
      send({ type: "get_voice_environment" });
      setStatus(i18n.t("cfg.refreshingVoice"));
    }),
    button(i18n.t("cfg.installVoice"), voiceEnvironment?.installed ? "btn btn--ghost" : "btn btn--primary", () => {
      send({ type: "install_virtual_mic" });
      setStatus(i18n.t("cfg.installingVoice"));
    }),
    button(i18n.t("cfg.saveVoiceShortcut"), "btn btn--primary", () => {
      saveGlobalVoiceShortcut({ modifiers: splitList(modsInput.value), key: keyInput.value || "right_command" });
    }),
  );
  section.append(title, hint, status, detail, controls, actions);
  return section;
}

function currentGlobalVoiceShortcut(): VoiceShortcut {
  const shortcut = targets.find((t) => t.profile.voiceShortcut)?.profile.voiceShortcut;
  return normalizeVoiceShortcut(shortcut);
}

function normalizeVoiceShortcut(shortcut?: VoiceShortcut | null): VoiceShortcut {
  const key = shortcut?.key?.trim() || "right_option";
  return { modifiers: shortcut?.modifiers ?? [], key };
}

function voiceShortcutPresetValue(shortcut: VoiceShortcut): string {
  if (shortcut.modifiers.length) return "custom";
  switch (shortcut.key.trim().toLowerCase()) {
  case "right_command":
  case "rightcommand":
  case "right_cmd":
  case "rightcmd":
  case "command_right":
  case "cmd_right":
    return "right_command";
  case "right_option":
  case "rightoption":
  case "right_opt":
  case "rightopt":
  case "option_right":
  case "opt_right":
    return "right_option";
  case "left_command":
  case "leftcommand":
  case "left_cmd":
  case "leftcmd":
  case "command_left":
  case "cmd_left":
    return "left_command";
  case "left_option":
  case "leftoption":
  case "left_opt":
  case "leftopt":
  case "option_left":
  case "opt_left":
    return "left_option";
  default:
    return "custom";
  }
}

function voiceShortcutFromPreset(value: string, fallback: VoiceShortcut): VoiceShortcut {
  if (value === "custom") return fallback;
  return { modifiers: [], key: value };
}

function saveGlobalVoiceShortcut(shortcut: VoiceShortcut): void {
  const normalized = normalizeVoiceShortcut(shortcut);
  for (const target of targets) {
    target.profile.voiceShortcut = normalized;
    send({ type: "set_config", targetId: target.id, profile: target.profile });
  }
  setStatus(i18n.t("cfg.voiceShortcutSaved", { key: normalized.key }));
}

function renderTargetList(): HTMLElement {
  const section = el("section", "cfg-list");
  const header = el("div", "cfg-list__header");
  const h = document.createElement("h2");
  h.textContent = i18n.t("cfg.targetList");
  const meta = document.createElement("p");
  const enabled = targets.filter((t) => t.enabled).length;
  const ready = targets.filter((t) => t.enabled && t.profile.bundleId.trim()).length;
  meta.textContent = i18n.t("cfg.meta", { enabled, ready });
  header.append(h, meta);
  section.append(header);

  if (!targets.length) {
    const empty = el("p", "cfg-empty");
    empty.textContent = i18n.t("cfg.loading");
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
    syncMode: target.profile.syncMode ?? "mirror",
  };
  const row = el("article", "cfg-row");
  row.dataset.target = target.id;
  if (!target.enabled) row.classList.add("cfg-row--disabled");

  const main = el("div", "cfg-row__main");
  const toggle = checkbox(target.enabled, (v) => {
    send({ type: "set_target_enabled", targetId: target.id, enabled: v });
    setStatus(i18n.t("cfg.enabledState", { name: p.displayName, state: v ? i18n.t("cfg.enabled") : i18n.t("cfg.disabled") }));
  });
  toggle.setAttribute("aria-label", i18n.t("cfg.enabledAria", { name: p.displayName }));

  let icon = renderTargetIcon(target.id, p.displayName || target.id, "cfg-row__icon", p.iconDataUrl);
  const updateIcon = () => {
    const next = renderTargetIcon(target.id, p.displayName || target.id, "cfg-row__icon", p.iconDataUrl);
    icon.replaceWith(next);
    icon = next;
  };

  const summary = el("div", "cfg-row__summary");
  const titleLine = el("div", "cfg-row__titleline");
  const title = document.createElement("h3");
  title.textContent = p.displayName || PRESET_LABELS[target.id] || target.id;
  const badge = el("span", p.bundleId.trim() ? "cfg-badge cfg-badge--ok" : "cfg-badge cfg-badge--warn");
  badge.textContent = p.bundleId.trim() ? i18n.t("cfg.ready") : i18n.t("cfg.needsBundle");
  titleLine.append(title, badge);
  const subtitle = document.createElement("p");
  subtitle.textContent = target.kind === "preset" ? i18n.t("cfg.preset") : i18n.t("cfg.custom");
  summary.append(titleLine, subtitle);
  main.append(toggle, icon, summary);

  const quick = el("div", "cfg-row__quick");
  const displayName = input(p.displayName, i18n.t("cfg.displayName"));
  displayName.addEventListener("input", () => {
    p.displayName = displayName.value;
    title.textContent = p.displayName || target.id;
    updateIcon();
  });
  const bundleId = input(p.bundleId, "Bundle ID");
  bundleId.addEventListener("input", () => {
    p.bundleId = bundleId.value;
    badge.textContent = p.bundleId.trim() ? i18n.t("cfg.ready") : i18n.t("cfg.needsBundle");
    badge.className = p.bundleId.trim() ? "cfg-badge cfg-badge--ok" : "cfg-badge cfg-badge--warn";
  });
  const picker = select("", [["", i18n.t("cfg.pickRunning")], ...runningApps.map((a) => [a.bundleId, `${a.name} (${a.bundleId})`] as [string, string])], (v) => {
    if (!v) return;
    const app = runningApps.find((a) => a.bundleId === v);
    p.bundleId = v;
    bundleId.value = v;
    p.iconDataUrl = app?.iconDataUrl ?? null;
    updateIcon();
    if (target.kind === "custom" && app && !displayName.value.trim()) {
      p.displayName = app.name;
      displayName.value = app.name;
      title.textContent = app.name;
      updateIcon();
    }
    badge.textContent = i18n.t("cfg.ready");
    badge.className = "cfg-badge cfg-badge--ok";
  });
  const iconPicker = renderIconPicker(
    () => p.iconDataUrl ?? null,
    (v) => {
      p.iconDataUrl = v;
      updateIcon();
    },
  );
  quick.append(wrapField(i18n.t("cfg.displayName"), displayName), wrapField("Bundle ID", bundleId), wrapField(i18n.t("cfg.quickPick"), picker), iconPicker);

  const validation = el("div", "cfg-validation");
  const result = el("div", "cfg-result");
  result.setAttribute("data-test-result", target.id);

  const advanced = renderAdvanced(target.id, p);

  const actions = el("div", "cfg-row__actions");
  const saveBtn = button(i18n.t("cfg.save"), "btn btn--primary", () => {
    const issues = validateProfile(p);
    validation.textContent = issues.join(" · ");
    send({ type: "set_config", targetId: target.id, profile: p });
    setStatus(i18n.t("cfg.saved", { name: p.displayName || target.id }));
  });
  const testBtn = button(i18n.t("cfg.test"), "btn btn--ghost", () => {
    const issues = validateProfile(p);
    validation.textContent = issues.join(" · ");
    if (!p.bundleId.trim()) {
      setStatus(i18n.t("cfg.needBundle"));
      return;
    }
    send({ type: "set_config", targetId: target.id, profile: p });
    send({ type: "test_target", targetId: target.id });
    setStatus(i18n.t("cfg.testing", { name: p.displayName || target.id }));
  });
  actions.append(saveBtn, testBtn);
  if (target.kind === "custom") {
    actions.append(button(i18n.t("cfg.delete"), "btn btn--ghost btn--danger", () => {
      if (!window.confirm(i18n.t("cfg.deleteConfirm", { name: p.displayName || target.id }))) return;
      send({ type: "delete_target", targetId: target.id });
      setStatus(i18n.t("cfg.deleteRequested", { name: p.displayName || target.id }));
    }));
  }

  row.append(main, quick, validation, advanced, actions, result);
  return row;
}

function renderAdvanced(targetId: TargetId, p: TargetProfile): HTMLElement {
  const details = document.createElement("details");
  details.className = "cfg-advanced";
  const summary = document.createElement("summary");
  summary.textContent = i18n.t("cfg.advanced");

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
    wrapField(i18n.t("cfg.focusMode"), select(p.focusMode, [
      ["shortcut", i18n.t("cfg.focusShortcut")], ["preserve_last_focus", i18n.t("cfg.preserveFocus")],
      ["accessibility", i18n.t("cfg.accessibilityLookup")], ["custom", i18n.t("cfg.customMode")],
    ], (v) => (p.focusMode = v as TargetProfile["focusMode"]))),
    wrapField(i18n.t("cfg.focusKey"), focusShortcutKey),
    wrapField(i18n.t("cfg.focusMods"), focusShortcutMods),
    wrapField(i18n.t("cfg.focusWait"), numberInput(p.focusWaitMs, (v) => (p.focusWaitMs = v))),
    wrapField(i18n.t("cfg.syncMode"), select(p.syncMode ?? "mirror", [
      ["mirror", i18n.t("cfg.syncMirror")],
      ["editor", i18n.t("cfg.syncEditor")],
    ], (v) => {
      p.syncMode = v as TargetProfile["syncMode"];
      if (v === "editor") {
        p.allowSelectAllReplace = false;
        if (p.writeMode === "clipboard_replace" || p.writeMode === "clipboard_paste") {
          p.writeMode = "clipboard_insert";
        }
      } else if (targetId === "notion" && p.writeMode === "clipboard_replace") {
        p.allowSelectAllReplace = true;
      }
    }), i18n.t("cfg.syncEditorHint")),
    wrapField(i18n.t("cfg.writeMode"), select(p.writeMode ?? "auto", [
      ["auto", i18n.t("cfg.writeAuto")],
      ["axvalue", i18n.t("cfg.writeAx")],
      ["clipboard_replace", i18n.t("cfg.writeReplace")],
      ["clipboard_insert", i18n.t("cfg.writeInsert")],
    ], (v) => {
      p.writeMode = v as TargetProfile["writeMode"];
      if (v === "clipboard_insert") p.allowSelectAllReplace = false;
      if (targetId === "notion" && v === "clipboard_replace" && p.syncMode !== "editor") {
        p.allowSelectAllReplace = true;
      }
      if ((v === "clipboard_replace" || v === "clipboard_paste") && p.syncMode === "editor") {
        p.writeMode = "clipboard_insert";
        p.allowSelectAllReplace = false;
      }
    })),
    wrapField(i18n.t("cfg.allowReplace"), checkbox(p.allowSelectAllReplace, (v) => (p.allowSelectAllReplace = v)), i18n.t("cfg.allowReplaceHint")),
    wrapField(i18n.t("cfg.sendMode"), select(p.sendMode, [
      ["key", i18n.t("cfg.sendKey")],
      ["custom_shortcut", i18n.t("cfg.customShortcut")],
      ["accessibility_button", i18n.t("cfg.sendButton")],
      ["none", i18n.t("cfg.syncOnly")],
    ], (v) => (p.sendMode = v as TargetProfile["sendMode"]))),
    wrapField(i18n.t("cfg.sendShortcutKey"), sendShortcutKey),
    wrapField(i18n.t("cfg.sendShortcutMods"), sendShortcutMods),
    wrapField(i18n.t("cfg.sendButtonContains"), inputWithChange(p.sendButtonTitleContains ?? "", (v) => (p.sendButtonTitleContains = v || null))),
    wrapField(i18n.t("cfg.clearAfterSend"), checkbox(p.clearAfterSend, (v) => (p.clearAfterSend = v))),
    wrapField(i18n.t("cfg.allowEmpty"), checkbox(p.allowEmpty, (v) => (p.allowEmpty = v))),
    wrapField(i18n.t("cfg.keepForeground"), checkbox(p.keepForeground, (v) => (p.keepForeground = v))),
    wrapField(i18n.t("cfg.maxLength"), numberInput(p.maxTextLength, (v) => (p.maxTextLength = v))),
  );
  details.append(summary, grid, advancedHint(targetId));
  return details;
}

function advancedHint(targetId: TargetId): HTMLElement {
  const p = document.createElement("p");
  p.className = "cfg-hint";
  p.textContent = targetId === "notion"
    ? i18n.t("cfg.notionHint")
    : targetId === "obsidian"
      ? i18n.t("cfg.obsidianHint")
    : i18n.t("cfg.defaultHint");
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

function renderIconPicker(getValue: () => string | null, setValue: (v: string | null) => void): HTMLElement {
  const wrap = document.createElement("div");
  wrap.className = "cfg-field cfg-icon-field";
  const span = document.createElement("span");
  span.textContent = i18n.t("cfg.icon");
  const actions = el("div", "cfg-icon-actions");
  const file = document.createElement("input");
  file.type = "file";
  file.accept = "image/png,image/jpeg,image/webp,image/svg+xml";
  file.addEventListener("change", async () => {
    const selected = file.files?.[0];
    file.value = "";
    if (!selected) return;
    const dataUrl = await fileToIconDataUrl(selected).catch(() => null);
    if (!dataUrl) {
      setStatus(i18n.t("cfg.iconInvalid"));
      return;
    }
    setValue(dataUrl);
    setStatus(i18n.t("cfg.iconUpdated"));
  });
  const clear = button(i18n.t("cfg.iconClear"), "btn btn--ghost cfg-icon-clear", () => {
    if (!getValue()) return;
    setValue(null);
    setStatus(i18n.t("cfg.iconCleared"));
  });
  actions.append(file, clear);
  wrap.append(span, actions);
  return wrap;
}

async function fileToIconDataUrl(file: File): Promise<string | null> {
  if (file.type === "image/svg+xml") {
    const dataUrl = await readFileAsDataURL(file);
    return isSafeImageDataUrl(dataUrl) ? dataUrl : null;
  }

  if (!["image/png", "image/jpeg", "image/webp"].includes(file.type)) return null;

  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await loadImage(objectUrl);
    const side = 96;
    const canvas = document.createElement("canvas");
    canvas.width = side;
    canvas.height = side;
    const ctx = canvas.getContext("2d");
    if (!ctx) return null;
    ctx.clearRect(0, 0, side, side);
    const scale = Math.min(side / img.naturalWidth, side / img.naturalHeight);
    const width = Math.max(1, Math.round(img.naturalWidth * scale));
    const height = Math.max(1, Math.round(img.naturalHeight * scale));
    const x = Math.round((side - width) / 2);
    const y = Math.round((side - height) / 2);
    ctx.drawImage(img, x, y, width, height);
    const dataUrl = canvas.toDataURL("image/png");
    return isSafeImageDataUrl(dataUrl) ? dataUrl : null;
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}

function loadImage(src: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error("image load failed"));
    img.src = src;
  });
}

function readFileAsDataURL(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result ?? ""));
    reader.onerror = () => reject(reader.error ?? new Error("file read failed"));
    reader.readAsDataURL(file);
  });
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
  if (!p.bundleId.trim()) issues.push(i18n.t("cfg.issueBundle"));
  if (p.focusWaitMs < 50 || p.focusWaitMs > 5000) issues.push(i18n.t("cfg.issueFocusWait"));
  if (p.maxTextLength < 1 || p.maxTextLength > 50000) issues.push(i18n.t("cfg.issueMaxLength"));
  if (p.syncMode === "editor" && p.allowSelectAllReplace) {
    issues.push(i18n.t("cfg.issueEditorReplace"));
  }
  if ((p.writeMode === "clipboard_replace" || p.writeMode === "clipboard_paste") && !p.allowSelectAllReplace) {
    issues.push(i18n.t("cfg.issueClipboard"));
  }
  return issues.length ? issues : [i18n.t("cfg.valid")];
}

function normalizeNetworkDraft(settings: NetworkSettings): NetworkSettings {
  const port = Number.isFinite(settings.port) ? Math.max(1, Math.min(65535, Math.round(settings.port))) : 8787;
  if (settings.bindMode === "all") return { bindMode: "all", bindAddress: null, port };
  const fallback = networkInterfaces.find((iface) => iface.isPreferred)?.address ?? networkInterfaces[0]?.address ?? null;
  return { bindMode: "address", bindAddress: settings.bindAddress || fallback, port };
}

function schedulePortCheck(): void {
  if (portCheckTimer !== null) clearTimeout(portCheckTimer);
  portCheckTimer = window.setTimeout(() => {
    portCheckTimer = null;
    sendPortCheck();
  }, 250);
}

function sendPortCheck(): void {
  if (!networkDraft || ws.readyState !== WebSocket.OPEN) return;
  const next = normalizeNetworkDraft(networkDraft);
  send({
    type: "check_port",
    bindMode: next.bindMode,
    bindAddress: next.bindAddress ?? null,
    port: next.port,
  });
}

function updatePortStatus(): void {
  const el = document.querySelector<HTMLElement>("[data-port-status]");
  if (!el) return;
  if (!portStatus) {
    el.textContent = i18n.t("cfg.portUnknown");
    el.dataset.tone = "neutral";
    return;
  }
  const label =
    portStatus.status === "available"
      ? i18n.t("cfg.portAvailable")
      : portStatus.status === "invalid"
        ? i18n.t("cfg.portInvalid")
        : i18n.t("cfg.portUnavailable");
  el.textContent = portStatus.message ? `${label}: ${portStatus.message}` : label;
  el.dataset.tone = portStatus.status === "available" ? "ok" : "warn";
}

function cssEscape(value: string): string {
  const escape = globalThis.CSS?.escape;
  return typeof escape === "function" ? escape(value) : value.replace(/"/g, '\\"');
}

render();
connect();
