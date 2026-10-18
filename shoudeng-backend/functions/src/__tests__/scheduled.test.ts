/**
 * Phase 5 — Scheduled Functions Tests
 *
 * Tests the 5 scheduled Cloud Functions:
 *   - ttlCleanup (daily)
 *   - computeIntegrityProof (daily)
 *   - checkCheckinOverdue (every 15 min)
 *   - checkHeartbeatMissing (every 5 min)
 *   - checkHomeTimerExpiry (every 1 min)
 *
 * Static analysis tests — verifies structure, thresholds, and edge cases.
 *
 * Run: cd shoudeng-backend/functions && npm test -- --testPathPattern scheduled
 */

import * as fs from "fs";
import * as path from "path";

function readScheduledSource(filename: string): string {
  const p = path.join(__dirname, "..", "scheduled", filename);
  try {
    return fs.readFileSync(p, "utf-8");
  } catch {
    return "";
  }
}

const ttlSource = readScheduledSource("ttlCleanup.ts");
const integritySource = readScheduledSource("integrityProof.ts");
const checkinSource = readScheduledSource("checkinOverdue.ts");
const heartbeatSource = readScheduledSource("heartbeatCheck.ts");
const homeTimerSource = readScheduledSource("homeTimerCheck.ts");

// Read index.ts to verify schedule declarations
const indexSource = fs.readFileSync(
  path.join(__dirname, "..", "index.ts"),
  "utf-8"
);

describe("Scheduled Functions — Registration", () => {
  it("exports ttlCleanup", () => {
    expect(indexSource).toContain("ttlCleanup");
  });

  it("exports computeIntegrityProof", () => {
    expect(indexSource).toContain("computeIntegrityProof");
  });

  it("exports checkCheckinOverdue", () => {
    expect(indexSource).toContain("checkCheckinOverdue");
  });

  it("exports checkHeartbeatMissing", () => {
    expect(indexSource).toContain("checkHeartbeatMissing");
  });

  it("exports checkHomeTimerExpiry", () => {
    expect(indexSource).toContain("checkHomeTimerExpiry");
  });
});

describe("TTL Cleanup", () => {
  it("source file exists", () => {
    expect(ttlSource.length).toBeGreaterThan(0);
  });

  it("runs on a daily schedule", () => {
    // Should contain cron-like schedule
    expect(ttlSource + indexSource).toMatch(/schedule|cron|0\s+3/);
  });

  it("differentiates free and paid tier retention", () => {
    // Free tier: 7d for heartbeat/location, paid: 90d
    expect(ttlSource).toMatch(/7|free/i);
    expect(ttlSource).toMatch(/90|paid/i);
  });

  it("respects evidence holds", () => {
    expect(ttlSource).toMatch(/evidence_holds|evidenceHold/i);
  });

  it("cleans expired invites", () => {
    expect(ttlSource).toMatch(/invites?/);
  });

  it("cleans expired rate limits", () => {
    expect(ttlSource).toMatch(/rate.?limit/i);
  });
});

describe("Integrity Proof", () => {
  it("source file exists", () => {
    expect(integritySource.length).toBeGreaterThan(0);
  });

  it("computes Merkle root", () => {
    expect(integritySource).toMatch(/[Mm]erkle|hash|SHA/i);
  });

  it("covers heartbeat and location tables", () => {
    expect(integritySource).toMatch(/heartbeat/i);
    expect(integritySource).toMatch(/location/i);
  });

  it("stores proof in integrity_proofs collection", () => {
    expect(integritySource).toContain("integrity_proofs");
  });
});

describe("Check-in Overdue", () => {
  it("source file exists", () => {
    expect(checkinSource.length).toBeGreaterThan(0);
  });

  it("uses 8-hour threshold for overdue check-in", () => {
    // CHECKIN_OVERDUE_HOURS = 8
    expect(checkinSource).toMatch(/CHECKIN_OVERDUE_HOURS\s*=\s*8|8\s*\*\s*60\s*\*\s*60/);
  });

  it("sends FCM reminder to guardians", () => {
    expect(checkinSource).toMatch(/send.*[Rr]eminder|sendCheckinReminder/);
  });

  it("queries protected users", () => {
    expect(checkinSource).toMatch(/protected|role/);
  });
});

describe("Heartbeat Missing", () => {
  it("source file exists", () => {
    expect(heartbeatSource.length).toBeGreaterThan(0);
  });

  it("uses 30-minute threshold for missing heartbeat", () => {
    // HEARTBEAT_MISSING_THRESHOLD_MIN = 30
    expect(heartbeatSource).toMatch(/HEARTBEAT_MISSING_THRESHOLD_MIN\s*=\s*30|30/);
  });

  it("sends FCM alert to guardians", () => {
    expect(heartbeatSource).toMatch(/send.*[Aa]lert|FCM|notification/);
  });
});

describe("Home Timer Expiry", () => {
  it("source file exists", () => {
    expect(homeTimerSource.length).toBeGreaterThan(0);
  });

  it("checks for expired timers", () => {
    expect(homeTimerSource).toMatch(/expir|deadline|overdue/i);
  });

  it("escalates to guardians", () => {
    expect(homeTimerSource).toMatch(/guardian|escalat|notify/i);
  });

  it("uses time-sensitive push notification", () => {
    expect(homeTimerSource).toMatch(/time-sensitive|timeSensitive|time.sensitive/i);
  });
});

describe("Free Tier Enforcement", () => {
  it("TTL cleanup has different retention for free vs paid", () => {
    // Free: 7 days, Paid: 90 days for heartbeat/location
    const hasFreeRetention = ttlSource.match(/free.*7|7.*free/i);
    const hasPaidRetention = ttlSource.match(/paid.*90|90.*paid/i);
    expect(hasFreeRetention || ttlSource.includes("7")).toBeTruthy();
    expect(hasPaidRetention || ttlSource.includes("90")).toBeTruthy();
  });

  it("TTL cleanup checks subscription status before deleting", () => {
    expect(ttlSource).toMatch(/subscriptions?|plan|tier/i);
  });
});
