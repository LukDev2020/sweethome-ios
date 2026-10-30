/** Languages the backend can speak to a user (push, SMS, voice). */
export type Lang = "en" | "zh" | "fr";

/** "zh-Hans" / "zh_CN" / "fr-CA" / "en" → Lang; anything else → null. */
export function normalizeLocale(v: unknown): Lang | null {
  if (typeof v !== "string") return null;
  const p = v.trim().toLowerCase().slice(0, 2);
  return p === "en" || p === "zh" || p === "fr" ? p : null;
}

/** Stored user locale, defaulting to Chinese (the app's original market). */
export function userLang(user: { locale?: unknown } | undefined | null): Lang {
  return normalizeLocale(user?.locale) ?? "zh";
}
