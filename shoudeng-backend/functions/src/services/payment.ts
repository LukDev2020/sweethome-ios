import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import * as fs from "fs";
import * as path from "path";
import { SignedDataVerifier, Environment } from "@apple/app-store-server-library";
import { insertConsentAudit } from "./bigquery";

const db = admin.firestore();

// Apple App Store Server API configuration
// Must equal PRODUCT_BUNDLE_IDENTIFIER of the ShouDeng target in project.yml.
export const APPLE_BUNDLE_ID = "com.shoudeng.app";

// Apple App ID from App Store Connect (numeric). Set via environment config.
const APPLE_APP_ID = Number(process.env.APPLE_APP_ID || "0");

// Load Apple Root CA certificates (DER-encoded) for JWS signature verification.
// Downloaded from https://www.apple.com/certificateauthority/
function loadAppleRootCerts(): Buffer[] {
  const certsDir = path.join(__dirname, "..", "certs");
  const certFiles = [
    "AppleIncRootCertificate.cer",
    "AppleRootCA-G2.cer",
    "AppleRootCA-G3.cer",
  ];
  const certs: Buffer[] = [];
  for (const file of certFiles) {
    const fullPath = path.join(certsDir, file);
    if (fs.existsSync(fullPath)) {
      certs.push(fs.readFileSync(fullPath));
    }
  }
  return certs;
}

const appleRootCerts = loadAppleRootCerts();

// Determine environment from Firebase config
const appleEnvironment =
  process.env.APPLE_ENVIRONMENT === "Production"
    ? Environment.PRODUCTION
    : Environment.SANDBOX;

// Create verifier instance (reused across requests)
let _verifier: SignedDataVerifier | null = null;
function getVerifier(): SignedDataVerifier | null {
  if (appleRootCerts.length === 0) {
    console.warn("[Payment] Apple root certs not found — signature verification disabled");
    return null;
  }
  if (!_verifier) {
    _verifier = new SignedDataVerifier(
      appleRootCerts,
      true,                // enable online checks (OCSP)
      appleEnvironment,
      APPLE_BUNDLE_ID,
      APPLE_APP_ID,
    );
  }
  return _verifier;
}

// Subscription plan definitions — single source of truth for plan IDs.
// Product IDs must match App Store Connect and StoreKitManager.productIds (iOS).
// Prices are reference values only; App Store Connect pricing is authoritative.
export const PLANS = {
  free: {
    id: "free",
    name: "免费版",
    prices: { monthly: { CNY: 0, USD: 0 }, yearly: { CNY: 0, USD: 0 } },
    ttlDays: { heartbeat: 7, location: 7, checkin: 30 },
    maxGuardians: 1,
    maxProtected: 1,
    features: ["basic_sos", "1_guardian", "24h_timeline", "checkin"],
  },
  single: {
    id: "single",
    name: "单人关注版",
    prices: { monthly: { CNY: 10, USD: 1.49 }, yearly: { CNY: 96, USD: 14.99 } },
    appleProductIds: [
      "com.shoudeng.app.single.monthly",
      "com.shoudeng.app.single.yearly",
    ],
    ttlDays: { heartbeat: 90, location: 90, checkin: -1 },
    maxGuardians: 3,
    maxProtected: 1,
    features: [
      "basic_sos", "checkin", "3_guardians", "90d_timeline",
      "duty_schedule", "voice_call_escalation", "export_pdf",
    ],
  },
  family: {
    id: "family",
    name: "家庭版",
    prices: { monthly: { CNY: 30, USD: 4.99 }, yearly: { CNY: 288, USD: 49.99 } },
    appleProductIds: [
      "com.shoudeng.app.family.monthly",
      "com.shoudeng.app.family.yearly",
    ],
    ttlDays: { heartbeat: 180, location: 180, checkin: -1 },
    maxGuardians: -1,
    maxProtected: 4,
    features: [
      "basic_sos", "checkin", "unlimited_guardians", "180d_timeline",
      "duty_schedule", "voice_call_escalation", "sms_fallback",
      "export_pdf", "family_dashboard", "location_history_export",
    ],
  },
  ultimate: {
    id: "ultimate",
    name: "企业版",
    prices: { monthly: { CNY: 128, USD: 19.99 }, yearly: { CNY: 1228, USD: 199.99 } },
    appleProductIds: [
      "com.shoudeng.app.ultimate.monthly",
      "com.shoudeng.app.ultimate.yearly",
    ],
    ttlDays: { heartbeat: 365, location: 365, checkin: -1 },
    maxGuardians: -1,
    maxProtected: -1,
    features: [
      "basic_sos", "checkin", "unlimited_guardians", "unlimited_protected",
      "365d_timeline", "duty_schedule", "voice_call_escalation", "sms_fallback",
      "export_pdf", "family_dashboard", "location_history_export",
      "priority_support",
    ],
  },
} as const;

export type PlanId = keyof typeof PLANS;

/**
 * Map an App Store product ID to its plan. Returns null for unknown products.
 */
export function mapProductToPlan(productId: string | undefined): PlanId | null {
  if (!productId) return null;
  for (const [planId, plan] of Object.entries(PLANS)) {
    if ("appleProductIds" in plan && (plan.appleProductIds as readonly string[]).includes(productId)) {
      return planId as PlanId;
    }
  }
  return null;
}

export interface SubscriptionDoc {
  userId: string;
  planId: PlanId;
  appleOriginalTransactionId: string | null;
  appleProductId: string | null;
  status: "active" | "expired" | "cancelled" | "grace_period" | "billing_retry";
  currentPeriodStart: FirebaseFirestore.Timestamp;
  currentPeriodEnd: FirebaseFirestore.Timestamp;
  cancelledAt: FirebaseFirestore.Timestamp | null;
  autoRenew: boolean;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

/**
 * Verify an Apple App Store signed transaction (JWS).
 * Uses Apple's official library to verify the certificate chain and signature.
 * Falls back to payload-only verification if certs are unavailable (dev/test).
 */
export async function verifyAppleReceipt(signedTransaction: string): Promise<{
  valid: boolean;
  productId?: string;
  originalTransactionId?: string;
  expiresDate?: Date;
  error?: string;
}> {
  try {
    const parts = signedTransaction.split(".");
    if (parts.length !== 3) {
      return { valid: false, error: "Invalid JWS format" };
    }

    const verifier = getVerifier();

    if (verifier) {
      // Full cryptographic verification: signature + certificate chain + OCSP
      const decoded = await verifier.verifyAndDecodeTransaction(signedTransaction);
      return {
        valid: true,
        productId: decoded.productId,
        originalTransactionId: decoded.originalTransactionId,
        expiresDate: decoded.expiresDate
          ? new Date(decoded.expiresDate)
          : undefined,
      };
    }

    // Fallback: payload-only verification (dev/test when certs not loaded)
    console.warn("[Payment] Using payload-only verification (no cert chain)");
    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf-8")
    );

    if (payload.bundleId !== APPLE_BUNDLE_ID) {
      return { valid: false, error: "Bundle ID mismatch" };
    }

    return {
      valid: true,
      productId: payload.productId,
      originalTransactionId: payload.originalTransactionId,
      expiresDate: payload.expiresDate
        ? new Date(payload.expiresDate)
        : undefined,
    };
  } catch (error) {
    console.error("[Payment] Receipt verification failed:", error);
    return { valid: false, error: "Failed to verify receipt" };
  }
}

/**
 * Create or update a subscription in Firestore.
 */
export async function upsertSubscription(params: {
  userId: string;
  planId: PlanId;
  appleOriginalTransactionId: string | null;
  appleProductId: string | null;
  expiresDate: Date | null;
}): Promise<void> {
  const now = admin.firestore.Timestamp.now();
  const expiresAt = params.expiresDate
    ? admin.firestore.Timestamp.fromDate(params.expiresDate)
    : admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // Default 30 days
      );

  const subDoc: SubscriptionDoc = {
    userId: params.userId,
    planId: params.planId,
    appleOriginalTransactionId: params.appleOriginalTransactionId,
    appleProductId: params.appleProductId,
    status: "active",
    currentPeriodStart: now,
    currentPeriodEnd: expiresAt,
    cancelledAt: null,
    autoRenew: true,
    createdAt: now,
    updatedAt: now,
  };

  await db.collection("subscriptions").doc(params.userId).set(subDoc, { merge: true });

  // Log consent audit
  await insertConsentAudit({
    userId: params.userId,
    consentType: "subscription",
    action: "granted",
    grantedTo: "system",
    detail: `Subscription activated: ${params.planId}`,
  });
}

/**
 * Get the active subscription for a user.
 * Returns the plan details or defaults to free tier.
 */
export async function getSubscription(userId: string): Promise<{
  planId: PlanId;
  status: string;
  expiresAt: string | null;
  features: readonly string[];
  ttlDays: { heartbeat: number; location: number; checkin: number };
}> {
  const subDoc = await db.collection("subscriptions").doc(userId).get();

  if (!subDoc.exists) {
    return {
      planId: "free",
      status: "active",
      expiresAt: null,
      features: PLANS.free.features,
      ttlDays: PLANS.free.ttlDays,
    };
  }

  const data = subDoc.data() as SubscriptionDoc;

  // Check if subscription has expired
  if (data.currentPeriodEnd.toDate() < new Date() && data.status === "active") {
    await subDoc.ref.update({ status: "expired", updatedAt: admin.firestore.Timestamp.now() });
    return {
      planId: "free",
      status: "expired",
      expiresAt: data.currentPeriodEnd.toDate().toISOString(),
      features: PLANS.free.features,
      ttlDays: PLANS.free.ttlDays,
    };
  }

  const plan = PLANS[data.planId] || PLANS.free;

  return {
    planId: data.planId,
    status: data.status,
    expiresAt: data.currentPeriodEnd.toDate().toISOString(),
    features: plan.features,
    ttlDays: plan.ttlDays,
  };
}

/**
 * Handle Apple App Store Server Notification v2.
 * Called by the webhook endpoint when Apple sends subscription lifecycle events.
 * Verifies the notification JWS signature before processing.
 */
export async function handleAppleNotification(signedPayload: string): Promise<void> {
  try {
    const verifier = getVerifier();
    let payload: Record<string, unknown>;

    if (verifier) {
      // Cryptographic verification of Apple's webhook notification
      const decoded = await verifier.verifyAndDecodeNotification(signedPayload);
      payload = decoded as unknown as Record<string, unknown>;
    } else {
      // Fallback for dev/test
      const parts = signedPayload.split(".");
      if (parts.length !== 3) {
        console.error("[Payment] Invalid Apple notification JWS");
        return;
      }
      payload = JSON.parse(
        Buffer.from(parts[1], "base64url").toString("utf-8")
      );
    }

    const notificationType = payload.notificationType as string;
    const subtype = payload.subtype as string | undefined;
    const data = payload.data as Record<string, unknown> | undefined;
    const transactionInfo = data?.signedTransactionInfo as string | undefined;

    if (!transactionInfo) {
      console.warn("[Payment] No transaction info in Apple notification");
      return;
    }

    // Decode and verify the nested transaction JWS
    let txPayload: Record<string, unknown>;
    if (verifier) {
      const decodedTx = await verifier.verifyAndDecodeTransaction(transactionInfo);
      txPayload = decodedTx as unknown as Record<string, unknown>;
    } else {
      const txParts = transactionInfo.split(".");
      txPayload = JSON.parse(
        Buffer.from(txParts[1], "base64url").toString("utf-8")
      );
    }

    const originalTransactionId = txPayload.originalTransactionId as string;

    // Find subscription by original transaction ID
    const subSnapshot = await db
      .collection("subscriptions")
      .where("appleOriginalTransactionId", "==", originalTransactionId)
      .limit(1)
      .get();

    if (subSnapshot.empty) {
      console.warn(`[Payment] No subscription found for tx ${originalTransactionId}`);
      return;
    }

    const subRef = subSnapshot.docs[0].ref;
    const now = admin.firestore.Timestamp.now();

    switch (notificationType) {
      case "DID_RENEW": {
        const renewedPlan = mapProductToPlan(txPayload.productId as string);
        await subRef.update({
          ...(renewedPlan ? { planId: renewedPlan, appleProductId: txPayload.productId } : {}),
          status: "active",
          currentPeriodEnd: admin.firestore.Timestamp.fromDate(
            new Date(txPayload.expiresDate as number)
          ),
          updatedAt: now,
        });
        console.log(`[Payment] Subscription renewed: ${originalTransactionId}`);
        break;
      }

      case "DID_CHANGE_RENEWAL_STATUS":
        await subRef.update({
          autoRenew: subtype !== "AUTO_RENEW_DISABLED",
          updatedAt: now,
        });
        break;

      case "EXPIRED":
        await subRef.update({
          status: "expired",
          updatedAt: now,
        });
        console.log(`[Payment] Subscription expired: ${originalTransactionId}`);
        break;

      case "GRACE_PERIOD_EXPIRED":
        await subRef.update({
          status: "expired",
          updatedAt: now,
        });
        break;

      case "DID_FAIL_TO_RENEW":
        await subRef.update({
          status: subtype === "GRACE_PERIOD" ? "grace_period" : "billing_retry",
          updatedAt: now,
        });
        break;

      case "REFUND":
        await subRef.update({
          status: "cancelled",
          cancelledAt: now,
          updatedAt: now,
        });
        console.log(`[Payment] Subscription refunded: ${originalTransactionId}`);
        break;

      default:
        console.log(`[Payment] Unhandled notification: ${notificationType}`);
    }
  } catch (error) {
    console.error("[Payment] Failed to handle Apple notification:", error);
  }
}
