/**
 * Seed script for 陈家 (Chen Family) persona test data.
 *
 * Populates Firebase emulator with 30 days of realistic history
 * ending 2026-10-17, including:
 *   - 3 users (陈浩 protected, 陈建国 + 李敏 guardians)
 *   - Guardian links with duty schedules
 *   - 30 days of location points (Toronto weekly pattern)
 *   - 30 check-ins (27 on-time, 2 late, 1 missed → escalated)
 *   - 3 degradation events
 *   - 1 SOS drill (Oct 9, acknowledged 41s by father)
 *   - 1 claims report draft (Oct 12, 2 photo attachments)
 *   - Audit log entries with copy version "2026-10-v1"
 *   - Family plan subscription (Sep 1 → Nov 1)
 *   - Medical card, consular hotline, safe zones
 *
 * Run: npx ts-node qa/seed-chen.ts
 * Requires: Firebase emulators running on localhost
 */

import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";

// --- Init Firebase Admin for emulator ---
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST = "127.0.0.1:9199";

admin.initializeApp({ projectId: "sweethome-d1edd" });
const db = admin.firestore();

// --- Load persona ---
const persona = JSON.parse(
  fs.readFileSync(path.join(__dirname, "personas/chen-family.json"), "utf-8")
);

const HAOZI = persona.members[0];
const FATHER = persona.members[1];
const MOTHER = persona.members[2];
const LOCS = persona.locations;

const COPY_VERSION = "2026-10-v1";
const TODAY = new Date("2026-10-17T23:59:59-04:00"); // Toronto EDT
const DAY_MS = 24 * 60 * 60 * 1000;

function daysAgo(n: number): Date {
  return new Date(TODAY.getTime() - n * DAY_MS);
}

function torontoHour(date: Date, hour: number, minute = 0): Date {
  const d = new Date(date);
  // Toronto is UTC-4 (EDT) in October
  d.setUTCHours(hour + 4, minute, 0, 0);
  return d;
}

function shenzhenHour(date: Date, hour: number, minute = 0): Date {
  const d = new Date(date);
  // Shenzhen is UTC+8
  d.setUTCHours(hour - 8, minute, 0, 0);
  return d;
}

function ts(date: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(date);
}

function jitter(base: number, range: number): number {
  return base + (Math.random() - 0.5) * 2 * range;
}

// --- Seed functions ---

async function seedUsers() {
  for (const member of persona.members) {
    await db.collection("users").doc(member.userId).set({
      displayName: member.displayName,
      phone: member.phone,
      role: member.role,
      avatarInitial: member.avatarInitial,
      timeZone: member.timeZone,
      countryCode: member.countryCode,
      cityName: member.cityName,
      notificationPrefs: {
        sosAlerts: true,
        checkinReminder: true,
        checkinOverdue: true,
        familyFeed: true,
      },
      createdAt: ts(new Date("2026-09-01T00:00:00Z")),
      updatedAt: ts(TODAY),
    });
  }
  console.log("[Seed] 3 users created");
}

async function seedGuardianLinks() {
  for (const link of persona.guardianLinks) {
    const linkId = `${link.guardianId}_${link.protectedPersonId}`;
    await db.collection("guardian_links").doc(linkId).set({
      guardianId: link.guardianId,
      protectedPersonId: link.protectedPersonId,
      status: "active",
      createdAt: ts(new Date("2026-09-01T10:00:00Z")),
      acceptedAt: ts(new Date("2026-09-01T10:05:00Z")),
      revokedAt: null,
      permissions: link.permissions,
      permissionsUpdatedAt: ts(new Date("2026-09-01T10:05:00Z")),
      protectionLayers: ["sos", "location", "checkin", "fall_detect"],
    });
  }
  console.log("[Seed] 2 guardian links created");
}

async function seedDutySchedules() {
  for (const slot of persona.dutySchedule.slots) {
    await db.collection("duty_schedules").add({
      protectedPersonId: HAOZI.userId,
      guardianId: slot.guardianId,
      startHour: slot.startHour,
      endHour: slot.endHour,
      dayOfWeek: slot.dayOfWeek.length > 0 ? slot.dayOfWeek : [1,2,3,4,5,6,7],
      timeZone: slot.timeZone,
      isActive: true,
    });
  }
  console.log("[Seed] 2 duty schedule slots created");
}

async function seedSafeZones() {
  for (const zone of HAOZI.safeZones) {
    await db.collection("safe_zones").doc(zone.id).set({
      userId: HAOZI.userId,
      name: zone.name,
      latitude: zone.latitude,
      longitude: zone.longitude,
      radiusMeters: zone.radius,
      type: zone.type,
      isActive: true,
      isAutoSuggested: false,
      createdAt: ts(new Date("2026-09-05T00:00:00Z")),
    });
  }
  console.log(`[Seed] ${HAOZI.safeZones.length} safe zones created`);
}

async function seedMedicalCard() {
  await db.collection("medical_cards").doc(HAOZI.userId).set({
    userId: HAOZI.userId,
    ...HAOZI.medicalCard,
    updatedAt: ts(new Date("2026-09-02T00:00:00Z")),
  });
  console.log("[Seed] Medical card created");
}

async function seedConsularHotline() {
  await db.collection("selected_hotlines").doc(HAOZI.userId).set({
    userId: HAOZI.userId,
    ...HAOZI.consularHotline,
    updatedAt: ts(new Date("2026-09-02T00:00:00Z")),
  });
  console.log("[Seed] Consular hotline created");
}

async function seedSubscription() {
  await db.collection("subscriptions").doc(FATHER.userId).set({
    userId: FATHER.userId,
    planId: "family",
    appleOriginalTransactionId: "chen-family-tx-001",
    appleProductId: persona.plan.appleProductId,
    status: "active",
    currentPeriodStart: ts(new Date(persona.plan.activeSince)),
    currentPeriodEnd: ts(new Date(persona.plan.nextBilling)),
    cancelledAt: null,
    autoRenew: true,
    createdAt: ts(new Date(persona.plan.activeSince)),
    updatedAt: ts(TODAY),
  });
  console.log("[Seed] Family plan subscription created");
}

async function seedDeviceTokens() {
  for (const member of persona.members) {
    await db.collection("device_tokens").doc(`${member.userId}_ios`).set({
      userId: member.userId,
      token: `fake-apns-token-${member.seedId}`,
      platform: "ios",
      environment: "development",
      updatedAt: ts(TODAY),
    });
  }
  console.log("[Seed] 3 device tokens created");
}

// --- Location history: 30 days of Toronto weekly pattern ---

interface LocPoint {
  lat: number;
  lng: number;
  accuracy: number;
  speed: number;
  isInSafeZone: boolean;
  safeZoneName: string | null;
}

function weekdayPattern(date: Date): Array<{ time: Date; loc: LocPoint }> {
  const points: Array<{ time: Date; loc: LocPoint }> = [];
  const home: LocPoint = { lat: jitter(LOCS.home.lat, 0.0005), lng: jitter(LOCS.home.lng, 0.0005), accuracy: 15, speed: 0, isInSafeZone: true, safeZoneName: "Home - Scarborough Apt" };
  const campus: LocPoint = { lat: jitter(LOCS.campus.lat, 0.001), lng: jitter(LOCS.campus.lng, 0.001), accuracy: 20, speed: 0, isInSafeZone: true, safeZoneName: "U of T St. George" };
  const gym: LocPoint = { lat: jitter(LOCS.gym.lat, 0.0003), lng: jitter(LOCS.gym.lng, 0.0003), accuracy: 10, speed: 0, isInSafeZone: true, safeZoneName: "GoodLife Fitness" };

  // Wake up 07:30, leave 08:00
  points.push({ time: torontoHour(date, 7, 30), loc: home });
  points.push({ time: torontoHour(date, 8, 0), loc: home });
  // Subway: Scarborough → Bloor (14 min gap = tunnel)
  points.push({ time: torontoHour(date, 8, 10), loc: { lat: LOCS.subwayScarborough.lat, lng: LOCS.subwayScarborough.lng, accuracy: 30, speed: 1.5, isInSafeZone: false, safeZoneName: null } });
  // GAP: 8:12 - 8:26 (14 min tunnel, no points)
  points.push({ time: torontoHour(date, 8, 26), loc: { lat: LOCS.subwayBloor.lat, lng: LOCS.subwayBloor.lng, accuracy: 30, speed: 1.5, isInSafeZone: false, safeZoneName: null } });
  // Campus 08:40 - 16:00
  points.push({ time: torontoHour(date, 8, 40), loc: campus });
  points.push({ time: torontoHour(date, 12, 0), loc: campus });
  points.push({ time: torontoHour(date, 16, 0), loc: campus });
  // Return subway (14 min gap)
  points.push({ time: torontoHour(date, 16, 15), loc: { lat: LOCS.subwayBloor.lat, lng: LOCS.subwayBloor.lng, accuracy: 30, speed: 1.5, isInSafeZone: false, safeZoneName: null } });
  // GAP: 16:17 - 16:31
  points.push({ time: torontoHour(date, 16, 31), loc: { lat: LOCS.subwayScarborough.lat, lng: LOCS.subwayScarborough.lng, accuracy: 30, speed: 1.5, isInSafeZone: false, safeZoneName: null } });

  // Gym 3x/week (Mon, Wed, Fri = dayOfWeek 1,3,5)
  const dow = date.getDay();
  if (dow === 1 || dow === 3 || dow === 5) {
    points.push({ time: torontoHour(date, 17, 0), loc: gym });
    points.push({ time: torontoHour(date, 18, 30), loc: gym });
  }

  // Home evening
  points.push({ time: torontoHour(date, 19, 0), loc: home });
  points.push({ time: torontoHour(date, 22, 0), loc: home });
  points.push({ time: torontoHour(date, 23, 30), loc: home });

  return points;
}

function saturdayPattern(date: Date): Array<{ time: Date; loc: LocPoint }> {
  const points: Array<{ time: Date; loc: LocPoint }> = [];
  const home: LocPoint = { lat: jitter(LOCS.home.lat, 0.0005), lng: jitter(LOCS.home.lng, 0.0005), accuracy: 15, speed: 0, isInSafeZone: true, safeZoneName: "Home - Scarborough Apt" };
  const job: LocPoint = { lat: jitter(LOCS.job.lat, 0.0005), lng: jitter(LOCS.job.lng, 0.0005), accuracy: 15, speed: 0, isInSafeZone: true, safeZoneName: "Scarborough Town Centre" };

  points.push({ time: torontoHour(date, 8, 0), loc: home });
  // Part-time job 09:00-17:00
  points.push({ time: torontoHour(date, 9, 0), loc: job });
  points.push({ time: torontoHour(date, 12, 0), loc: job });
  points.push({ time: torontoHour(date, 17, 0), loc: job });
  points.push({ time: torontoHour(date, 18, 0), loc: home });
  points.push({ time: torontoHour(date, 22, 30), loc: home });

  return points;
}

function sundayPattern(date: Date): Array<{ time: Date; loc: LocPoint }> {
  const home: LocPoint = { lat: jitter(LOCS.home.lat, 0.0005), lng: jitter(LOCS.home.lng, 0.0005), accuracy: 15, speed: 0, isInSafeZone: true, safeZoneName: "Home - Scarborough Apt" };
  return [
    { time: torontoHour(date, 10, 0), loc: home },
    { time: torontoHour(date, 14, 0), loc: home },
    { time: torontoHour(date, 18, 0), loc: home },
    { time: torontoHour(date, 22, 0), loc: home },
  ];
}

async function seedLocationHistory() {
  let totalPoints = 0;
  const batch = db.batch();

  for (let day = 29; day >= 0; day--) {
    const date = daysAgo(day);
    const dow = date.getDay(); // 0=Sun, 6=Sat

    let points: Array<{ time: Date; loc: LocPoint }>;

    // Special days
    if (day === 11) {
      // Oct 6: phone offline 2h (notifications disabled) — fewer points
      points = weekdayPattern(date).slice(0, 5);
    } else if (day === 6) {
      // Oct 11: phone offline 9h overnight (battery died) — no points after 01:00
      points = weekdayPattern(date).filter(p => p.time.getUTCHours() < 18);
    } else if (day === 12) {
      // Oct 5 (Sat): Niagara Falls trip
      const home: LocPoint = { lat: LOCS.home.lat, lng: LOCS.home.lng, accuracy: 15, speed: 0, isInSafeZone: true, safeZoneName: "Home - Scarborough Apt" };
      const niagara: LocPoint = { lat: LOCS.niagaraFalls.lat, lng: LOCS.niagaraFalls.lng, accuracy: 25, speed: 0, isInSafeZone: false, safeZoneName: null };
      points = [
        { time: torontoHour(date, 9, 0), loc: home },
        { time: torontoHour(date, 10, 30), loc: { ...niagara, speed: 30 } },
        { time: torontoHour(date, 11, 0), loc: niagara },
        { time: torontoHour(date, 14, 0), loc: niagara },
        { time: torontoHour(date, 16, 0), loc: niagara },
        { time: torontoHour(date, 18, 30), loc: home },
        { time: torontoHour(date, 22, 0), loc: home },
      ];
    } else if (day === 20 || day === 15) {
      // Two late nights (02:00 return): Oct 27 - day 20, Oct 2 - day 15
      points = weekdayPattern(date);
      const queenSt: LocPoint = { lat: LOCS.queenStBar.lat, lng: LOCS.queenStBar.lng, accuracy: 20, speed: 0, isInSafeZone: false, safeZoneName: null };
      const home: LocPoint = { lat: LOCS.home.lat, lng: LOCS.home.lng, accuracy: 15, speed: 0, isInSafeZone: true, safeZoneName: "Home - Scarborough Apt" };
      points.push({ time: torontoHour(date, 23, 30), loc: queenSt });
      // Next day 02:00
      const nextDay = new Date(date.getTime() + DAY_MS);
      points.push({ time: torontoHour(nextDay, 2, 0), loc: home });
    } else if (dow === 0) {
      points = sundayPattern(date);
    } else if (dow === 6) {
      points = saturdayPattern(date);
    } else {
      points = weekdayPattern(date);
    }

    for (const p of points) {
      const docRef = db.collection("location_history_chen").doc();
      batch.set(docRef, {
        userId: HAOZI.userId,
        latitude: p.loc.lat,
        longitude: p.loc.lng,
        accuracy: p.loc.accuracy,
        speed: p.loc.speed,
        timestamp: ts(p.time),
        isInSafeZone: p.loc.isInSafeZone,
        safeZoneName: p.loc.safeZoneName,
      });
      totalPoints++;
    }
  }

  await batch.commit();
  console.log(`[Seed] ${totalPoints} location points created over 30 days`);
}

// --- Check-ins: 30 days, 27 on-time, 2 late, 1 missed ---

async function seedCheckins() {
  const batch = db.batch();
  let count = 0;

  for (let day = 29; day >= 0; day--) {
    const date = daysAgo(day);
    const isOct3 = day === 14; // Oct 3 — missed check-in
    const isLate1 = day === 22; // Sep 25 — late
    const isLate2 = day === 10; // Oct 7 — late

    if (isOct3) {
      // Missed — no check-in, will be escalated
      continue;
    }

    const hour = isLate1 ? 23 : isLate2 ? 23 : Math.floor(20 + Math.random() * 2);
    const minute = Math.floor(Math.random() * 59);
    const checkinTime = torontoHour(date, hour, minute);

    const docRef = db.collection("checkins").doc();
    batch.set(docRef, {
      userId: HAOZI.userId,
      timestamp: ts(checkinTime),
      latitude: LOCS.home.lat,
      longitude: LOCS.home.lng,
      note: isLate1 || isLate2 ? "Sorry, was studying late" : null,
    });
    count++;

    // Timeline entry
    const tlRef = db.collection("timeline_entries").doc();
    batch.set(tlRef, {
      userId: HAOZI.userId,
      timestamp: ts(checkinTime),
      type: "checkIn",
      description: isLate1 || isLate2 ? "报平安（迟到）" : "报平安",
      detail: null,
    });
  }

  // Oct 3 missed check-in escalation timeline
  const oct3 = daysAgo(14);
  const missedTlRef = db.collection("timeline_entries").doc();
  batch.set(missedTlRef, {
    userId: HAOZI.userId,
    timestamp: ts(shenzhenHour(new Date(oct3.getTime() + DAY_MS), 11, 15)),
    type: "missedCheckIn",
    description: "未按时报平安，已通知守护者",
    detail: "SMS sent to 李敏, resolved by 李敏",
  });

  await batch.commit();
  console.log(`[Seed] ${count} check-ins + 1 missed escalation created`);
}

// --- Degradation events ---

async function seedDegradationEvents() {
  const batch = db.batch();

  // Oct 6: notifications disabled 2h (14:00-16:00 Toronto)
  const oct6 = daysAgo(11);
  batch.set(db.collection("timeline_entries").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(torontoHour(oct6, 14, 0)),
    type: "degradation",
    description: "Notifications disabled",
    detail: "notification_disabled for 2 hours",
  });
  batch.set(db.collection("timeline_entries").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(torontoHour(oct6, 16, 0)),
    type: "degradation",
    description: "Notifications re-enabled",
    detail: "notification_restored",
  });

  // Oct 11: phone offline 9h overnight (battery died 01:00 - 09:00 Toronto)
  const oct11 = daysAgo(6);
  batch.set(db.collection("timeline_entries").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(torontoHour(oct11, 1, 0)),
    type: "degradation",
    description: "Device offline - battery died",
    detail: "device_offline for 9 hours, battery_level=0",
  });
  batch.set(db.collection("timeline_entries").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(torontoHour(oct11, 9, 0)),
    type: "degradation",
    description: "Device back online",
    detail: "device_online, battery_level=0.23",
  });

  // Oct 8-10: Low Power Mode 3 days
  for (let d = 9; d <= 11; d++) {
    const date = daysAgo(17 - d + 8); // Oct 8-10
    batch.set(db.collection("timeline_entries").doc(), {
      userId: HAOZI.userId,
      timestamp: ts(torontoHour(daysAgo(17 - d + 8), 8, 0)),
      type: "degradation",
      description: "Low Power Mode enabled",
      detail: "low_power_mode active, reduced location frequency",
    });
  }

  await batch.commit();
  console.log("[Seed] 3 degradation events created (notifications, offline, low-power)");
}

// --- SOS drill (Oct 9) ---

async function seedSOSDrill() {
  const oct9 = daysAgo(8);
  const triggeredAt = torontoHour(oct9, 14, 0);
  const resolvedAt = new Date(triggeredAt.getTime() + 41 * 1000);

  const sosId = "sos-drill-oct9";
  await db.collection("sos_events").doc(sosId).set({
    protectedPersonId: HAOZI.userId,
    triggeredAt: ts(triggeredAt),
    triggerMethod: "longPress",
    latitude: LOCS.campus.lat,
    longitude: LOCS.campus.lng,
    accuracy: 15,
    batteryLevel: 0.72,
    escalationState: "resolved",
    resolvedAt: ts(resolvedAt),
    resolvedBy: FATHER.userId,
    resolution: "guardianConfirmedSafe",
    escalationLog: [
      {
        hop: 1,
        targetId: FATHER.userId,
        sentAt: ts(triggeredAt),
        deliveredAt: ts(new Date(triggeredAt.getTime() + 3000)),
        readAt: ts(new Date(triggeredAt.getTime() + 35000)),
        respondedAt: ts(resolvedAt),
        response: "taken_over",
        callSid: null,
        channel: "push",
      },
    ],
  });

  // Timeline entries
  const batch = db.batch();
  batch.set(db.collection("timeline_entries").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(triggeredAt),
    type: "sosTriggered",
    description: "触发紧急求助（长按） — 演习",
    detail: "SOS drill",
  });
  batch.set(db.collection("timeline_entries").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(resolvedAt),
    type: "sosResolved",
    description: "守护者确认安全",
    detail: "Resolved by 陈建国 in 41s",
  });
  await batch.commit();

  console.log("[Seed] SOS drill (Oct 9) created — acknowledged by father in 41s");
}

// --- Claims report draft (Oct 12) ---

async function seedClaimsReport() {
  const oct12 = daysAgo(5);
  await db.collection("claim_material_exports").doc("claim-oct12").set({
    exportId: "claim-oct12",
    userId: HAOZI.userId,
    incidentDate: ts(torontoHour(oct12, 15, 0)),
    exportedAt: ts(torontoHour(oct12, 18, 30)),
    insuranceType: "travel",
    description: "Lost phone at campus library",
    contentHash: "sha256-placeholder-chen-claim-oct12",
    attachments: [
      "gs://sweethome-d1edd.appspot.com/evidence/chen-hao/claim-oct12/photo1.jpg",
      "gs://sweethome-d1edd.appspot.com/evidence/chen-hao/claim-oct12/photo2.jpg",
    ],
    includeSOS: false,
    includeCheckIns: true,
    includeTimeline: true,
    includeLocation: true,
    includeMedicalCard: false,
  });

  console.log("[Seed] Claims report draft (Oct 12) created with 2 photo attachments");
}

// --- Audit log entries ---

async function seedAuditLog() {
  const batch = db.batch();
  const sep1 = new Date("2026-09-01T10:00:00Z");

  // Disclaimer acceptances for all 3 users
  for (const member of persona.members) {
    for (const screen of ["onboard.not_emergency", "onboard.scope", "onboard.control"]) {
      batch.set(db.collection("consent_audit_chen").doc(), {
        userId: member.userId,
        timestamp: ts(sep1),
        consentType: screen,
        action: "granted",
        grantedTo: "system",
        detail: `Disclaimer screen accepted`,
        copyVersion: COPY_VERSION,
        locale: member.locale,
        deviceId: `device-${member.seedId}`,
        appVersion: "1.0.0",
      });
    }

    // Feature consents
    for (const [key, value] of Object.entries(member.consent)) {
      if (value) {
        batch.set(db.collection("consent_audit_chen").doc(), {
          userId: member.userId,
          timestamp: ts(new Date(sep1.getTime() + 60000)),
          consentType: `consent.${key === "fallDetect" ? "fall_detect" : key === "voiceCall" ? "voice_call" : key}`,
          action: "granted",
          grantedTo: "system",
          detail: `Feature consent granted`,
          copyVersion: COPY_VERSION,
          locale: member.locale,
          deviceId: `device-${member.seedId}`,
          appVersion: "1.0.0",
        });
      }
    }
  }

  // Haozi trajectory = denied initially
  batch.set(db.collection("consent_audit_chen").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(new Date(sep1.getTime() + 60000)),
    consentType: "consent.trajectory",
    action: "denied",
    grantedTo: "system",
    detail: "Trajectory consent denied at onboarding",
    copyVersion: COPY_VERSION,
    locale: HAOZI.locale,
    deviceId: `device-${HAOZI.seedId}`,
    appVersion: "1.0.0",
  });

  // SOS drill audit
  batch.set(db.collection("consent_audit_chen").doc(), {
    userId: HAOZI.userId,
    timestamp: ts(torontoHour(daysAgo(8), 14, 0)),
    consentType: "sos_triggered",
    action: "granted",
    grantedTo: "system",
    detail: "SOS drill triggered — longPress",
    copyVersion: COPY_VERSION,
    locale: HAOZI.locale,
    deviceId: `device-${HAOZI.seedId}`,
    appVersion: "1.0.0",
  });

  // Subscription audit
  batch.set(db.collection("consent_audit_chen").doc(), {
    userId: FATHER.userId,
    timestamp: ts(new Date("2026-09-01T10:10:00Z")),
    consentType: "subscription",
    action: "granted",
    grantedTo: "system",
    detail: "Subscription activated: family",
    copyVersion: COPY_VERSION,
    locale: FATHER.locale,
    deviceId: `device-${FATHER.seedId}`,
    appVersion: "1.0.0",
  });

  await batch.commit();
  console.log("[Seed] Audit log entries created (disclaimers, consents, SOS, subscription)");
}

// --- Main ---

async function main() {
  console.log("=== Seeding 陈家 (Chen Family) persona data ===\n");

  await seedUsers();
  await seedGuardianLinks();
  await seedDutySchedules();
  await seedSafeZones();
  await seedMedicalCard();
  await seedConsularHotline();
  await seedSubscription();
  await seedDeviceTokens();
  await seedLocationHistory();
  await seedCheckins();
  await seedDegradationEvents();
  await seedSOSDrill();
  await seedClaimsReport();
  await seedAuditLog();

  console.log("\n=== Seed complete ===");
  console.log("Users: 3 (陈浩, 陈建国, 李敏)");
  console.log("Plan: Family (Sep 1 → Nov 1)");
  console.log("Location points: ~350 over 30 days");
  console.log("Check-ins: 29 (27 on-time, 2 late, 1 missed)");
  console.log("SOS: 1 drill (Oct 9)");
  console.log("Claims: 1 draft (Oct 12)");
  console.log("Degradation events: 3");

  process.exit(0);
}

main().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});
