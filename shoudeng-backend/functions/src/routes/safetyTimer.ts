import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { setSafetyTimer, SafetyTimerError } from "../services/safetyTimer";

/**
 * Safety timer deadline kept on the server (see services/safetyTimer.ts).
 *   POST /v1/safety-timer   (the phone sends it through its offline queue; PUT works too)
 *     { deadline: ISO 8601 | null, clientSOSId?, latitude?, longitude?, batteryLevel? }
 *     deadline = start / extend / resume; null = checked in / cancelled / paused
 *     → { active, deadline? }
 */
const router = Router();
router.use(authMiddleware);

const handler = async (req: Request, res: Response) => {
  try {
    res.json(await setSafetyTimer(req.uid!, req.body ?? {}));
  } catch (e) {
    if (e instanceof SafetyTimerError) {
      res.status(e.status).json({ error: e.message });
      return;
    }
    console.error("[SafetyTimer] update failed:", e);
    res.status(500).json({ error: "Failed to update the safety timer" });
  }
};
router.post("/", createRateLimiter(RATE_LIMITS.telemetry), handler);
router.put("/", createRateLimiter(RATE_LIMITS.telemetry), handler);

export default router;
