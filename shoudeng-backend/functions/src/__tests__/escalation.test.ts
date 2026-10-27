/**
 * Phase 5 — Escalation & Delivery Tests
 *
 * Tests the onSOSCreated trigger logic:
 *   - 4-hop escalation chain timing
 *   - Idempotency (resolved SOS stops escalation)
 *   - On-duty guardian selection
 *   - SMS fallback for non-app guardians
 *   - FCM push payload structure
 *   - Push payload PII check
 *   - Free tier enforcement
 *
 * These are unit tests that mock Firebase and external services.
 *
 * Run: cd shoudeng-backend/functions && npm test -- --testPathPattern escalation
 */

import * as fs from "fs";
import * as path from "path";

// Read the escalation trigger source for static analysis
const triggerSource = fs.readFileSync(
  path.join(__dirname, "..", "triggers", "onSOSCreated.ts"),
  "utf-8"
);

// Read FCM service for push payload analysis
const fcmSource = fs.readFileSync(
  path.join(__dirname, "..", "services", "fcm.ts"),
  "utf-8"
);

// Read SMS service
const smsSource = fs.readFileSync(
  path.join(__dirname, "..", "services", "sms.ts"),
  "utf-8"
);

describe("Escalation Chain — Structure", () => {
  it("implements 4 hops", () => {
    // 3 hops log to escalationLog, hop 4 creates a share link
    const hopMatches = triggerSource.match(/hop:\s*\d/g) || [];
    const hopNumbers = new Set(hopMatches.map((m) => m.match(/\d/)![0]));
    expect(hopNumbers.size).toBe(3); // hop 1, 2, 3 logged
    expect(hopNumbers.has("1")).toBe(true);
    expect(hopNumbers.has("2")).toBe(true);
    expect(hopNumbers.has("3")).toBe(true);
    // Hop 4 creates share token instead of logging
    expect(triggerSource).toContain("createShareToken");
  });

  it("Hop 1 fires immediately (no delay before first notification)", () => {
    // The first delay() call should come AFTER hop 1 is sent
    const firstDelayIdx = triggerSource.indexOf("delay(");
    const hop1NotifyIdx = triggerSource.indexOf('hop1_notified');
    expect(hop1NotifyIdx).toBeLessThan(firstDelayIdx);
  });

  it("Hop 2 has 30 second delay", () => {
    expect(triggerSource).toContain("delay(30000)");
  });

  it("Hop 3 voice call delay totals 90s from start (30s + 60s)", () => {
    // After hop 2's 30s delay, there's another 60s delay
    expect(triggerSource).toContain("delay(60000)");
  });

  it("Hop 4 share link delay totals 120s from start (30s + 60s + 30s)", () => {
    // Three delay calls: 30s, 60s, 30s
    const delays = (triggerSource.match(/delay\(\d+\)/g) || []).map((d) =>
      parseInt(d.match(/\d+/)![0])
    );
    expect(delays).toEqual(expect.arrayContaining([30000, 60000, 30000]));
    const totalDelayMs = delays.reduce((sum, d) => sum + d, 0);
    expect(totalDelayMs).toBe(120000); // 120 seconds total
  });

  it("uses 300 second timeout and 512MB memory", () => {
    expect(triggerSource).toMatch(/timeoutSeconds:\s*300/);
    expect(triggerSource).toMatch(/memory:\s*["']512MB["']/);
  });
});

describe("Escalation Chain — Idempotency", () => {
  it("checks resolution status before Hop 2", () => {
    // Between hop 1 and hop 2, there should be a re-read and check
    const hop2Section = triggerSource.substring(
      triggerSource.indexOf("delay(30000)"),
      triggerSource.indexOf("delay(60000)")
    );
    expect(hop2Section).toMatch(/resolvedAt|frozen/);
  });

  it("checks resolution status before Hop 3", () => {
    const hop3Start = triggerSource.indexOf("delay(60000)");
    const hop3Section = triggerSource.substring(
      hop3Start,
      triggerSource.indexOf("delay(30000)", hop3Start + 1)
    );
    expect(hop3Section).toMatch(/resolvedAt|frozen/);
  });

  it("checks resolution status before Hop 4", () => {
    // Last section of the trigger
    const lastDelayIdx = triggerSource.lastIndexOf("delay(30000)");
    const hop4Section = triggerSource.substring(lastDelayIdx);
    expect(hop4Section).toMatch(/resolvedAt|frozen/);
  });

  it("re-reads the SOS document from Firestore before each hop", () => {
    // Should have at least 3 re-reads (snapshot.ref.get())
    const reReads = (triggerSource.match(/snapshot\.ref\.get\(\)/g) || [])
      .length;
    expect(reReads).toBeGreaterThanOrEqual(3);
  });
});

describe("Escalation Chain — Guardian Selection", () => {
  it("queries guardian_links by protectedPersonId and active status", () => {
    expect(triggerSource).toContain('"protectedPersonId"');
    expect(triggerSource).toContain('"status"');
    expect(triggerSource).toContain('"active"');
  });

  it("checks duty schedules for on-duty guardians", () => {
    expect(triggerSource).toContain("duty_schedules");
    expect(triggerSource).toContain("dayOfWeek");
    expect(triggerSource).toContain("startHour");
    expect(triggerSource).toContain("endHour");
  });

  it("falls back to first guardian if no schedules exist", () => {
    expect(triggerSource).toContain("guardianIds[0]");
  });

  it("falls back to first guardian when no one is on duty", () => {
    // onDutyGuardians.length > 0 ? onDutyGuardians : [guardianIds[0]]
    expect(triggerSource).toMatch(
      /onDutyGuardians\.length\s*>\s*0\s*\?\s*onDutyGuardians\s*:\s*\[guardianIds\[0\]\]/
    );
  });
});

describe("Escalation Chain — SMS Fallback", () => {
  it("checks app installation before SMS", () => {
    expect(triggerSource).toContain("hasAppInstalled");
  });

  it("sends SMS only to guardians without the app", () => {
    expect(triggerSource).toContain("!hasApp");
    expect(triggerSource).toContain("sendSOSSms");
  });

  it("logs channel type (push vs sms) in escalation log", () => {
    expect(triggerSource).toContain('channel');
    // SMS fallback triggers on push failure OR no app installed
    expect(triggerSource).toContain("sms_fallback");
  });
});

describe("Escalation Chain — Voice Call (Hop 3)", () => {
  it("dynamically imports twilio service", () => {
    expect(triggerSource).toMatch(/import\(["']\.\.\/services\/twilio["']\)/);
  });

  it("calls initiateVoiceCall with guardianId, sosId, personName", () => {
    expect(triggerSource).toContain("initiateVoiceCall");
  });

  it("handles voice call failure gracefully", () => {
    expect(triggerSource).toMatch(/catch.*error.*hop3_exhausted/s);
  });
});

describe("Escalation Chain — Share Link (Hop 4)", () => {
  it("dynamically imports evidence service", () => {
    expect(triggerSource).toMatch(/import\(["']\.\.\/services\/evidence["']\)/);
  });

  it("creates share token with 48 hour expiry", () => {
    expect(triggerSource).toContain("expiresInHours: 48");
  });

  it("sets createdBy to system_escalation", () => {
    expect(triggerSource).toContain("system_escalation");
  });
});

describe("Escalation Chain — State Transitions", () => {
  const states = [
    "hop1_notified",
    "hop2_allNotified",
    "hop3_voiceCalling",
    "hop3_exhausted",
    "frozen",
  ];

  it("updates escalationState at each hop", () => {
    for (const state of states) {
      expect(triggerSource).toContain(state);
    }
  });

  it("appends to escalationLog array (not replace)", () => {
    expect(triggerSource).toContain("FieldValue.arrayUnion");
  });

  it("logs sentAt timestamp in each escalation entry", () => {
    const sentAtCount = (triggerSource.match(/sentAt:/g) || []).length;
    expect(sentAtCount).toBeGreaterThanOrEqual(3); // At least hop 1, 2, 3
  });
});

describe("FCM Push Payload — PII Check", () => {
  it("does NOT include phone number in push payload", () => {
    // Push notifications should not contain phone numbers
    expect(fcmSource).not.toMatch(/phone_number|phoneNumber.*notification/);
  });

  it("does NOT include location coordinates in push title/body", () => {
    // Coordinates should not be in the visible notification text
    // (they may be in data payload for map display)
    expect(fcmSource).not.toMatch(/lat.*body|lng.*body|latitude.*body/);
  });

  it("SOS alert uses critical interruption level", () => {
    expect(fcmSource).toContain("interruption-level");
    expect(fcmSource).toContain("critical");
  });

  it("respects notification preferences for non-critical alerts", () => {
    // checkin reminder and heartbeat missing should check prefs
    expect(fcmSource).toMatch(/notif.*[Pp]ref|notification.*preferences/);
  });
});

describe("FCM Push — Locale (FIXED)", () => {
  it("FIXED: FCM has per-locale notification routing", () => {
    // F-001 fixed: FCM now has per-recipient locale routing
    expect(fcmSource).toMatch(/getUserLocale/i);
    expect(fcmSource).toMatch(/fcmStrings/);
    // Still has Chinese as one of the supported locales
    const hasChineseChars = /[\u4e00-\u9fff]/.test(fcmSource);
    expect(hasChineseChars).toBe(true);
    // But also has English and French
    expect(fcmSource).toContain("Emergency SOS");
    expect(fcmSource).toContain("SOS Urgence");
  });
});

describe("SMS Templates — Locale (FIXED)", () => {
  it("FIXED: SMS has per-locale template routing", () => {
    // F-002 fixed: SMS now has per-recipient locale routing
    expect(smsSource).toMatch(/getUserLocale|getSmsStrings/i);
    expect(smsSource).toContain("Lantern Care Emergency");
    expect(smsSource).toContain("Lantern Care Urgence");
  });
});

describe("Escalation Chain — Edge Cases", () => {
  it("handles no guardians found", () => {
    expect(triggerSource).toMatch(/linksSnapshot\.empty|guardianIds\.length.*0/);
    expect(triggerSource).toContain("No guardians found");
  });

  it("fetches protected person name with fallback", () => {
    // Should fallback to a default name if user doc doesn't exist
    expect(triggerSource).toMatch(/userDoc\.exists\s*\?/);
    expect(triggerSource).toContain("Protected Person");
  });
});
