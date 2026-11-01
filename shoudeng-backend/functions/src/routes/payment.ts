import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import {
  verifyAppleReceipt,
  applyTransaction,
  claimSubscription,
  ensureAppAccountToken,
  getSubscription,
  handleAppleNotification,
  mapProductToPlan,
  AppleVerificationError,
  VerifiedReceipt,
  PLANS,
} from "../services/payment";

const router = Router();

/**
 * GET /v1/payment/plans
 * Get available subscription plans. Public endpoint.
 */
router.get("/plans", (_req: Request, res: Response) => {
  const plans = Object.values(PLANS).map((p) => ({
    id: p.id,
    name: p.name,
    prices: p.prices,
    appleProductIds: "appleProductIds" in p ? p.appleProductIds : [],
    maxGuardians: p.maxGuardians,
    maxProtected: p.maxProtected,
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

/** 409 body when the Apple subscription already unlocks another account. */
const OWNED_ELSEWHERE = {
  error: "This App Store subscription is already linked to another account",
  code: "SUBSCRIPTION_OWNED_BY_OTHER_ACCOUNT",
};

/** At most this many JWS per restore call (one subscription group → normally 1). */
const MAX_RESTORE_TRANSACTIONS = 20;

/**
 * POST /v1/payment/verify-receipt
 * Verify an Apple App Store signed transaction and activate the subscription.
 * Called by the iOS client after a successful StoreKit 2 purchase or renewal.
 */
router.post(
  "/verify-receipt",
  authMiddleware,
  createRateLimiter(RATE_LIMITS.general),
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { signedTransaction } = req.body;

    if (!signedTransaction || typeof signedTransaction !== "string") {
      res.status(400).json({ error: "signedTransaction is required" });
      return;
    }

    try {
      await ensureAppAccountToken(uid);
      const result = await verifyAppleReceipt(signedTransaction);

      if (!result.valid || !result.transaction) {
        res.status(result.retryable ? 503 : 400).json({ error: result.error || "Invalid receipt" });
        return;
      }

      // Plan comes only from the signed product ID — never from the client
      const resolvedPlanId = mapProductToPlan(result.productId);
      if (!resolvedPlanId) {
        res.status(400).json({ error: "Unknown product" });
        return;
      }

      const claim = await claimSubscription(uid, result.transaction);
      if (!claim.ok) {
        res.status(409).json(OWNED_ELSEWHERE);
        return;
      }

      await applyTransaction({ userId: uid, transaction: result.transaction, environment: result.environment });

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
 * Sync the App Store's current entitlements (Transaction.currentEntitlements JWS) to
 * the server. Called by the app at login and after "Restore Purchases".
 */
router.post(
  "/restore",
  authMiddleware,
  createRateLimiter(RATE_LIMITS.general),
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { signedTransactions } = req.body;

    if (!signedTransactions || !Array.isArray(signedTransactions)) {
      res.status(400).json({ error: "signedTransactions array is required" });
      return;
    }
    if (signedTransactions.length > MAX_RESTORE_TRANSACTIONS) {
      res.status(400).json({ error: `At most ${MAX_RESTORE_TRANSACTIONS} transactions` });
      return;
    }

    try {
      await ensureAppAccountToken(uid);
      const now = new Date();
      let best: VerifiedReceipt | null = null;
      let ownedElsewhere = 0;

      for (const jws of signedTransactions) {
        if (typeof jws !== "string") continue;
        const result = await verifyAppleReceipt(jws);
        if (!result.valid || !result.transaction || !mapProductToPlan(result.productId)) continue;
        // Refunded/revoked or lapsed transactions don't restore anything
        if (result.revocationDate || !result.expiresDate || result.expiresDate <= now) continue;
        const claim = await claimSubscription(uid, result.transaction);
        if (!claim.ok) {
          ownedElsewhere++;
          continue;
        }
        if (!best || result.expiresDate > (best.expiresDate as Date)) best = result;
      }

      if (best?.transaction) {
        await applyTransaction({ userId: uid, transaction: best.transaction, environment: best.environment });
      } else if (ownedElsewhere > 0) {
        res.status(409).json(OWNED_ELSEWHERE);
        return;
      }

      const sub = await getSubscription(uid);
      res.json({ success: true, subscription: sub, restored: !!best });
    } catch (error) {
      console.error("[Payment] restore error:", error);
      res.status(500).json({ error: "Failed to restore purchases" });
    }
  }
);

/**
 * POST /v1/payment/apple-webhook
 * Apple App Store Server Notification V2 webhook (Production and Sandbox URL).
 * NO authentication — Apple signs the payload with JWS.
 * Non-2xx answers make Apple retry, so verification failures are not acknowledged.
 */
router.post("/apple-webhook", async (req: Request, res: Response) => {
  const { signedPayload } = req.body;

  if (!signedPayload || typeof signedPayload !== "string") {
    res.status(400).json({ error: "signedPayload is required" });
    return;
  }

  try {
    const result = await handleAppleNotification(signedPayload);
    res.json({ success: true, outcome: result.outcome });
  } catch (error) {
    if (error instanceof AppleVerificationError) {
      res.status(error.retryable ? 503 : 401).json({ error: "Notification could not be verified" });
      return;
    }
    console.error("[Payment] webhook error:", error);
    res.status(500).json({ error: "Webhook processing failed" });
  }
});

export default router;
