import { type TargetId } from "../ws/protocol.ts";

const PRESET_ICON_SRC: Record<string, string> = {
  codex: "./target-icons/codex.svg",
  workbuddy: "./target-icons/workbuddy.svg",
  notion: "./target-icons/notion.svg",
  codebuddycn: "./target-icons/codebuddy.svg",
  codebuddy: "./target-icons/codebuddy.svg",
};

export function targetIconSrc(targetId: TargetId, iconDataUrl?: string | null): string | null {
  if (iconDataUrl && isSafeImageDataUrl(iconDataUrl)) return iconDataUrl;
  return PRESET_ICON_SRC[targetId] ?? null;
}

export function renderTargetIcon(targetId: TargetId, displayName: string, className: string, iconDataUrl?: string | null): HTMLElement {
  const icon = document.createElement("div");
  icon.className = className;
  icon.setAttribute("aria-hidden", "true");
  setFallback(icon, displayName || targetId);

  const src = targetIconSrc(targetId, iconDataUrl);
  if (!src) return icon;

  const img = document.createElement("img");
  img.src = src;
  img.alt = "";
  img.decoding = "async";
  img.loading = "lazy";
  img.addEventListener("error", () => setFallback(icon, displayName || targetId), { once: true });
  icon.textContent = "";
  icon.append(img);
  return icon;
}

export function isSafeImageDataUrl(value: string): boolean {
  const clean = value.trim().toLowerCase();
  if (value.length > 200_000) return false;
  return clean.startsWith("data:image/png;base64,")
    || clean.startsWith("data:image/jpeg;base64,")
    || clean.startsWith("data:image/jpg;base64,")
    || clean.startsWith("data:image/webp;base64,")
    || clean.startsWith("data:image/svg+xml;base64,");
}

function setFallback(icon: HTMLElement, text: string): void {
  icon.textContent = text.charAt(0).toUpperCase();
}
