import { Request, Response, NextFunction } from "express";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

const db = admin.firestore();
const RATE_LIMIT_COLLECTION = "rate_limits";

interface RateLimitConfig {
  /** Namespace for the counter — limits never share a bucket. */
  name: string;
  windowMs: number;     // Time window in milliseconds
  maxRequests: number;  // Max requests per window
  /**
   * If the limiter itself fails (Firestore unavailable): reject when true
   * (brute-force protection on auth/SMS), allow when false (everything else —
   * a safety app must not drop requests because of its own limiter).
   */
  failClosed?: boolean;
}

// Rate limit presets
export const RATE_LIMITS = {
  // Auth endpoints: 5 requests per minute (prevent brute force)
  auth: { name: "auth", windowMs: 60 * 1000, maxRequests: 5, failClosed: true },

  // Account deletion: rare, destructive
  accountDelete: { name: "accountDelete", windowMs: 60 * 1000, maxRequests: 5 },

  // SMS sending: 3 per 10 minutes (prevent SMS bombing)
  sms: { name: "sms", windowMs: 10 * 60 * 1000, maxRequests: 3, failClosed: true },

  // Evidence share (public): 20 per hour per IP
  publicShare: { name: "publicShare", windowMs: 60 * 60 * 1000, maxRequests: 20 },

  // General API: 100 per minute per user
  general: { name: "general", windowMs: 60 * 1000, maxRequests: 100 },

  // Invite preview / accept: 30 per 10 minutes per user. Codes are short, and
  // the preview shows the inviter's name, so guessing must stay expensive.
  invite: { name: "invite", windowMs: 10 * 60 * 1000, maxRequests: 30 },

  // SOS trigger: its own generous bucket. Trigger is idempotent while an SOS is
  // active, so this only bounds trigger→resolve→trigger loops (Twilio cost);
  // a second real emergency in the same hour must still go through.
  sosTrigger: { name: "sosTrigger", windowMs: 60 * 60 * 1000, maxRequests: 20 },

  // Client-requested voice calls (each one costs money and rings a phone)
  voiceCall: { name: "voiceCall", windowMs: 60 * 60 * 1000, maxRequests: 10 },

  // Telemetry: 120 per minute (heartbeats at 12/hr + location bursts)
  telemetry: { name: "telemetry", windowMs: 60 * 1000, maxRequests: 120 },

  // Incident reports: heavy (BigQuery + Firestore over up to 7 days), rarely needed
  incidentReport: { name: "incidentReport", windowMs: 60 * 60 * 1000, maxRequests: 10 },

  // Public Twilio callbacks, per caller IP
  webhook: { name: "webhook", windowMs: 60 * 1000, maxRequests: 120 },
} as const;

export function rateLimitDocId(config: RateLimitConfig, key: string, now = Date.now()): string {
  // Firestore doc ids cannot contain "/"
  const safeKey = key.replace(/\//g, "_");
  return `${config.name}:${safeKey}:${Math.floor(now / config.windowMs)}`;
}

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

    const docRef = db.collection(RATE_LIMIT_COLLECTION).doc(rateLimitDocId(config, key));

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
      if (config.failClosed) {
        console.error(`[RateLimit] ${config.name} check failed, rejecting (fail-closed):`, error);
        res.status(503).json({ error: "Please try again shortly" });
        return;
      }
      // Fail open everywhere else — a safety app must not drop requests
      console.error(`[RateLimit] ${config.name} check failed, allowing request:`, error);
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
