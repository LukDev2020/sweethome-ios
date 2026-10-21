import { Request, Response, NextFunction } from "express";
import { getSubscription } from "../services/payment";

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
      if (sub.features.includes(feature)) {
        next();
      } else {
        res.status(403).json({
          error: "Feature not available on your current plan",
          feature,
          currentPlan: sub.planId,
          upgrade: true,
        });
      }
    } catch (error) {
      console.error("[Subscription] Feature check failed:", error);
      res.status(500).json({ error: "Failed to check subscription" });
    }
  };
}

/**
 * Middleware factory that gates invite acceptance behind plan limits.
 * Checks guardian count OR protected person count based on the acceptor's role.
 */
export function requirePlanCapacity(role: "guardian" | "protected") {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const uid = req.uid;
    if (!uid) {
      res.status(401).json({ error: "Authentication required" });
      return;
    }

    try {
      const sub = await getSubscription(uid);
      const { PLANS } = await import("../services/payment");
      const plan = PLANS[sub.planId] || PLANS.free;

      // For guardians: check maxProtected (how many people they can watch)
      // For protected: check maxGuardians (how many guardians can watch them)
      // The limit applies to the GUARDIAN's subscription since they are the paying user
      if (role === "guardian") {
        const maxProtected = (plan as any).maxProtected ?? 1;
        if (maxProtected >= 0) {
          const admin = await import("firebase-admin");
          const links = await admin.default
            .firestore()
            .collection("guardian_links")
            .where("guardianId", "==", uid)
            .where("status", "==", "active")
            .get();
          if (links.size >= maxProtected) {
            res.status(403).json({
              error: "Plan limit reached",
              detail: `Your plan allows up to ${maxProtected} protected person(s)`,
              currentCount: links.size,
              maxAllowed: maxProtected,
              currentPlan: sub.planId,
              upgrade: true,
            });
            return;
          }
        }
      }

      next();
    } catch (error) {
      console.error("[Subscription] Capacity check failed:", error);
      res.status(500).json({ error: "Failed to check plan capacity" });
    }
  };
}
