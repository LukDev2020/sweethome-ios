import { Router, Request, Response } from "express";
import { authMiddleware } from "../middleware/auth";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";
import { nearbyAlerts, NearbyResult, RADII } from "../services/nearbyAlerts";

const router = Router();
router.use(authMiddleware);

/** Same area (~1 km) and radius within 10 minutes: one set of upstream calls */
const CACHE_MS = 10 * 60 * 1000;
const cache = new Map<string, { at: number; result: NearbyResult }>();

/** For tests */
export function clearNearbyCache(): void { cache.clear(); }

/**
 * GET /v1/nearby/alerts?lat=..&lng=..&radiusKm=30
 * Disasters, traffic and crime around the point (services/nearbyAlerts.ts). The
 * point is rounded to ~1 km before it goes anywhere; nothing is stored.
 */
router.get("/alerts", createRateLimiter(RATE_LIMITS.general), async (req: Request, res: Response) => {
  const lat = Number(req.query.lat);
  const lng = Number(req.query.lng);
  const asked = Number(req.query.radiusKm ?? 30);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    res.status(400).json({ error: "lat and lng are required" });
    return;
  }
  const radiusKm = RADII.includes(asked) ? asked : 30;
  const rLat = Math.round(lat * 100) / 100;
  const rLng = Math.round(lng * 100) / 100;
  const key = `${rLat},${rLng},${radiusKm}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_MS) {
    res.json(hit.result);
    return;
  }
  try {
    // Up to 20: the home shows 3–5, the "all nearby" page the rest
    const result = await nearbyAlerts(rLat, rLng, radiusKm, { tomtomKey: process.env.TOMTOM_API_KEY?.trim() || undefined, limit: 20 });
    if (cache.size > 2000) cache.clear();
    cache.set(key, { at: Date.now(), result });
    res.json(result);
  } catch (error) {
    console.error("[Nearby] alerts error:", error);
    res.status(500).json({ error: "Failed to load nearby alerts" });
  }
});

export default router;
