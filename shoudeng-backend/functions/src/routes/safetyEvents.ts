import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { reportFall, SafetyEventError } from "../services/safetyEvents";

/**
 * Safety events (see services/safetyEvents.ts).
 *   POST /v1/safety-events/fall
 *     { clientEventId, clientSOSId?, outcome: "pending"|"dismissed"|"escalated"|"help_requested",
 *       detectedAt?, countdownSec?, latitude?, longitude?, accuracy?, batteryLevel?,
 *       metrics?: { peakImpactG, freeFallMs, orientationChangeDeg, stillnessVariance, detector },
 *       respondedAfterSec?, sosEventId? }
 *     → { outcome, sosEventId }   (the outcome the server holds)
 */
const router = Router();
router.use(authMiddleware);

router.post("/fall", createRateLimiter(RATE_LIMITS.telemetry), async (req: Request, res: Response) => {
  try {
    res.json(await reportFall(req.uid!, req.body ?? {}));
  } catch (e) {
    if (e instanceof SafetyEventError) {
      res.status(e.status).json({ error: e.message });
      return;
    }
    console.error("[Fall] report failed:", e);
    res.status(500).json({ error: "Failed to record the fall" });
  }
});

export default router;
