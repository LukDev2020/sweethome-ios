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
