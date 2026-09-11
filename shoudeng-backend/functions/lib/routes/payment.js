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
const express_1 = require("express");
const admin = __importStar(require("firebase-admin"));
const auth_1 = require("../middleware/auth");
const rateLimit_1 = require("../middleware/rateLimit");
const payment_1 = require("../services/payment");
const router = (0, express_1.Router)();
const db = admin.firestore();
/**
 * GET /v1/payment/plans
 * Get available subscription plans. Public endpoint.
 */
router.get("/plans", (_req, res) => {
    const plans = Object.values(payment_1.PLANS).map((p) => ({
        id: p.id,
        name: p.name,
        price: p.price,
        appleProductId: "appleProductId" in p ? p.appleProductId : null,
        features: p.features,
    }));
    res.json(plans);
});
/**
 * GET /v1/payment/subscription
 * Get current user's subscription status.
 */
router.get("/subscription", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    try {
        const sub = await (0, payment_1.getSubscription)(uid);
        res.json(sub);
    }
    catch (error) {
        console.error("[Payment] get subscription error:", error);
        res.status(500).json({ error: "Failed to get subscription" });
    }
});
/**
 * POST /v1/payment/verify-receipt
 * Verify an Apple App Store receipt and activate subscription.
 * Called by the iOS client after a successful StoreKit 2 purchase.
 */
router.post("/verify-receipt", auth_1.authMiddleware, (0, rateLimit_1.createRateLimiter)(rateLimit_1.RATE_LIMITS.general), async (req, res) => {
    const uid = req.uid;
    const { signedTransaction, planId } = req.body;
    if (!signedTransaction) {
        res.status(400).json({ error: "signedTransaction is required" });
        return;
    }
    try {
        const result = await (0, payment_1.verifyAppleReceipt)(signedTransaction);
        if (!result.valid) {
            res.status(400).json({ error: result.error || "Invalid receipt" });
            return;
        }
        // Determine plan from product ID or request body
        const resolvedPlanId = planId || mapProductToPlan(result.productId);
        await (0, payment_1.upsertSubscription)({
            userId: uid,
            planId: resolvedPlanId,
            appleOriginalTransactionId: result.originalTransactionId || null,
            appleProductId: result.productId || null,
            expiresDate: result.expiresDate || null,
        });
        const sub = await (0, payment_1.getSubscription)(uid);
        res.json({ success: true, subscription: sub });
    }
    catch (error) {
        console.error("[Payment] verify receipt error:", error);
        res.status(500).json({ error: "Failed to verify receipt" });
    }
});
/**
 * POST /v1/payment/restore
 * Restore purchases — verify all transactions and activate matching subscription.
 */
router.post("/restore", auth_1.authMiddleware, async (req, res) => {
    const uid = req.uid;
    const { signedTransactions } = req.body;
    if (!signedTransactions || !Array.isArray(signedTransactions)) {
        res.status(400).json({ error: "signedTransactions array is required" });
        return;
    }
    try {
        let latestValid = null;
        for (const tx of signedTransactions) {
            const result = await (0, payment_1.verifyAppleReceipt)(tx);
            if (result.valid && result.expiresDate && result.expiresDate > new Date()) {
                const plan = mapProductToPlan(result.productId);
                if (!latestValid ||
                    (result.expiresDate > (latestValid.expiresDate || new Date(0)))) {
                    latestValid = {
                        planId: plan,
                        originalTransactionId: result.originalTransactionId || "",
                        productId: result.productId || "",
                        expiresDate: result.expiresDate,
                    };
                }
            }
        }
        if (latestValid) {
            await (0, payment_1.upsertSubscription)({
                userId: uid,
                planId: latestValid.planId,
                appleOriginalTransactionId: latestValid.originalTransactionId,
                appleProductId: latestValid.productId,
                expiresDate: latestValid.expiresDate,
            });
        }
        const sub = await (0, payment_1.getSubscription)(uid);
        res.json({ success: true, subscription: sub, restored: !!latestValid });
    }
    catch (error) {
        console.error("[Payment] restore error:", error);
        res.status(500).json({ error: "Failed to restore purchases" });
    }
});
/**
 * POST /v1/payment/apple-webhook
 * Apple App Store Server Notification v2 webhook.
 * Apple sends subscription lifecycle events here.
 * NO authentication — Apple signs the payload with JWS.
 */
router.post("/apple-webhook", async (req, res) => {
    const { signedPayload } = req.body;
    if (!signedPayload) {
        res.status(400).json({ error: "signedPayload is required" });
        return;
    }
    try {
        await (0, payment_1.handleAppleNotification)(signedPayload);
        res.json({ success: true });
    }
    catch (error) {
        console.error("[Payment] webhook error:", error);
        res.status(500).json({ error: "Webhook processing failed" });
    }
});
/**
 * Map Apple product ID to internal plan ID.
 */
function mapProductToPlan(productId) {
    if (!productId)
        return "free";
    for (const [planId, plan] of Object.entries(payment_1.PLANS)) {
        if ("appleProductId" in plan && plan.appleProductId === productId) {
            return planId;
        }
    }
    return "free";
}
exports.default = router;
//# sourceMappingURL=payment.js.map