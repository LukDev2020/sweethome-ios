import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { isValidTimeZone } from "../services/localTime";
import { normalizeLocale } from "../services/locale";
import { eraseAccount, exportAccount } from "../services/accountData";
import { recordDataTransferConsent, parseConsentRecords, latestConsentVersions } from "../services/consent";
import { insertConsentAudit } from "../services/bigquery";
import { appAccountTokenFor } from "../services/payment";

import { riderProfileUpdates, riderProfileView, ProfileFieldError } from "../services/riderProfile";

const router = Router();
const db = admin.firestore();

// All user routes require authentication
// Mounted at /v1/user AND bare /v1 (diagnostics): auth is per route, never router.use.

/**
 * GET /v1/user/me
 * Get current user's profile.
 */
router.get("/me", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      res.status(404).json({ error: "User not found" });
      return;
    }

    const data = userDoc.data()!;
    // Lets App Store notifications find this account by the purchase's appAccountToken
    const appAccountToken = appAccountTokenFor(uid);
    if (data.appAccountToken !== appAccountToken) {
      userDoc.ref.update({ appAccountToken }).catch((e) =>
        console.error("[User] could not store appAccountToken:", e));
    }
    res.json({
      id: uid,
      displayName: data.displayName,
      role: data.role,
      avatarInitial: data.avatarInitial,
      email: data.email || null,
      timeZone: data.timeZone,
      countryCode: data.countryCode,
      cityName: data.cityName,
      createdAt: data.createdAt.toDate().toISOString(),
      publicKey: data.publicKey || null,
      dataTransferConsentVersion: data.dataTransferConsentVersion || null,
      // Why they use the app, which home they see, rider setup (survives a new phone)
      ...riderProfileView(data),
    });
  } catch (error) {
    console.error("[User] get profile error:", error);
    res.status(500).json({ error: "Failed to fetch profile" });
  }
});

/**
 * PUT /v1/user/me
 * Update current user's profile.
 */
router.put("/me", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { displayName, email, timeZone, cityName, countryCode, publicKey, role, locale } = req.body;

  const updates: Record<string, unknown> = {
    updatedAt: admin.firestore.Timestamp.now(),
  };

  if (role !== undefined) {
    if (!["protected", "guardian"].includes(role)) {
      res.status(400).json({ error: "Role must be 'protected' or 'guardian'" });
      return;
    }
    updates.role = role;
  }
  if (displayName !== undefined) {
    if (typeof displayName !== "string" || displayName.length > 100) {
      res.status(400).json({ error: "displayName must be a string of 100 characters or less" });
      return;
    }
    updates.displayName = displayName;
    updates.avatarInitial = displayName.charAt(0);
  }
  if (email !== undefined) {
    if (typeof email !== "string" || email.length > 200 || (email.length > 0 && !email.includes("@"))) {
      res.status(400).json({ error: "Invalid email format" });
      return;
    }
    updates.email = email;
  }
  if (timeZone !== undefined) {
    if (!isValidTimeZone(timeZone)) {
      res.status(400).json({ error: "timeZone must be an IANA time zone, e.g. Asia/Shanghai" });
      return;
    }
    updates.timeZone = timeZone;
  }
  if (locale !== undefined) {
    // Language for pushes, SMS and voice calls sent to this user
    const lang = normalizeLocale(locale);
    if (!lang) {
      res.status(400).json({ error: "locale must be one of en, zh, zh-Hant, fr, ja" });
      return;
    }
    updates.locale = lang;
  }
  if (cityName !== undefined) {
    if (typeof cityName !== "string" || cityName.length > 100) {
      res.status(400).json({ error: "cityName must be a string of 100 characters or less" });
      return;
    }
    updates.cityName = cityName;
  }
  if (countryCode !== undefined) {
    if (typeof countryCode !== "string" || countryCode.length > 10) {
      res.status(400).json({ error: "countryCode must be a string of 10 characters or less" });
      return;
    }
    updates.countryCode = countryCode;
  }
  try {
    Object.assign(updates, riderProfileUpdates(req.body ?? {}));
  } catch (e) {
    if (e instanceof ProfileFieldError) {
      res.status(400).json({ error: e.message });
      return;
    }
    throw e;
  }
  if (publicKey !== undefined) {
    if (typeof publicKey !== "string" || publicKey.length > 200) {
      res.status(400).json({ error: "publicKey must be a base64 string of 200 characters or less" });
      return;
    }
    updates.publicKey = publicKey;
  }

  try {
    // The first rider setup date stays (the onboarding funnel counts from it)
    if (updates["riderProfile.onboardedAt"]) {
      const existing = (await db.collection("users").doc(uid).get()).data()?.riderProfile?.onboardedAt;
      if (existing) delete updates["riderProfile.onboardedAt"];
    }
    await db.collection("users").doc(uid).update(updates);
    res.json({ success: true });
  } catch (error) {
    console.error("[User] update profile error:", error);
    res.status(500).json({ error: "Failed to update profile" });
  }
});

/**
 * PUT /v1/user/notification-preferences
 * Save notification preferences to server (for push filtering).
 */
router.put("/notification-preferences", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;
  // Only boolean fields that were sent are updated (field paths), so an older
  // client that doesn't know a preference can't wipe it.
  const keys = ["sosAlerts", "sosCriticalAlerts", "checkinReminder", "checkinOverdue", "familyFeed"];
  const updates: Record<string, unknown> = {};
  for (const key of keys) {
    if (typeof req.body?.[key] === "boolean") updates[`notificationPrefs.${key}`] = req.body[key];
  }

  try {
    await db.collection("users").doc(uid).update({
      ...updates,
      updatedAt: admin.firestore.Timestamp.now(),
    });
    res.json({ success: true });
  } catch (error) {
    console.error("[User] update notification prefs error:", error);
    res.status(500).json({ error: "Failed to update notification preferences" });
  }
});

/**
 * POST /v1/user/consent
 * Record consent shown in the app. Two shapes:
 *  - { type: "cross_border_transfer", version } — the data-location prompt
 *  - { records: [{ item, copyVersion, action, at, appVersion, locale, deviceId }] } —
 *    taps logged on the phone (first-launch disclaimers, Terms agreement, feature
 *    disclosures, guardian duties), up to 100 per call. Kept in consent_audit, which
 *    account deletion keeps on purpose; the latest versions are also on the user doc.
 */
router.post("/consent", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;
  const body = req.body ?? {};

  if (Array.isArray(body.records)) {
    const records = parseConsentRecords(body.records);
    if (!records) {
      res.status(400).json({ error: "records must be 1–100 valid consent records" });
      return;
    }
    try {
      await Promise.all(records.map((r) => insertConsentAudit({
        userId: uid,
        consentType: r.item,
        action: r.action,
        grantedTo: "lantern-care",
        detail: `copy ${r.copyVersion}; shown ${r.at}; app ${r.appVersion}; locale ${r.locale}`,
        deviceInfo: r.deviceId,
      })));
      const latest = latestConsentVersions(records);
      if (Object.keys(latest).length > 0) {
        await db.collection("users").doc(uid).set(latest, { merge: true });
      }
      res.json({ success: true, recorded: records.length });
    } catch (error) {
      // The phone keeps the records and sends them again
      console.error("[User] consent records error:", error);
      res.status(500).json({ error: "Failed to record consent" });
    }
    return;
  }

  const { type, version } = body;
  if (type !== "cross_border_transfer" || typeof version !== "string" || version.length === 0 || version.length > 20) {
    res.status(400).json({ error: "type must be cross_border_transfer and version a short string" });
    return;
  }
  try {
    await db.collection("users").doc(uid).set({
      dataTransferConsentVersion: version,
      dataTransferConsentAt: admin.firestore.Timestamp.now(),
    }, { merge: true });
    await recordDataTransferConsent(uid, version, "prompt");
    res.json({ success: true });
  } catch (error) {
    console.error("[User] consent error:", error);
    res.status(500).json({ error: "Failed to record consent" });
  }
});

/**
 * POST /v1/user/delete
 * Delete user account and all associated data (GDPR right to erasure).
 * This is irreversible.
 */
router.post("/delete", authMiddleware, createRateLimiter(RATE_LIMITS.accountDelete), async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    // Everything except consent_audit and evidence_holds (see services/accountData.ts)
    const { bigQueryComplete } = await eraseAccount(uid);

    // Delete Firebase Auth account
    try {
      await admin.auth().deleteUser(uid);
    } catch (authError) {
      console.warn(`[User] Failed to delete auth account for ${uid}:`, authError);
    }

    if (!bigQueryComplete) {
      console.log(`[User] BigQuery history for ${uid} queued for deletion (streaming buffer)`);
    }
    console.log(`[User] Account deleted: ${uid}`);
    res.json({ success: true });
  } catch (error) {
    console.error("[User] delete account error:", error);
    res.status(500).json({ error: "Failed to delete account" });
  }
});

/**
 * POST /v1/user/export
 * Full data export (data portability). Returns all user data as JSON;
 * the app saves it as a file the user can keep or share.
 */
router.post("/export", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const exportData = await exportAccount(uid);
    res.json(exportData);
  } catch (error) {
    console.error("[User] export error:", error);
    res.status(500).json({ error: "Failed to export data" });
  }
});

/**
 * POST /v1/diagnostics/crash
 * Receive crash reports from iOS client.
 */
router.post("/diagnostics/crash", authMiddleware, async (req: Request, res: Response) => {
  try {
    await db.collection("crash_reports").add({
      ...req.body,
      userId: req.uid,
      receivedAt: admin.firestore.Timestamp.now(),
    });
    res.json({ success: true });
  } catch (error) {
    console.error("[Diagnostics] crash report error:", error);
    res.status(500).json({ error: "Failed to store crash report" });
  }
});

export default router;
