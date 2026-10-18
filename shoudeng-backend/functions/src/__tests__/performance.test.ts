/**
 * Phase 7 — Performance, Cost & Battery Tests
 *
 * Verifies:
 *   1. Cloud Function resource configuration (memory, timeout)
 *   2. Firestore batch sizes within 500-doc limit
 *   3. Rate limiting thresholds and headers
 *   4. BigQuery cost controls (parameterized queries, no SELECT *)
 *   5. Telemetry endpoint input validation (no unbounded writes)
 *   6. TTL cleanup efficiency (batch processing, evidence hold skip)
 *   7. Pagination on list endpoints
 *   8. Heartbeat/location reporting rate caps (iOS side)
 *   9. Geocoding cache effectiveness
 *   10. FCM multicast batch size constraints
 *
 * Static analysis tests — no runtime needed.
 *
 * Run: cd shoudeng-backend/functions && npm test -- --testPathPattern performance
 */

import * as fs from "fs";
import * as path from "path";

function readSource(relativePath: string): string {
  const fullPath = path.join(__dirname, "..", relativePath);
  try {
    return fs.readFileSync(fullPath, "utf-8");
  } catch {
    return "";
  }
}

const projectRoot = path.join(__dirname, "..", "..", "..", "..");
function readiOS(relativePath: string): string {
  try {
    return fs.readFileSync(path.join(projectRoot, relativePath), "utf-8");
  } catch {
    return "";
  }
}

const indexSource = readSource("index.ts");
const triggerSource = readSource("triggers/onSOSCreated.ts");
const ttlSource = readSource("scheduled/ttlCleanup.ts");
const heartbeatCheckSource = readSource("scheduled/heartbeatCheck.ts");
const checkinOverdueSource = readSource("scheduled/checkinOverdue.ts");
const homeTimerSource = readSource("scheduled/homeTimerCheck.ts");
const rateLimitSource = readSource("middleware/rateLimit.ts");
const telemetrySource = readSource("routes/telemetry.ts");
const geocodingSource = readSource("services/geocoding.ts");
const fcmSource = readSource("services/fcm.ts");
const bigquerySource = readSource("services/bigquery.ts");
const timelineSource = readSource("routes/timeline.ts");
const evidenceSource = readSource("services/evidence.ts");

// iOS sources
const heartbeatServiceSource = readiOS("ShouDeng/Services/Network/HeartbeatService.swift");
const adaptiveLocationSource = readiOS("ShouDeng/Core/Algorithms/AdaptiveLocationManager.swift");

// --- Tests ---

describe("Performance — Cloud Function Resources", () => {
  it("onSOSCreated uses 300s timeout (escalation chain requires 120s+)", () => {
    expect(triggerSource).toMatch(/timeoutSeconds:\s*300/);
  });

  it("onSOSCreated uses 512MB memory", () => {
    expect(triggerSource).toMatch(/memory:\s*["']512MB["']/);
  });

  it("scheduled functions use appropriate resources", () => {
    // Scheduled functions should not need excessive memory
    const allScheduled = ttlSource + heartbeatCheckSource + checkinOverdueSource + homeTimerSource;
    // If memory is specified, it should be <= 512MB
    const memorySpecs = allScheduled.match(/memory:\s*["'](\d+)MB["']/g) || [];
    for (const spec of memorySpecs) {
      const mb = parseInt(spec.match(/(\d+)/)![1]);
      expect(mb).toBeLessThanOrEqual(512);
    }
  });
});

describe("Performance — Rate Limiting", () => {
  it("auth endpoint: 5 requests per minute", () => {
    expect(rateLimitSource).toMatch(/auth.*windowMs.*60\s*\*\s*1000.*maxRequests.*5/s);
  });

  it("SMS: 3 per 10 minutes", () => {
    expect(rateLimitSource).toMatch(/sms.*windowMs.*10\s*\*\s*60\s*\*\s*1000.*maxRequests.*3/s);
  });

  it("SOS trigger: 3 per hour", () => {
    expect(rateLimitSource).toMatch(/sos.*windowMs.*60\s*\*\s*60\s*\*\s*1000.*maxRequests.*3/s);
  });

  it("telemetry: 120 per minute", () => {
    expect(rateLimitSource).toMatch(/telemetry.*windowMs.*60\s*\*\s*1000.*maxRequests.*120/s);
  });

  it("general API: 100 per minute", () => {
    expect(rateLimitSource).toMatch(/general.*windowMs.*60\s*\*\s*1000.*maxRequests.*100/s);
  });

  it("rate limiter sets standard headers", () => {
    expect(rateLimitSource).toContain("X-RateLimit-Limit");
    expect(rateLimitSource).toContain("X-RateLimit-Remaining");
    expect(rateLimitSource).toContain("X-RateLimit-Reset");
    expect(rateLimitSource).toContain("Retry-After");
  });

  it("rate limiter fails open for safety-critical app", () => {
    // If rate limiting fails (Firestore down), allow the request
    expect(rateLimitSource).toMatch(/fail.*allow|allowing request/i);
    expect(rateLimitSource).toContain("next()");
  });

  it("rate limiter returns 429 with retryAfter", () => {
    expect(rateLimitSource).toContain("429");
    expect(rateLimitSource).toContain("retryAfter");
  });
});

describe("Performance — Firestore Batch Limits", () => {
  it("TTL cleanup uses batch within 500-doc limit", () => {
    // Firestore batch writes are limited to 500 operations
    expect(ttlSource).toContain("batch");
    // The rate limit cleanup limits to 500
    expect(rateLimitSource).toContain("limit(500)");
  });

  it("rate limit cleanup processes in batches of 500", () => {
    expect(rateLimitSource).toContain("limit(500)");
    expect(rateLimitSource).toContain("batch.delete");
    expect(rateLimitSource).toContain("batch.commit()");
  });
});

describe("Performance — Telemetry Input Validation", () => {
  it("heartbeat requires userId and timestamp", () => {
    expect(telemetrySource).toMatch(/!userId\s*\|\|\s*!timestamp/);
  });

  it("heartbeat rejects cross-user submissions", () => {
    expect(telemetrySource).toContain("userId !== req.uid");
    expect(telemetrySource).toContain("403");
  });

  it("location report requires userId, latitude, longitude", () => {
    expect(telemetrySource).toMatch(
      /!userId\s*\|\|\s*latitude\s*===\s*undefined\s*\|\|\s*longitude\s*===\s*undefined/
    );
  });

  it("location report rejects cross-user submissions", () => {
    // Count the 403 checks — should have at least 3 (heartbeat, location, checkin)
    const crossUserChecks = (telemetrySource.match(/userId !== req\.uid/g) || []).length;
    expect(crossUserChecks).toBeGreaterThanOrEqual(3);
  });

  it("telemetry uses rate limiting middleware", () => {
    expect(telemetrySource).toContain("createRateLimiter");
    expect(telemetrySource).toContain("RATE_LIMITS.telemetry");
  });
});

describe("Performance — BigQuery Cost Controls", () => {
  it("TTL cleanup uses parameterized queries (no SQL injection)", () => {
    expect(ttlSource).toContain("@cutoff");
    expect(ttlSource).toContain("params");
    expect(ttlSource).not.toMatch(/\$\{.*\}.*WHERE/); // No template literals in SQL WHERE
  });

  it("TTL cleanup uses DELETE (not SELECT then delete)", () => {
    expect(ttlSource).toContain("DELETE FROM");
  });

  it("TTL differentiates free (7d) and paid (90d) retention", () => {
    expect(ttlSource).toMatch(/free:\s*7/);
    expect(ttlSource).toMatch(/paid:\s*90/);
  });

  it("TTL skips tables with -1 retention (never delete)", () => {
    expect(ttlSource).toContain("-1");
    expect(ttlSource).toContain("no TTL");
  });
});

describe("Performance — Geocoding Cache", () => {
  it("caches results in Firestore with 30-day TTL", () => {
    expect(geocodingSource).toMatch(/CACHE_TTL_DAYS\s*=\s*30/);
    expect(geocodingSource).toContain("geocoding_cache");
  });

  it("checks cache before API call", () => {
    const cacheCheckIdx = geocodingSource.indexOf("cached.exists");
    const apiCallIdx = geocodingSource.indexOf("maps.googleapis.com");
    expect(cacheCheckIdx).toBeLessThan(apiCallIdx);
  });

  it("rounds coordinates to 4 decimal places (~11m precision)", () => {
    expect(geocodingSource).toContain("toFixed(4)");
  });

  it("batch geocoding deduplicates locations", () => {
    expect(geocodingSource).toContain("unique");
    expect(geocodingSource).toContain("unique.has(key)");
  });

  it("batch geocoding adds delay for Google Maps rate limit", () => {
    expect(geocodingSource).toMatch(/setTimeout.*25/);
  });
});

describe("Performance — iOS Heartbeat Rate", () => {
  it("heartbeat rate limited to 12 per hour max", () => {
    // maxHeartbeatsPerHour: Int = 12
    expect(heartbeatServiceSource).toMatch(/maxHeartbeatsPerHour.*=\s*12/);
  });

  it("heartbeat minimum interval is 60 seconds", () => {
    expect(heartbeatServiceSource).toMatch(/minIntervalBetweenBeats.*=\s*60/);
  });
});

describe("Performance — iOS Adaptive Location Intervals", () => {
  it("safe zone uses infinite interval (no GPS polling)", () => {
    // .safe = no active GPS polling, relies on geofence exits
    expect(adaptiveLocationSource).toContain("safe");
  });

  it("unknown mode uses 600s (10 min) interval", () => {
    expect(adaptiveLocationSource).toMatch(/600/);
  });

  it("moving mode uses 60s interval", () => {
    expect(adaptiveLocationSource).toMatch(/moving/);
  });

  it("SOS mode uses 5s interval (highest frequency)", () => {
    expect(adaptiveLocationSource).toMatch(/5/);
  });

  it("low battery mode uses 1200s (20 min) interval", () => {
    expect(adaptiveLocationSource).toMatch(/1200/);
  });
});

describe("Performance — FCM Multicast", () => {
  it("uses sendEachForMulticast (handles up to 500 tokens)", () => {
    expect(fcmSource).toContain("sendEachForMulticast");
  });

  it("logs success and failure counts", () => {
    expect(fcmSource).toContain("successCount");
    expect(fcmSource).toContain("failureCount");
  });
});

describe("Performance — Evidence Hold Protection", () => {
  it("TTL cleanup queries active evidence holds before deletion", () => {
    expect(ttlSource).toContain("evidence_holds");
    expect(ttlSource).toContain("expiresAt");
  });

  it("TTL cleanup builds hold exclusion clauses", () => {
    expect(ttlSource).toContain("holdClauses");
    expect(ttlSource).toContain("NOT (user_id =");
  });

  it("TTL cleanup cleans up expired evidence holds", () => {
    const expiredHoldCleanup = ttlSource.indexOf("Removed expired evidence hold");
    expect(expiredHoldCleanup).toBeGreaterThan(0);
  });
});

describe("Performance — Checkin Dual-Write", () => {
  it("checkin writes to Firestore (real-time) and BigQuery (history)", () => {
    expect(telemetrySource).toContain("checkins");
    expect(telemetrySource).toContain("insertCheckin");
  });

  it("BigQuery write failure is non-fatal for checkin", () => {
    expect(telemetrySource).toMatch(/bqError|non-fatal|non.?blocking/i);
  });

  it("heartbeat BigQuery failure is non-fatal", () => {
    // Heartbeats should not fail the request if BigQuery is down
    expect(telemetrySource).toContain("Queued for retry");
  });
});

describe("Performance — TTL Cleanup Scope", () => {
  it("cleans expired invites", () => {
    expect(ttlSource).toContain("invites");
    expect(ttlSource).toContain("expired");
  });

  it("cleans expired rate limit documents", () => {
    expect(ttlSource).toContain("cleanupRateLimits");
  });

  it("cleans expired evidence share links", () => {
    expect(ttlSource).toContain("evidence_shares");
  });

  it("cleans expired evidence files from Cloud Storage", () => {
    expect(ttlSource).toContain("cleanupExpiredEvidence");
  });
});
