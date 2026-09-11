import { Request, Response, NextFunction } from "express";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

const db = admin.firestore();
const RATE_LIMIT_COLLECTION = "rate_limits";

interface RateLimitConfig {
  windowMs: number;     // Time window in milliseconds
  maxRequests: number;  // Max requests per window
}

// Rate limit presets
export const RATE_LIMITS = {
  // Auth endpoints: 5 requests per minute (prevent brute force)
  auth: { windowMs: 60 * 1000, maxRequests: 5 },

  // SMS sending: 3 per 10 minutes (prevent SMS bombing)
  sms: { windowMs: 10 * 60 * 1000, maxRequests: 3 },

  // Evidence share (public): 20 per hour per IP
  publicShare: { windowMs: 60 * 60 * 1000, maxRequests: 20 },

  // General API: 100 per minute per user
  general: { windowMs: 60 * 1000, maxRequests: 100 },

  // SOS trigger: 3 per hour (prevent spam)
  sos: { windowMs: 60 * 60 * 1000, maxRequests: 3 },

  // Telemetry: 120 per minute (heartbeats at 12/hr + location bursts)
  telemetry: { windowMs: 60 * 1000, maxRequests: 120 },
} as const;

/**
 * Create a rate limiting middleware for a specific config.
 * Uses Firestore to track request counts (works across Cloud Function instances).
 */
export function createRateLimiter(
  config: RateLimitConfig,
  keyFn?: (req: Request) => string
) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    // Determine the rate limit key (user ID or IP address)
    const key = keyFn
      ? keyFn(req)
      : req.uid || req.ip || req.headers["x-forwarded-for"]?.toString() || "unknown";

    const windowKey = `${key}_${Math.floor(Date.now() / config.windowMs)}`;
    const docRef = db.collection(RATE_LIMIT_COLLECTION).doc(windowKey);

    try {
      const result = await db.runTransaction(async (tx) => {
        const doc = await tx.get(docRef);

        if (!doc.exists) {
          tx.set(docRef, {
            count: 1,
            expiresAt: Timestamp.fromDate(
              new Date(Date.now() + config.windowMs)
            ),
          });
          return { allowed: true, count: 1 };
        }

        const data = doc.data()!;
        const newCount = (data.count || 0) + 1;

        if (newCount > config.maxRequests) {
          return { allowed: false, count: newCount };
        }

        tx.update(docRef, { count: newCount });
        return { allowed: true, count: newCount };
      });

      // Set rate limit headers
      res.set("X-RateLimit-Limit", String(config.maxRequests));
      res.set("X-RateLimit-Remaining", String(Math.max(0, config.maxRequests - result.count)));
      res.set("X-RateLimit-Reset", String(Math.ceil(Date.now() / config.windowMs) * config.windowMs));

      if (!result.allowed) {
        const retryAfter = Math.ceil(config.windowMs / 1000);
        res.set("Retry-After", String(retryAfter));
        res.status(429).json({
          error: "Too many requests",
          retryAfter,
        });
        return;
      }

      next();
    } catch (error) {
      // If rate limiting fails, allow the request (fail-open for safety-critical app)
      console.error("[RateLimit] Check failed, allowing request:", error);
      next();
    }
  };
}

/**
 * Cleanup expired rate limit documents.
 * Called by TTL cleanup scheduled function.
 */
export async function cleanupRateLimits(): Promise<number> {
  const now = Timestamp.now();
  const expired = await db
    .collection(RATE_LIMIT_COLLECTION)
    .where("expiresAt", "<", now)
    .limit(500) // Process in batches
    .get();

  const batch = db.batch();
  expired.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  return expired.size;
}
