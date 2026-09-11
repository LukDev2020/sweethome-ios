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
exports.RATE_LIMITS = void 0;
exports.createRateLimiter = createRateLimiter;
exports.cleanupRateLimits = cleanupRateLimits;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const db = admin.firestore();
const RATE_LIMIT_COLLECTION = "rate_limits";
// Rate limit presets
exports.RATE_LIMITS = {
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
};
/**
 * Create a rate limiting middleware for a specific config.
 * Uses Firestore to track request counts (works across Cloud Function instances).
 */
function createRateLimiter(config, keyFn) {
    return async (req, res, next) => {
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
                        expiresAt: firestore_1.Timestamp.fromDate(new Date(Date.now() + config.windowMs)),
                    });
                    return { allowed: true, count: 1 };
                }
                const data = doc.data();
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
        }
        catch (error) {
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
async function cleanupRateLimits() {
    const now = firestore_1.Timestamp.now();
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
//# sourceMappingURL=rateLimit.js.map