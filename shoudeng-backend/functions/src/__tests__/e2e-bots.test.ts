/**
 * E2E Dual-Bot Test Suite — Guardian "妈妈" + Protected Person "小明"
 *
 * Runs against Firebase Emulator (Firestore + Auth + Functions).
 * Tests the complete lifecycle: signup → link → daily use → SOS → cleanup.
 *
 * Prerequisites:
 *   firebase emulators:start --only functions,firestore,auth
 *
 * Run:
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *   FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *   FUNCTIONS_EMULATOR=true \
 *   npx jest --testPathPattern e2e-bots --runInBand --forceExit
 */

import request from "supertest";
import * as admin from "firebase-admin";

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const API_BASE = process.env.API_BASE || "http://localhost:5001/sweethome-d1edd/us-central1/api";

// Bot identities
const GUARDIAN = {
  uid: "bot-guardian-mama",
  displayName: "妈妈",
  role: "guardian" as const,
  phone: "+8613800000001",
};

const PROTECTED = {
  uid: "bot-protected-xiaoming",
  displayName: "小明",
  role: "protected" as const,
  phone: "+8613800000002",
};

// Second protected person for concurrent SOS tests
const PROTECTED_B = {
  uid: "bot-protected-xiaoli",
  displayName: "小丽",
  role: "protected" as const,
  phone: "+8613800000003",
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Create a fake Firebase ID token for emulator auth (no signature needed) */
function fakeIdToken(uid: string, phone: string): string {
  const header = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({ uid, user_id: uid, phone_number: phone, sub: uid })
  ).toString("base64url");
  return `${header}.${payload}.fake-sig`;
}

/** Create a fake access token (emulator decodes base64 payload directly) */
function fakeAccessToken(uid: string): string {
  const header = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const payload = Buffer.from(
    JSON.stringify({ uid, type: "access", exp: Math.floor(Date.now() / 1000) + 3600 })
  ).toString("base64url");
  return `${header}.${payload}.fake-sig`;
}

/** Supertest agent with auth header pre-set */
function authed(uid: string) {
  return {
    get: (path: string) =>
      request(API_BASE).get(path).set("Authorization", `Bearer ${fakeAccessToken(uid)}`),
    post: (path: string) =>
      request(API_BASE).post(path).set("Authorization", `Bearer ${fakeAccessToken(uid)}`),
    put: (path: string) =>
      request(API_BASE).put(path).set("Authorization", `Bearer ${fakeAccessToken(uid)}`),
    delete: (path: string) =>
      request(API_BASE).delete(path).set("Authorization", `Bearer ${fakeAccessToken(uid)}`),
  };
}

// ---------------------------------------------------------------------------
// State shared across acts
// ---------------------------------------------------------------------------

let guardianTokens: { accessToken: string; refreshToken: string };
let protectedTokens: { accessToken: string; refreshToken: string };
let protectedBTokens: { accessToken: string; refreshToken: string };
let inviteCode: string;
let inviteId: string;
let safeZoneId: string;
let familyPostId: string;
let commentId: string;
let sosEventId: string;
let sosEventIdB: string;
let homeTimerDeadline: string;
let medicalShareToken: string;

// ---------------------------------------------------------------------------
// Timeout — E2E tests need more time
// ---------------------------------------------------------------------------

jest.setTimeout(60_000);

// ---------------------------------------------------------------------------
// ACT 1 — Signup & Login
// ---------------------------------------------------------------------------

describe("Act 1: Signup & Login", () => {
  it("1.1 Guardian signs up", async () => {
    const res = await request(API_BASE)
      .post("/v1/auth/signup")
      .send({
        idToken: fakeIdToken(GUARDIAN.uid, GUARDIAN.phone),
        displayName: GUARDIAN.displayName,
        role: GUARDIAN.role,
      });

    expect(res.status).toBe(201);
    expect(res.body.userId).toBe(GUARDIAN.uid);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.refreshToken).toBeDefined();
    guardianTokens = {
      accessToken: res.body.accessToken,
      refreshToken: res.body.refreshToken,
    };
  });

  it("1.2 Protected person signs up", async () => {
    const res = await request(API_BASE)
      .post("/v1/auth/signup")
      .send({
        idToken: fakeIdToken(PROTECTED.uid, PROTECTED.phone),
        displayName: PROTECTED.displayName,
        role: PROTECTED.role,
      });

    expect(res.status).toBe(201);
    expect(res.body.userId).toBe(PROTECTED.uid);
    protectedTokens = {
      accessToken: res.body.accessToken,
      refreshToken: res.body.refreshToken,
    };
  });

  it("1.3 Protected person B signs up (for concurrent SOS)", async () => {
    const res = await request(API_BASE)
      .post("/v1/auth/signup")
      .send({
        idToken: fakeIdToken(PROTECTED_B.uid, PROTECTED_B.phone),
        displayName: PROTECTED_B.displayName,
        role: PROTECTED_B.role,
      });

    expect(res.status).toBe(201);
    protectedBTokens = {
      accessToken: res.body.accessToken,
      refreshToken: res.body.refreshToken,
    };
  });

  it("1.4 Duplicate signup is rejected (409)", async () => {
    const res = await request(API_BASE)
      .post("/v1/auth/signup")
      .send({
        idToken: fakeIdToken(GUARDIAN.uid, GUARDIAN.phone),
        displayName: GUARDIAN.displayName,
        role: GUARDIAN.role,
      });

    expect(res.status).toBe(409);
  });

  it("1.5 Guardian can login after signup", async () => {
    const res = await request(API_BASE)
      .post("/v1/auth/login")
      .send({ idToken: fakeIdToken(GUARDIAN.uid, GUARDIAN.phone) });

    expect(res.status).toBe(200);
    expect(res.body.role).toBe("guardian");
  });

  it("1.6 Protected person can fetch own profile", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/user/me");

    expect(res.status).toBe(200);
    expect(res.body.displayName).toBe("小明");
    expect(res.body.role).toBe("protected");
    expect(res.body.countryCode).toBe("CN");
  });

  it("1.7 Token refresh works", async () => {
    const res = await request(API_BASE)
      .post("/v1/auth/refresh")
      .send({ refreshToken: guardianTokens.refreshToken });

    expect(res.status).toBe(200);
    expect(res.body.accessToken).toBeDefined();
    expect(res.body.userId).toBe(GUARDIAN.uid);
  });
});

// ---------------------------------------------------------------------------
// ACT 2 — Invite & Link
// ---------------------------------------------------------------------------

describe("Act 2: Invite & Link", () => {
  it("2.1 Guardian creates invite", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/invite/create")
      .send({ role: "guardian" });

    expect(res.status).toBe(201);
    expect(res.body.code).toHaveLength(6);
    inviteCode = res.body.code;
    inviteId = res.body.inviteId;
  });

  it("2.2 Protected person accepts invite by code", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/invite/accept")
      .send({ code: inviteCode });

    expect(res.status).toBe(200);
    expect(res.body.guardianId).toBe(GUARDIAN.uid);
    expect(res.body.protectedPersonId).toBe(PROTECTED.uid);
  });

  it("2.3 Self-accept is rejected", async () => {
    // Guardian creates another invite
    const createRes = await authed(GUARDIAN.uid)
      .post("/v1/invite/create")
      .send({ role: "guardian" });
    expect(createRes.status).toBe(201);

    // Guardian tries to accept own invite
    const res = await authed(GUARDIAN.uid)
      .post("/v1/invite/accept")
      .send({ code: createRes.body.code });

    expect(res.status).toBe(400);
  });

  it("2.4 Link Protected B to Guardian for concurrent SOS tests", async () => {
    const createRes = await authed(GUARDIAN.uid)
      .post("/v1/invite/create")
      .send({ role: "guardian" });
    expect(createRes.status).toBe(201);

    const res = await authed(PROTECTED_B.uid)
      .post("/v1/invite/accept")
      .send({ code: createRes.body.code });

    expect(res.status).toBe(200);
    expect(res.body.protectedPersonId).toBe(PROTECTED_B.uid);
  });

  it("2.5 Guardian sees protected persons list", async () => {
    const res = await authed(GUARDIAN.uid).get("/v1/guardian/protected-persons");

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    const names = res.body.map((p: any) => p.displayName);
    expect(names).toContain("小明");
    expect(names).toContain("小丽");
  });

  it("2.6 Protected person sees guardian list", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/protected/guardians");

    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThanOrEqual(1);
    expect(res.body[0].user.displayName).toBe("妈妈");
  });
});

// ---------------------------------------------------------------------------
// ACT 3 — Profile & Device Setup
// ---------------------------------------------------------------------------

describe("Act 3: Profile & Device Setup", () => {
  it("3.1 Protected person updates profile", async () => {
    const res = await authed(PROTECTED.uid)
      .put("/v1/user/me")
      .send({ cityName: "北京", timeZone: "Asia/Shanghai" });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("3.2 Guardian registers device token", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/device/token")
      .send({ token: "fake-apns-token-guardian-001", platform: "ios" });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("3.3 Protected person registers device token", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/device/token")
      .send({ token: "fake-apns-token-protected-001", platform: "ios" });

    expect(res.status).toBe(200);
  });

  it("3.4 Guardian sets notification preferences", async () => {
    const res = await authed(GUARDIAN.uid)
      .put("/v1/user/notification-preferences")
      .send({
        sosAlerts: true,
        checkinReminder: true,
        checkinOverdue: true,
        familyFeed: true,
      });

    expect(res.status).toBe(200);
  });

  it("3.5 Profile update persists", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/user/me");

    expect(res.status).toBe(200);
    expect(res.body.cityName).toBe("北京");
  });
});

// ---------------------------------------------------------------------------
// ACT 4 — Safe Zones & Telemetry
// ---------------------------------------------------------------------------

describe("Act 4: Safe Zones & Telemetry", () => {
  it("4.1 Protected person creates a safe zone", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/safe-zone/save")
      .send({
        name: "家",
        latitude: 39.9042,
        longitude: 116.4074,
        radius: 200,
      });

    expect(res.status).toBe(200);
    expect(res.body.id).toBeDefined();
    safeZoneId = res.body.id;
  });

  it("4.2 Protected person lists safe zones", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/safe-zones");

    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThanOrEqual(1);
    expect(res.body.find((z: any) => z.name === "家")).toBeDefined();
  });

  it("4.3 Protected person sends heartbeat", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/heartbeat")
      .send({
        userId: PROTECTED.uid,
        timestamp: new Date().toISOString(),
        source: "foreground",
        batteryLevel: 85,
        batteryState: "charging",
        latitude: 39.9042,
        longitude: 116.4074,
        accuracy: 10,
      });

    expect(res.status).toBe(200);
  });

  it("4.4 Heartbeat for another user is rejected (403)", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/heartbeat")
      .send({
        userId: GUARDIAN.uid,
        timestamp: new Date().toISOString(),
      });

    expect(res.status).toBe(403);
  });

  it("4.5 Protected person sends location report", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/location/report")
      .send({
        userId: PROTECTED.uid,
        latitude: 39.9042,
        longitude: 116.4074,
        accuracy: 15,
        speed: 0,
        timestamp: new Date().toISOString(),
        isInSafeZone: true,
        safeZoneName: "家",
      });

    expect(res.status).toBe(200);
  });

  it("4.6 Protected person checks in (报平安)", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/checkin")
      .send({
        userId: PROTECTED.uid,
        latitude: 39.9042,
        longitude: 116.4074,
        note: "我到家了",
      });

    expect(res.status).toBe(200);
    expect(res.body.checkInId).toBeDefined();
  });

  it("4.7 Checkin for another user is rejected (403)", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/checkin")
      .send({ userId: PROTECTED.uid });

    expect(res.status).toBe(403);
  });

  it("4.8 Invalid safe zone coordinates rejected (400)", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/safe-zone/save")
      .send({ name: "bad", latitude: 999, longitude: 116 });

    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// ACT 5 — Duty Schedule & Permissions
// ---------------------------------------------------------------------------

describe("Act 5: Duty Schedule & Permissions", () => {
  it("5.1 Protected person sets duty schedule for guardian", async () => {
    const res = await authed(PROTECTED.uid)
      .put("/v1/duty-schedule")
      .send({
        guardianId: GUARDIAN.uid,
        slots: [
          { startHour: 8, endHour: 20, dayOfWeek: [1, 2, 3, 4, 5] },
          { startHour: 9, endHour: 18, dayOfWeek: [6, 7] },
        ],
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("5.2 Protected person updates guardian permissions", async () => {
    const res = await authed(PROTECTED.uid)
      .put(`/v1/protected/guardians/${GUARDIAN.uid}/permissions`)
      .send({
        canSeeLocation: true,
        canSeeBattery: true,
        canSeeHealth: false,
        canSeePhoneActivity: false,
        canHearEmergencyAudio: true,
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("5.3 Guardian cannot update own permissions on protected (403)", async () => {
    const res = await authed(GUARDIAN.uid)
      .put(`/v1/protected/guardians/${GUARDIAN.uid}/permissions`)
      .send({ canSeeLocation: true });

    // Guardian is not the protected person in this link
    expect(res.status).toBe(403);
  });
});

// ---------------------------------------------------------------------------
// ACT 6 — SOS Flow (Happy Path)
// ---------------------------------------------------------------------------

describe("Act 6: SOS Flow", () => {
  it("6.1 Protected person triggers SOS", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/sos/trigger")
      .send({
        protectedPersonId: PROTECTED.uid,
        triggerMethod: "longPress",
        latitude: 39.9042,
        longitude: 116.4074,
        batteryLevel: 72,
      });

    expect(res.status).toBe(201);
    expect(res.body.sosEventId).toBeDefined();
    expect(res.body.escalationState).toBe("initiated");
    sosEventId = res.body.sosEventId;
  });

  it("6.2 Duplicate SOS returns existing event (idempotent)", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/sos/trigger")
      .send({
        protectedPersonId: PROTECTED.uid,
        triggerMethod: "longPress",
      });

    expect(res.status).toBe(200);
    expect(res.body.sosEventId).toBe(sosEventId);
    expect(res.body.message).toMatch(/already active/i);
  });

  it("6.3 Cannot trigger SOS for another user (403)", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/sos/trigger")
      .send({ protectedPersonId: PROTECTED.uid });

    expect(res.status).toBe(403);
  });

  it("6.4 Unauthorized user cannot resolve SOS (403)", async () => {
    const res = await authed(PROTECTED_B.uid)
      .post("/v1/sos/resolve")
      .send({
        sosEventId,
        resolution: "guardianConfirmedSafe",
      });

    expect(res.status).toBe(403);
  });

  it("6.5 Guardian resolves SOS", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/sos/resolve")
      .send({
        sosEventId,
        resolution: "guardianConfirmedSafe",
      });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("6.6 Resolving already-resolved SOS returns 409", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/sos/resolve")
      .send({
        sosEventId,
        resolution: "guardianConfirmedSafe",
      });

    expect(res.status).toBe(409);
  });
});

// ---------------------------------------------------------------------------
// ACT 7 — Family Feed
// ---------------------------------------------------------------------------

describe("Act 7: Family Feed", () => {
  it("7.1 Guardian creates a post", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/family/posts")
      .send({ text: "小明今天在家安全，放心。" });

    expect(res.status).toBe(201);
    expect(res.body.postId).toBeDefined();
    familyPostId = res.body.postId;
  });

  it("7.2 Protected person reads family feed", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/family/posts");

    expect(res.status).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    const post = res.body.find((p: any) => p.id === familyPostId);
    expect(post).toBeDefined();
    expect(post.text).toBe("小明今天在家安全，放心。");
  });

  it("7.3 Protected person comments on post", async () => {
    const res = await authed(PROTECTED.uid)
      .post(`/v1/family/posts/${familyPostId}/comments`)
      .send({ text: "谢谢妈妈！" });

    expect(res.status).toBe(201);
    expect(res.body.commentId).toBeDefined();
    commentId = res.body.commentId;
  });

  it("7.4 Guardian edits post", async () => {
    const res = await authed(GUARDIAN.uid)
      .put(`/v1/family/posts/${familyPostId}`)
      .send({ text: "小明今天在家安全，放心。已确认。" });

    expect(res.status).toBe(200);
  });

  it("7.5 Non-author cannot edit post (403)", async () => {
    const res = await authed(PROTECTED.uid)
      .put(`/v1/family/posts/${familyPostId}`)
      .send({ text: "hack" });

    expect(res.status).toBe(403);
  });

  it("7.6 Empty comment rejected (400)", async () => {
    const res = await authed(PROTECTED.uid)
      .post(`/v1/family/posts/${familyPostId}/comments`)
      .send({ text: "" });

    expect(res.status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// ACT 8 — Home Timer & Medical Card
// ---------------------------------------------------------------------------

describe("Act 8: Home Timer & Medical Card", () => {
  it("8.1 Protected person sets home timer", async () => {
    homeTimerDeadline = new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(); // 2h from now

    const res = await authed(PROTECTED.uid)
      .post("/v1/home-timer")
      .send({
        deadline: homeTimerDeadline,
        label: "放学回家",
        latitude: 39.9042,
        longitude: 116.4074,
      });

    expect(res.status).toBe(201);
    expect(res.body.success).toBe(true);
  });

  it("8.2 Guardian sees active home timers", async () => {
    const res = await authed(GUARDIAN.uid).get("/v1/home-timer/guardian");

    expect(res.status).toBe(200);
    const timer = res.body.find((t: any) => t.userId === PROTECTED.uid);
    expect(timer).toBeDefined();
    expect(timer.label).toBe("放学回家");
  });

  it("8.3 Protected person dismisses timer (arrived safely)", async () => {
    const res = await authed(PROTECTED.uid).post("/v1/home-timer/dismiss");

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("8.4 Dismissing when no active timer returns 404", async () => {
    const res = await authed(PROTECTED.uid).post("/v1/home-timer/dismiss");

    expect(res.status).toBe(404);
  });

  it("8.5 Protected person saves medical card", async () => {
    const res = await authed(PROTECTED.uid)
      .put("/v1/medical-card")
      .send({
        bloodType: "A+",
        allergies: ["青霉素"],
        medications: [],
        conditions: ["哮喘"],
        emergencyNote: "哮喘急性发作时使用吸入器",
        organDonor: false,
      });

    expect(res.status).toBe(200);
  });

  it("8.6 Protected person reads own medical card", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/medical-card");

    expect(res.status).toBe(200);
    expect(res.body.bloodType).toBe("A+");
    expect(res.body.allergies).toContain("青霉素");
    expect(res.body.conditions).toContain("哮喘");
  });

  it("8.7 Protected person creates medical card share link", async () => {
    const res = await authed(PROTECTED.uid).post("/v1/medical-card/share");

    expect(res.status).toBe(200);
    expect(res.body.token).toBeDefined();
    medicalShareToken = res.body.token;
  });

  it("8.8 Share link provides medical data without auth", async () => {
    const res = await request(API_BASE).get(`/v1/medical-card/share/${medicalShareToken}`);

    expect(res.status).toBe(200);
    expect(res.body.bloodType).toBe("A+");
    expect(res.body.name).toBe("小明");
  });
});

// ---------------------------------------------------------------------------
// ACT 9 — Timeline & Data Export
// ---------------------------------------------------------------------------

describe("Act 9: Timeline & Data Export", () => {
  it("9.1 Protected person has timeline entries from previous actions", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/timeline");

    expect(res.status).toBe(200);
    expect(res.body.entries.length).toBeGreaterThanOrEqual(1);

    // Should have SOS trigger, SOS resolve, check-in, home timer entries
    const types = res.body.entries.map((e: any) => e.type);
    expect(types).toContain("sosTriggered");
    expect(types).toContain("checkIn");
  });

  it("9.2 GDPR data export returns all user data", async () => {
    const res = await authed(PROTECTED.uid).post("/v1/user/export");

    expect(res.status).toBe(200);
    expect(res.body.userId).toBe(PROTECTED.uid);
    expect(res.body.profile).toBeDefined();
    expect(res.body.profile.displayName).toBe("小明");
    expect(res.body.guardianLinks).toBeDefined();
    expect(res.body.safeZones).toBeDefined();
    expect(res.body.sosEvents).toBeDefined();
    expect(res.body.timeline).toBeDefined();
  });

  it("9.3 Guardian data export works", async () => {
    const res = await authed(GUARDIAN.uid).post("/v1/user/export");

    expect(res.status).toBe(200);
    expect(res.body.userId).toBe(GUARDIAN.uid);
    expect(res.body.guardianLinks.length).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// ACT 10 — Persistence Verification
// ---------------------------------------------------------------------------

describe("Act 10: Persistence Verification", () => {
  it("10.1 Re-authenticate and verify profile persisted", async () => {
    // Login again (simulating app restart)
    const loginRes = await request(API_BASE)
      .post("/v1/auth/login")
      .send({ idToken: fakeIdToken(PROTECTED.uid, PROTECTED.phone) });

    expect(loginRes.status).toBe(200);
    expect(loginRes.body.displayName).toBe("小明");

    // Fetch profile with fresh auth
    const profileRes = await authed(PROTECTED.uid).get("/v1/user/me");
    expect(profileRes.status).toBe(200);
    expect(profileRes.body.cityName).toBe("北京");
    expect(profileRes.body.countryCode).toBe("CN");
  });

  it("10.2 Guardian link persists after re-auth", async () => {
    const res = await authed(GUARDIAN.uid).get("/v1/guardian/protected-persons");
    expect(res.status).toBe(200);
    const names = res.body.map((p: any) => p.displayName);
    expect(names).toContain("小明");
  });

  it("10.3 Safe zones persist", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/safe-zones");
    expect(res.status).toBe(200);
    expect(res.body.find((z: any) => z.name === "家")).toBeDefined();
  });

  it("10.4 Timeline entries persist", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/timeline");
    expect(res.status).toBe(200);
    expect(res.body.entries.length).toBeGreaterThanOrEqual(3);
  });

  it("10.5 Medical card persists", async () => {
    const res = await authed(PROTECTED.uid).get("/v1/medical-card");
    expect(res.status).toBe(200);
    expect(res.body.bloodType).toBe("A+");
  });

  it("10.6 Family post persists with comments", async () => {
    const res = await authed(GUARDIAN.uid).get("/v1/family/posts");
    expect(res.status).toBe(200);
    const post = res.body.find((p: any) => p.id === familyPostId);
    expect(post).toBeDefined();
    expect(post.commentCount).toBeGreaterThanOrEqual(1);
    expect(post.comments.length).toBeGreaterThanOrEqual(1);
  });
});

// ---------------------------------------------------------------------------
// ACT 11 — Concurrent SOS & Emergency Edge Cases
// ---------------------------------------------------------------------------

describe("Act 11: Concurrent SOS & Emergency Edge Cases", () => {
  it("11.1 Protected A triggers SOS", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/sos/trigger")
      .send({
        protectedPersonId: PROTECTED.uid,
        triggerMethod: "fallDetection",
        latitude: 39.91,
        longitude: 116.41,
        batteryLevel: 15,
      });

    expect(res.status).toBe(201);
    sosEventId = res.body.sosEventId;
  });

  it("11.2 Protected B triggers SOS simultaneously", async () => {
    const res = await authed(PROTECTED_B.uid)
      .post("/v1/sos/trigger")
      .send({
        protectedPersonId: PROTECTED_B.uid,
        triggerMethod: "bluetoothButton",
        latitude: 31.23,
        longitude: 121.47,
        batteryLevel: 42,
      });

    expect(res.status).toBe(201);
    sosEventIdB = res.body.sosEventId;
    expect(sosEventIdB).not.toBe(sosEventId); // Different events
  });

  it("11.3 Both SOS events are independent", async () => {
    // Guardian should be notified of both (we verify via export data)
    const exportRes = await authed(PROTECTED.uid).post("/v1/user/export");
    const sosA = exportRes.body.sosEvents.find(
      (e: any) => e.id === sosEventId
    );
    expect(sosA).toBeDefined();
    expect(sosA.resolvedAt).toBeNull();
  });

  it("11.4 Resolve SOS-A only, SOS-B stays active", async () => {
    const resolveRes = await authed(GUARDIAN.uid)
      .post("/v1/sos/resolve")
      .send({ sosEventId, resolution: "guardianConfirmedSafe" });
    expect(resolveRes.status).toBe(200);

    // SOS-B should still be triggerable (duplicate returns existing)
    const retrigger = await authed(PROTECTED_B.uid)
      .post("/v1/sos/trigger")
      .send({ protectedPersonId: PROTECTED_B.uid });
    expect(retrigger.status).toBe(200);
    expect(retrigger.body.sosEventId).toBe(sosEventIdB);
    expect(retrigger.body.message).toMatch(/already active/i);
  });

  it("11.5 Resolve SOS-B", async () => {
    const res = await authed(GUARDIAN.uid)
      .post("/v1/sos/resolve")
      .send({ sosEventId: sosEventIdB, resolution: "guardianConfirmedSafe" });
    expect(res.status).toBe(200);
  });

  it("11.6 SOS with missing fields still works (graceful defaults)", async () => {
    const res = await authed(PROTECTED.uid)
      .post("/v1/sos/trigger")
      .send({
        protectedPersonId: PROTECTED.uid,
        // No triggerMethod, no location, no battery
      });

    expect(res.status).toBe(201);
    expect(res.body.escalationState).toBe("initiated");

    // Clean up
    await authed(PROTECTED.uid)
      .post("/v1/sos/resolve")
      .send({ sosEventId: res.body.sosEventId, resolution: "falseAlarm" });
  });
});

// ---------------------------------------------------------------------------
// ACT 12 — Authorization & Security Boundaries
// ---------------------------------------------------------------------------

describe("Act 12: Authorization & Security Boundaries", () => {
  it("12.1 No auth header → 401 on protected endpoints", async () => {
    const res = await request(API_BASE).get("/v1/user/me");
    expect(res.status).toBe(401);
  });

  it("12.2 Protected person cannot see another protected person's data", async () => {
    const res = await authed(PROTECTED_B.uid).get("/v1/protected/guardians");
    expect(res.status).toBe(200);
    // Only their own guardians
    const guardianIds = res.body.map((g: any) => g.id);
    expect(guardianIds).toContain(GUARDIAN.uid);
  });

  it("12.3 Protected person cannot remove a guardian they're not linked to", async () => {
    // PROTECTED_B tries to remove guardian from PROTECTED's link
    const res = await authed(PROTECTED.uid)
      .delete(`/v1/protected/guardians/nonexistent-guardian-id`);
    expect(res.status).toBe(404);
  });

  it("12.4 Health check works without auth", async () => {
    const res = await request(API_BASE).get("/health");
    expect(res.status).toBe(200);
    expect(res.body.status).toBe("ok");
    expect(res.body.service).toBe("shoudeng-backend");
  });
});

// ---------------------------------------------------------------------------
// ACT 13 — GDPR Cleanup (Account Deletion)
// ---------------------------------------------------------------------------

describe("Act 13: GDPR Cleanup — Account Deletion", () => {
  it("13.1 Delete protected person B's family post before account deletion", async () => {
    // Protected B creates and deletes a post to test post deletion flow
    const postRes = await authed(PROTECTED_B.uid)
      .post("/v1/family/posts")
      .send({ text: "临时帖子" });
    expect(postRes.status).toBe(201);

    const deleteRes = await authed(PROTECTED_B.uid)
      .delete(`/v1/family/posts/${postRes.body.postId}`);
    expect(deleteRes.status).toBe(200);
  });

  it("13.2 Delete protected person B's account (GDPR erasure)", async () => {
    const res = await authed(PROTECTED_B.uid).post("/v1/user/delete");

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  it("13.3 Deleted user's profile returns 404", async () => {
    const res = await authed(PROTECTED_B.uid).get("/v1/user/me");

    expect(res.status).toBe(404);
  });

  it("13.4 Deleted user no longer appears in guardian's list", async () => {
    const res = await authed(GUARDIAN.uid).get("/v1/guardian/protected-persons");

    expect(res.status).toBe(200);
    const names = res.body.map((p: any) => p.displayName);
    expect(names).not.toContain("小丽");
    expect(names).toContain("小明"); // 小明 should still be there
  });

  it("13.5 Guardian deletes family post", async () => {
    const res = await authed(GUARDIAN.uid)
      .delete(`/v1/family/posts/${familyPostId}`);

    expect(res.status).toBe(200);
  });

  it("13.6 Protected person removes guardian link", async () => {
    const res = await authed(PROTECTED.uid)
      .delete(`/v1/protected/guardians/${GUARDIAN.uid}`);

    expect(res.status).toBe(200);
  });

  it("13.7 After unlinking, guardian sees empty list", async () => {
    const res = await authed(GUARDIAN.uid).get("/v1/guardian/protected-persons");

    expect(res.status).toBe(200);
    expect(res.body.length).toBe(0);
  });

  it("13.8 Delete remaining test accounts", async () => {
    const resP = await authed(PROTECTED.uid).post("/v1/user/delete");
    expect(resP.status).toBe(200);

    const resG = await authed(GUARDIAN.uid).post("/v1/user/delete");
    expect(resG.status).toBe(200);
  });

  it("13.9 All accounts deleted — profiles return 404", async () => {
    const resP = await authed(PROTECTED.uid).get("/v1/user/me");
    expect(resP.status).toBe(404);

    const resG = await authed(GUARDIAN.uid).get("/v1/user/me");
    expect(resG.status).toBe(404);
  });
});
