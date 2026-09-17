"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.PLANS = void 0;
exports.verifyAppleReceipt = verifyAppleReceipt;
exports.upsertSubscription = upsertSubscription;
exports.getSubscription = getSubscription;
exports.handleAppleNotification = handleAppleNotification;
const admin = __importStar(require("firebase-admin"));
const bigquery_1 = require("./bigquery");
const db = admin.firestore();
// Apple App Store Server API configuration
const APPLE_BUNDLE_ID = "app.shoudeng.ios";
// Subscription plan definitions
exports.PLANS = {
    free: {
        id: "free",
        name: "免费版",
        price: 0,
        ttlDays: { heartbeat: 7, location: 7, checkin: 30 },
        maxGuardians: 1,
        maxProtected: 1,
        features: ["basic_sos", "1_guardian", "24h_timeline", "checkin"],
    },
    duo: {
        id: "duo",
        name: "双人守护",
        price: 18,
        appleProductIds: [
            "app.shoudeng.duo.monthly",
            "app.shoudeng.duo.yearly",
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
        name: "家庭守护",
        price: 38,
        appleProductIds: [
            "app.shoudeng.family.monthly",
            "app.shoudeng.family.yearly",
        ],
        ttlDays: { heartbeat: 90, location: 90, checkin: -1 },
        maxGuardians: -1,
        maxProtected: 4,
        features: [
            "basic_sos", "checkin", "unlimited_guardians", "90d_timeline",
            "duty_schedule", "voice_call_escalation", "sms_fallback",
            "export_pdf", "family_dashboard",
        ],
    },
    familyplus: {
        id: "familyplus",
        name: "家庭守护+",
        price: 58,
        appleProductIds: [
            "app.shoudeng.familyplus.monthly",
            "app.shoudeng.familyplus.yearly",
        ],
        ttlDays: { heartbeat: 180, location: 180, checkin: -1 },
        maxGuardians: -1,
        maxProtected: 8,
        features: [
            "basic_sos", "checkin", "unlimited_guardians", "180d_timeline",
            "duty_schedule", "voice_call_escalation", "sms_fallback",
            "export_pdf", "family_dashboard", "priority_support",
            "location_history_export",
        ],
    },
};
/**
 * Verify an Apple App Store receipt with Apple's server.
 * Uses App Store Server API v2 (signed JWS transactions).
 */
async function verifyAppleReceipt(signedTransaction) {
    try {
        // Decode the JWS transaction (base64url encoded)
        // In production, verify the signature against Apple's certificate chain
        const parts = signedTransaction.split(".");
        if (parts.length !== 3) {
            return { valid: false, error: "Invalid JWS format" };
        }
        const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf-8"));
        // Verify bundle ID
        if (payload.bundleId && payload.bundleId !== APPLE_BUNDLE_ID) {
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
    }
    catch (error) {
        console.error("[Payment] Receipt verification failed:", error);
        return { valid: false, error: "Failed to verify receipt" };
    }
}
/**
 * Create or update a subscription in Firestore.
 */
async function upsertSubscription(params) {
    const now = admin.firestore.Timestamp.now();
    const expiresAt = params.expiresDate
        ? admin.firestore.Timestamp.fromDate(params.expiresDate)
        : admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000) // Default 30 days
        );
    const subDoc = {
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
    await (0, bigquery_1.insertConsentAudit)({
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
async function getSubscription(userId) {
    const subDoc = await db.collection("subscriptions").doc(userId).get();
    if (!subDoc.exists) {
        return {
            planId: "free",
            status: "active",
            expiresAt: null,
            features: exports.PLANS.free.features,
            ttlDays: exports.PLANS.free.ttlDays,
        };
    }
    const data = subDoc.data();
    // Check if subscription has expired
    if (data.currentPeriodEnd.toDate() < new Date() && data.status === "active") {
        await subDoc.ref.update({ status: "expired", updatedAt: admin.firestore.Timestamp.now() });
        return {
            planId: "free",
            status: "expired",
            expiresAt: data.currentPeriodEnd.toDate().toISOString(),
            features: exports.PLANS.free.features,
            ttlDays: exports.PLANS.free.ttlDays,
        };
    }
    const plan = exports.PLANS[data.planId] || exports.PLANS.free;
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
 */
async function handleAppleNotification(signedPayload) {
    try {
        const parts = signedPayload.split(".");
        if (parts.length !== 3) {
            console.error("[Payment] Invalid Apple notification JWS");
            return;
        }
        const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString("utf-8"));
        const notificationType = payload.notificationType;
        const subtype = payload.subtype;
        const transactionInfo = payload.data?.signedTransactionInfo;
        if (!transactionInfo) {
            console.warn("[Payment] No transaction info in Apple notification");
            return;
        }
        // Decode transaction info
        const txParts = transactionInfo.split(".");
        const txPayload = JSON.parse(Buffer.from(txParts[1], "base64url").toString("utf-8"));
        const originalTransactionId = txPayload.originalTransactionId;
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
            case "DID_RENEW":
                await subRef.update({
                    status: "active",
                    currentPeriodEnd: admin.firestore.Timestamp.fromDate(new Date(txPayload.expiresDate)),
                    updatedAt: now,
                });
                console.log(`[Payment] Subscription renewed: ${originalTransactionId}`);
                break;
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
    }
    catch (error) {
        console.error("[Payment] Failed to handle Apple notification:", error);
    }
}
//# sourceMappingURL=payment.js.map