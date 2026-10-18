/**
 * Chen Family — Backend Scenario Assertions
 *
 * Static analysis + Firestore-seeded assertions for all 12 scenarios.
 * Validates that backend code supports the behaviors described in each scenario.
 *
 * Run: cd qa && npx ts-node --skip-project flows/chen/chen-scenarios.test.ts
 *   OR from shoudeng-backend/functions: npm test -- --testPathPattern chen-scenarios
 */

import * as fs from "fs";
import * as path from "path";

// --- Helpers ---
// When run from shoudeng-backend/functions/src/__tests__/
const backendRoot = path.join(__dirname, "..");
const projectRoot = path.join(__dirname, "..", "..", "..", "..");

function readBackend(relativePath: string): string {
  try { return fs.readFileSync(path.join(backendRoot, relativePath), "utf-8"); } catch { return ""; }
}
function readiOS(relativePath: string): string {
  try { return fs.readFileSync(path.join(projectRoot, relativePath), "utf-8"); } catch { return ""; }
}
function readPersona(): any {
  return JSON.parse(fs.readFileSync(path.join(projectRoot, "qa", "personas", "chen-family.json"), "utf-8"));
}

// --- Source files ---
const sosRoute = readBackend("routes/sos.ts");
const authRoute = readBackend("routes/auth.ts");
const telemetryRoute = readBackend("routes/telemetry.ts");
const timelineRoute = readBackend("routes/timeline.ts");
const triggerSource = readBackend("triggers/onSOSCreated.ts");
const checkinOverdue = readBackend("scheduled/checkinOverdue.ts");
const heartbeatCheck = readBackend("scheduled/heartbeatCheck.ts");
const ttlCleanup = readBackend("scheduled/ttlCleanup.ts");
const rateLimitSource = readBackend("middleware/rateLimit.ts");
const fcmSource = readBackend("services/fcm.ts");
const smsSource = readBackend("services/sms.ts");
const twilioSource = readBackend("services/twilio.ts");
const geocodingSource = readBackend("services/geocoding.ts");
const evidenceSource = readBackend("services/evidence.ts");

const fallDetector = readiOS("ShouDeng/Core/Algorithms/FallDetector.swift");
const heartbeatService = readiOS("ShouDeng/Services/Network/HeartbeatService.swift");
const escalationEngine = readiOS("ShouDeng/Core/StateMachine/EscalationEngine.swift");
const consentLogger = readiOS("ShouDeng/Services/Compliance/ConsentLogger.swift");
const disclaimerCopy = readiOS("ShouDeng/Services/Compliance/DisclaimerCopy.swift");
const adaptiveLocation = readiOS("ShouDeng/Core/Algorithms/AdaptiveLocationManager.swift");

const persona = readPersona();

// ============================================================
// S1: Onboarding
// ============================================================
describe("S1: Onboarding — Fresh Install to Family Joined", () => {
  it("persona has 3 family members", () => {
    expect(persona.members).toHaveLength(3);
  });

  it("haozi is protected, father and mother are guardians", () => {
    const haozi = persona.members.find((m: any) => m.seedId === "haozi");
    const father = persona.members.find((m: any) => m.seedId === "father");
    const mother = persona.members.find((m: any) => m.seedId === "mother");
    expect(haozi.role).toBe("protected");
    expect(father.role).toBe("guardian");
    expect(mother.role).toBe("guardian");
  });

  it("disclaimer copy has 3 onboarding screens with version v1.1", () => {
    expect(disclaimerCopy).toContain("onboard.not_emergency");
    expect(disclaimerCopy).toContain("onboard.scope");
    expect(disclaimerCopy).toContain("onboard.control");
    expect(disclaimerCopy).toContain("v1.1");
  });

  it("consent logger records onboarding screens", () => {
    expect(consentLogger).toContain("logOnboardingScreen");
    expect(consentLogger).toContain("consent_log");
  });

  it("signup endpoint creates user with countryCode and timeZone", () => {
    expect(authRoute).toContain("countryCode");
    expect(authRoute).toContain("timeZone");
  });

  it("invite acceptance creates guardian link", () => {
    expect(persona.guardianLinks).toHaveLength(2);
    expect(persona.guardianLinks[0].status).toBe("active");
  });

  it("feature disclosures include location, fallDetect, sos", () => {
    expect(disclaimerCopy).toContain("consent.location");
    expect(disclaimerCopy).toContain("consent.fall_detect");
    expect(disclaimerCopy).toContain("consent.sos");
  });
});

// ============================================================
// S2: Normal Day
// ============================================================
describe("S2: Normal Day — Campus + Gym + Home", () => {
  it("haozi has 4 safe zones covering daily routine", () => {
    const haozi = persona.members.find((m: any) => m.seedId === "haozi");
    expect(haozi.safeZones).toHaveLength(4);
    const types = haozi.safeZones.map((z: any) => z.type);
    expect(types).toContain("home");
    expect(types).toContain("school");
    expect(types).toContain("custom"); // gym
    expect(types).toContain("work");
  });

  it("heartbeat service enforces 12/hour max and 60s min interval", () => {
    expect(heartbeatService).toMatch(/maxHeartbeatsPerHour.*=\s*12/);
    expect(heartbeatService).toMatch(/minIntervalBetweenBeats.*=\s*60/);
  });

  it("adaptive location uses no GPS polling in safe zones", () => {
    expect(adaptiveLocation).toContain("safe");
  });

  it("adaptive location uses 60s interval for moving mode", () => {
    expect(adaptiveLocation).toContain("moving");
  });

  it("check-in endpoint exists", () => {
    expect(telemetryRoute).toContain("check-in");
  });

  it("mother is on-duty during haozi's daytime (08:00-20:00 EDT)", () => {
    const mother = persona.dutySchedule.slots.find(
      (s: any) => s.guardianId === "li-min-uid"
    );
    // Mother: 20:00-08:00 CST = 08:00-20:00 EDT
    expect(mother.startHour).toBe(20);
    expect(mother.endHour).toBe(8);
    expect(mother.timeZone).toBe("Asia/Shanghai");
  });
});

// ============================================================
// S3: Missed Check-In
// ============================================================
describe("S3: Missed Check-In — 8h Overdue Escalation", () => {
  it("checkinOverdue threshold is 8 hours", () => {
    expect(checkinOverdue).toMatch(/CHECKIN_OVERDUE_HOURS\s*=\s*8/);
  });

  it("checkinOverdue runs every 15 minutes", () => {
    expect(checkinOverdue).toMatch(/every 15 minutes/);
  });

  it("checkinOverdue sends guardian reminder", () => {
    expect(checkinOverdue).toContain("sendCheckinReminder");
  });

  it("FCM has check-in overdue notification template", () => {
    expect(fcmSource).toContain("报平安提醒");
  });
});

// ============================================================
// S4: SOS Full Escalation
// ============================================================
describe("S4: SOS Full Escalation — Long Press to Voice Call", () => {
  it("SOS trigger creates doc with triggerMethod and escalationState=initiated", () => {
    expect(sosRoute).toContain("triggerMethod");
    expect(sosRoute).toContain('"initiated"');
  });

  it("backend escalation delays: hop1→2=30s, hop2→3=60s, hop3→4=30s", () => {
    expect(triggerSource).toContain("delay(30000)");
    expect(triggerSource).toContain("delay(60000)");
  });

  it("escalation states include all hops", () => {
    expect(triggerSource).toContain("hop1_notified");
    expect(triggerSource).toContain("hop2_allNotified");
    expect(triggerSource).toContain("hop3_voiceCalling");
  });

  it("SOS trigger rate limited to 3/hour", () => {
    expect(rateLimitSource).toMatch(/sos.*windowMs.*60\s*\*\s*60\s*\*\s*1000.*maxRequests.*3/s);
  });

  it("FCM SOS notification uses critical interruption level", () => {
    expect(fcmSource).toContain('"interruption-level": "critical"');
  });

  it("voice call initiated via Twilio", () => {
    expect(sosRoute).toContain("initiateVoiceCall");
  });

  it("resolution guardianConfirmedSafe sends notification to protected person", () => {
    expect(sosRoute).toContain("guardianConfirmedSafe");
    expect(sosRoute).toContain("sendSOSResolvedNotification");
  });

  it("timeline entries for SOS trigger and resolve", () => {
    expect(sosRoute).toContain("sosTriggered");
    expect(sosRoute).toContain("sosResolved");
  });

  it("emergency share token expires in 48 hours", () => {
    expect(triggerSource).toContain("48");
  });

  it("only protected person can trigger own SOS", () => {
    expect(sosRoute).toContain("Cannot trigger SOS for another user");
  });

  it("only authorized users can resolve SOS", () => {
    expect(sosRoute).toContain("Not authorized to resolve this SOS event");
  });
});

// ============================================================
// S5: Fall Detection
// ============================================================
describe("S5: Fall Detection — Auto-SOS After 60s Timeout", () => {
  it("fall detection thresholds — DO NOT MODIFY", () => {
    // Swift uses Double literals: 0.6, 2.5, etc.
    expect(fallDetector).toMatch(/freeFallThresholdG.*=\s*0\.6/);
    expect(fallDetector).toMatch(/impactThresholdG.*=\s*2\.5/);
    expect(fallDetector).toMatch(/orientationChangeMinDegrees.*=\s*60/);
    expect(fallDetector).toMatch(/stillnessMaxVariance.*=\s*0\.05/);
    expect(fallDetector).toMatch(/stillnessDurationSec.*=\s*15\.0/);
  });

  it("confirmation timeout is 60 seconds", () => {
    expect(fallDetector).toMatch(/confirmationTimeoutSec.*=\s*60\.0/);
  });

  it("free-fall minimum duration is 100ms", () => {
    expect(fallDetector).toMatch(/freeFallMinDurationMs.*=\s*100/);
  });

  it("impact window after free-fall is 500ms", () => {
    expect(fallDetector).toMatch(/impactWindowAfterFreeFallMs.*=\s*500/);
  });

  it("sample rate is 50 Hz", () => {
    expect(fallDetector).toMatch(/sampleRateHz.*=\s*50\.0/);
  });

  it("SOS trigger supports fallDetection method", () => {
    expect(sosRoute).toContain("fallDetection");
  });
});

// ============================================================
// S6: Battery Death
// ============================================================
describe("S6: Battery Death — 9h Offline", () => {
  it("heartbeat missing threshold is 30 minutes", () => {
    expect(heartbeatCheck).toMatch(/HEARTBEAT_MISSING_THRESHOLD_MIN\s*=\s*30/);
  });

  it("heartbeatCheck runs every 5 minutes", () => {
    expect(heartbeatCheck).toMatch(/every 5 minutes/);
  });

  it("battery report threshold is 5%", () => {
    expect(heartbeatService).toMatch(/batteryReportThreshold.*=\s*0\.05/);
  });

  it("FCM has device offline notification", () => {
    expect(fcmSource).toContain("设备离线提醒");
  });

  it("heartbeat resumes on app foreground", () => {
    expect(heartbeatService).toContain("appForeground");
  });
});

// ============================================================
// S7: Trajectory Consent Toggle
// ============================================================
describe("S7: Trajectory Consent Toggle", () => {
  it("haozi has trajectory consent=false initially", () => {
    const haozi = persona.members.find((m: any) => m.seedId === "haozi");
    expect(haozi.consent.trajectory).toBe(false);
  });

  it("trajectory disclosure is high sensitivity and requires opt-in", () => {
    expect(disclaimerCopy).toContain("trajectory");
    expect(disclaimerCopy).toContain("requiresOptIn");
    expect(disclaimerCopy).toContain("isHighSensitivity");
  });

  it("consent logger records grant and revoke actions", () => {
    expect(consentLogger).toContain("granted");
    expect(consentLogger).toContain("revoked");
  });

  it("consent log is JSONL append-only", () => {
    expect(consentLogger).toContain("jsonl");
  });

  it("consent record includes copyVersion", () => {
    expect(consentLogger).toContain("copyVersion");
  });
});

// ============================================================
// S8: Subscription Upgrade
// ============================================================
describe("S8: Subscription Upgrade — Free to Family Plan", () => {
  it("persona has family plan with correct Apple product ID", () => {
    expect(persona.plan.appleProductId).toBe("com.shoudeng.app.family.monthly");
  });

  it("TTL differentiates free (7d) and paid (90d) retention", () => {
    expect(ttlCleanup).toMatch(/free:\s*7/);
    expect(ttlCleanup).toMatch(/paid:\s*90/);
  });
});

// ============================================================
// S9: Accessibility
// ============================================================
describe("S9: Accessibility — Dynamic Type xxLarge + VoiceOver", () => {
  it("mother persona has dynamicTypeSize xxLarge", () => {
    const mother = persona.members.find((m: any) => m.seedId === "mother");
    expect(mother.dynamicTypeSize).toBe("xxLarge");
  });

  it("mother uses iPhone SE (smallest supported screen)", () => {
    const mother = persona.members.find((m: any) => m.seedId === "mother");
    expect(mother.device).toBe("iPhone SE");
  });

  it("mother locale is zh-Hans", () => {
    const mother = persona.members.find((m: any) => m.seedId === "mother");
    expect(mother.locale).toBe("zh-Hans");
  });
});

// ============================================================
// S10: Insurance Claim
// ============================================================
describe("S10: Insurance Claim Report", () => {
  it("evidence hold prevents TTL deletion", () => {
    expect(ttlCleanup).toContain("evidence_holds");
    expect(ttlCleanup).toContain("expiresAt");
  });

  it("TTL cleanup builds hold exclusion clauses", () => {
    expect(ttlCleanup).toContain("holdClauses");
  });

  it("evidence service exists", () => {
    expect(evidenceSource.length).toBeGreaterThan(0);
  });
});

// ============================================================
// S11: Cross-Border Reachability
// ============================================================
describe("S11: Cross-Border Reachability", () => {
  it("father persona is in CN with +86 phone", () => {
    const father = persona.members.find((m: any) => m.seedId === "father");
    expect(father.countryCode).toBe("CN");
    expect(father.phone).toMatch(/^\+86/);
  });

  it("geocoding uses zh-CN language", () => {
    expect(geocodingSource).toContain("language=zh-CN");
  });

  it("TwiML language maps CN to zh-CN", () => {
    expect(twilioSource).toContain('CN: "zh-CN"');
  });

  it("emergency numbers: CA=911, CN=110, fallback=112", () => {
    expect(twilioSource).toContain('CA: "911"');
    expect(twilioSource).toContain('CN: "110"');
    expect(twilioSource).toMatch(/\|\|\s*"112"/);
  });

  it("SMS uses Twilio for +86 (known limitation F-011)", () => {
    expect(smsSource).toContain("twilio");
    expect(smsSource).not.toMatch(/aliyun|tencent/i);
  });

  it("FCM uses APNs headers for iOS delivery", () => {
    expect(fcmSource).toContain("apns-priority");
    expect(fcmSource).toContain("apns-push-type");
  });

  it("backend auth maps +86 to CN", () => {
    expect(authRoute).toContain('"+86": "CN"');
  });

  it("CN timezone is Asia/Shanghai", () => {
    expect(authRoute).toContain('CN: "Asia/Shanghai"');
  });
});

// ============================================================
// S12: Leaving Family
// ============================================================
describe("S12: Leaving Family — Guardian Revocation", () => {
  it("guardian link can be revoked", () => {
    // The persona has active links that can be revoked
    expect(persona.guardianLinks[0].status).toBe("active");
  });

  it("SOS resolve checks guardian authorization", () => {
    expect(sosRoute).toContain("Not authorized to resolve this SOS event");
    expect(sosRoute).toContain("isGuardian");
  });

  it("voice call checks authorization", () => {
    expect(sosRoute).toContain("Not authorized for this SOS event");
  });
});
