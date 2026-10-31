/** Languages the backend can speak to a user (push, SMS, voice). */
export type Lang = "en" | "zh" | "zh-Hant" | "fr" | "ja";

/** "zh-Hans" / "zh_CN" / "zh-Hant-HK" / "fr-CA" / "ja-JP" / "en" → Lang; anything else → null. */
export function normalizeLocale(v: unknown): Lang | null {
  if (typeof v !== "string") return null;
  const t = v.trim().toLowerCase().replace(/_/g, "-");
  const p = t.slice(0, 2);
  if (p === "zh") {
    // Hong Kong, Macao, Taiwan → Traditional Chinese
    return /hant|^zh-(tw|hk|mo)/.test(t) ? "zh-Hant" : "zh";
  }
  return p === "en" || p === "fr" || p === "ja" ? p : null;
}

/** Stored user locale, defaulting to Chinese (the app's original market). */
export function userLang(user: { locale?: unknown } | undefined | null): Lang {
  return normalizeLocale(user?.locale) ?? "zh";
}

/**
 * Best guess when only a phone number is known (verification SMS before sign-up).
 * Mainland China → zh; Hong Kong, Macao, Taiwan → zh-Hant; Japan → ja;
 * France → fr; everything else (incl. the other App Store markets) → en.
 */
export function localeFromPhone(phone: string): Lang {
  const p = phone.replace(/[^+\d]/g, "");
  if (p.startsWith("+86")) return "zh";
  if (["+852", "+853", "+886"].some((c) => p.startsWith(c))) return "zh-Hant";
  if (p.startsWith("+81")) return "ja";
  if (p.startsWith("+33")) return "fr";
  return "en";
}
