import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import {
  verifyAppleReceipt,
  upsertSubscription,
  getSubscription,
  handleAppleNotification,
  PLANS,
  PlanId,
} from "../services/payment";

const router = Router();
const db = admin.firestore();

/**
 * GET /v1/payment/plans
 * Get available subscription plans. Public endpoint.
 */
router.get("/plans", (_req: Request, res: Response) => {
  const plans = Object.values(PLANS).map((p) => ({
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
router.get(
  "/subscription",
  authMiddleware,
  async (req: Request, res: Response) => {
    const uid = req.uid!;

    try {
      const sub = await getSubscription(uid);
      res.json(sub);
    } catch (error) {
      console.error("[Payment] get subscription error:", error);
      res.status(500).json({ error: "Failed to get subscription" });
    }
  }
);

/**
 * POST /v1/payment/verify-receipt
 * Verify an Apple App Store receipt and activate subscription.
 * Called by the iOS client after a successful StoreKit 2 purchase.
 */
router.post(
  "/verify-receipt",
  authMiddleware,
  createRateLimiter(RATE_LIMITS.general),
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { signedTransaction, planId } = req.body;

    if (!signedTransaction) {
      res.status(400).json({ error: "signedTransaction is required" });
      return;
    }

    try {
      const result = await verifyAppleReceipt(signedTransaction);

      if (!result.valid) {
        res.status(400).json({ error: result.error || "Invalid receipt" });
        return;
      }

      // Determine plan from product ID or request body
      const resolvedPlanId: PlanId = (planId as PlanId) || mapProductToPlan(result.productId);

      await upsertSubscription({
        userId: uid,
        planId: resolvedPlanId,
        appleOriginalTransactionId: result.originalTransactionId || null,
        appleProductId: result.productId || null,
        expiresDate: result.expiresDate || null,
      });

      const sub = await getSubscription(uid);
      res.json({ success: true, subscription: sub });
    } catch (error) {
      console.error("[Payment] verify receipt error:", error);
      res.status(500).json({ error: "Failed to verify receipt" });
    }
  }
);

/**
 * POST /v1/payment/restore
 * Restore purchases — verify all transactions and activate matching subscription.
 */
router.post(
  "/restore",
  authMiddleware,
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { signedTransactions } = req.body;

    if (!signedTransactions || !Array.isArray(signedTransactions)) {
      res.status(400).json({ error: "signedTransactions array is required" });
      return;
    }

    try {
      let latestValid: {
        planId: PlanId;
        originalTransactionId: string;
        productId: string;
        expiresDate: Date | null;
      } | null = null;

      for (const tx of signedTransactions) {
        const result = await verifyAppleReceipt(tx);
        if (result.valid && result.expiresDate && result.expiresDate > new Date()) {
          const plan = mapProductToPlan(result.productId);
          if (
            !latestValid ||
            (result.expiresDate > (latestValid.expiresDate || new Date(0)))
          ) {
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
        await upsertSubscription({
          userId: uid,
          planId: latestValid.planId,
          appleOriginalTransactionId: latestValid.originalTransactionId,
          appleProductId: latestValid.productId,
          expiresDate: latestValid.expiresDate,
        });
      }

      const sub = await getSubscription(uid);
      res.json({ success: true, subscription: sub, restored: !!latestValid });
    } catch (error) {
      console.error("[Payment] restore error:", error);
      res.status(500).json({ error: "Failed to restore purchases" });
    }
  }
);

/**
 * POST /v1/payment/apple-webhook
 * Apple App Store Server Notification v2 webhook.
 * Apple sends subscription lifecycle events here.
 * NO authentication — Apple signs the payload with JWS.
 */
router.post("/apple-webhook", async (req: Request, res: Response) => {
  const { signedPayload } = req.body;

  if (!signedPayload) {
    res.status(400).json({ error: "signedPayload is required" });
    return;
  }

  try {
    await handleAppleNotification(signedPayload);
    res.json({ success: true });
  } catch (error) {
    console.error("[Payment] webhook error:", error);
    res.status(500).json({ error: "Webhook processing failed" });
  }
});

/**
 * Map Apple product ID to internal plan ID.
 */
function mapProductToPlan(productId?: string): PlanId {
  if (!productId) return "free";

  for (const [planId, plan] of Object.entries(PLANS)) {
    if ("appleProductId" in plan && plan.appleProductId === productId) {
      return planId as PlanId;
    }
  }
  return "free";
}

export default router;
