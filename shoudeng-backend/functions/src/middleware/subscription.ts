import { Request, Response, NextFunction } from "express";
import { getSubscription, PLANS, PLAN_RANK, PlanId } from "../services/payment";
import { effectivePlanId } from "../services/household";

/**
 * Middleware factory that gates a route behind a subscription feature.
 * Returns 403 if the user's plan doesn't include the required feature.
 *
 * Usage: router.post("/generate", authMiddleware, requireFeature("export_pdf"), handler)
 */
export function requireFeature(feature: string) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const uid = req.uid;
    if (!uid) {
      res.status(401).json({ error: "Authentication required" });
      return;
    }

    try {
      const sub = await getSubscription(uid);
      let planId: PlanId = sub.planId;
      let features: readonly string[] = sub.features;
      if (!features.includes(feature)) {
        // A family member's plan covers the whole household (services/household.ts)
        try {
          const household = await effectivePlanId(uid);
          if (PLAN_RANK[household] > PLAN_RANK[planId]) {
            planId = household;
            features = PLANS[household].features;
          }
        } catch (error) {
          console.warn("[Subscription] Household lookup failed, using own plan:", error);
        }
      }
      if (features.includes(feature)) {
        next();
      } else {
        res.status(403).json({
          error: "Feature not available on your current plan",
          feature,
          currentPlan: planId,
          upgrade: true,
        });
      }
    } catch (error) {
      console.error("[Subscription] Feature check failed:", error);
      res.status(500).json({ error: "Failed to check subscription" });
    }
  };
}
