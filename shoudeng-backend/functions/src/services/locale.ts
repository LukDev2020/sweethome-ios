/** Languages the backend can speak to a user (push, SMS, voice). */
export type Lang = "en" | "zh" | "zh-Hant" | "fr";

/** "zh-Hans" / "zh_CN" / "zh-Hant-HK" / "fr-CA" / "en" → Lang; anything else → null. */
export function normalizeLocale(v: unknown): Lang | null {
  if (typeof v !== "string") return null;
  const t = v.trim().toLowerCase().replace(/_/g, "-");
  const p = t.slice(0, 2);
  if (p === "zh") {
    // Hong Kong, Macao, Taiwan → Traditional Chinese
    return /hant|^zh-(tw|hk|mo)/.test(t) ? "zh-Hant" : "zh";
  }
  return p === "en" || p === "fr" ? p : null;
}

/** Stored user locale, defaulting to Chinese (the app's original market). */
export function userLang(user: { locale?: unknown } | undefined | null): Lang {
  return normalizeLocale(user?.locale) ?? "zh";
}
