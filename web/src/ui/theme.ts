export type AppTheme = "auto" | "eink";

const STORAGE_KEY = "vibecast.theme.v1";

export function normalizeTheme(value: string | null | undefined): AppTheme {
  return value === "eink" ? "eink" : "auto";
}

export function readTheme(storage: Storage = localStorage): AppTheme {
  try {
    return normalizeTheme(storage.getItem(STORAGE_KEY));
  } catch {
    return "auto";
  }
}

export function writeTheme(theme: AppTheme, storage: Storage = localStorage): void {
  try {
    storage.setItem(STORAGE_KEY, theme);
  } catch {
    // Private browsing or full storage should not block the UI toggle.
  }
}

export function applyTheme(theme: AppTheme, root: HTMLElement = document.documentElement): void {
  if (theme === "eink") {
    root.dataset.theme = "eink";
  } else {
    delete root.dataset.theme;
  }
}
