import { insertConsentAudit } from "./bigquery";

/** Bump when the data-location wording in the app changes; users are asked again. */
export const DATA_TRANSFER_CONSENT_VERSION = "2026-10-31";

/** Consent to storage and processing in the United States (Google Cloud us-central1, Twilio). */
export async function recordDataTransferConsent(uid: string, version: string, source: string): Promise<void> {
  try {
    await insertConsentAudit({
      userId: uid,
      consentType: "cross_border_transfer",
      action: "granted",
      grantedTo: "us-central1",
      detail: `version ${version} via ${source}`,
    });
  } catch (error) {
    // The user doc already holds the version; the audit row is best-effort
    console.error("[Consent] audit write failed:", error);
  }
}

// ---------------------------------------------------------------------------
// Consent taps logged on the phone (POST /v1/user/consent { records })
// ---------------------------------------------------------------------------

export interface ConsentRecordInput {
  item: string;
  copyVersion: string;
  action: "granted" | "denied" | "revoked";
  at: string;
  appVersion: string;
  locale: string;
  deviceId: string;
}

const ITEM = /^[a-z0-9_.]{1,64}$/;
const short = (v: unknown, max: number): string | null =>
  typeof v === "string" && v.length > 0 && v.length <= max ? v : null;

/** Validates a batch from the app; null if anything is off (the app resends). */
export function parseConsentRecords(raw: unknown[]): ConsentRecordInput[] | null {
  if (raw.length === 0 || raw.length > 100) return null;
  const out: ConsentRecordInput[] = [];
  for (const r of raw) {
    if (typeof r !== "object" || r === null) return null;
    const o = r as Record<string, unknown>;
    const item = typeof o.item === "string" && ITEM.test(o.item) ? o.item : null;
    const copyVersion = short(o.copyVersion, 20);
    const action = o.action === "granted" || o.action === "denied" || o.action === "revoked" ? o.action : null;
    const at = typeof o.at === "string" && !Number.isNaN(Date.parse(o.at)) ? new Date(o.at).toISOString() : null;
    if (!item || !copyVersion || !action || !at) return null;
    out.push({
      item, copyVersion, action, at,
      appVersion: short(o.appVersion, 20) ?? "unknown",
      locale: short(o.locale, 20) ?? "unknown",
      deviceId: short(o.deviceId, 64) ?? "unknown",
    });
  }
  return out;
}

/** The newest version the user agreed to, per document, for the user doc. */
export function latestConsentVersions(records: ConsentRecordInput[]): Record<string, string> {
  const fields: Record<string, string> = {};
  const set = (field: string, r: ConsentRecordInput) => {
    fields[field] = r.copyVersion;
    fields[`${field}At`] = r.at;
  };
  for (const r of [...records].sort((a, b) => a.at.localeCompare(b.at))) {
    if (r.action !== "granted") continue;
    if (r.item === "terms.accept") set("termsVersion", r);
    else if (r.item === "guardian.duty") set("guardianDutyVersion", r);
    else if (r.item.startsWith("onboard.")) set("onboardingCopyVersion", r);
  }
  return fields;
}
