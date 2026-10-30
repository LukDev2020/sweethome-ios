jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor, ts } from "./helpers/fakeAdmin";

const { app } = require("../app");
const auth = (uid: string) => ({ Authorization: `Bearer ${tokenFor(uid)}` });

beforeEach(() => {
  resetFakeAdmin();
  process.env.PUBLIC_API_BASE_URL = "https://us-central1-test.cloudfunctions.net/api";
  seed("users/mom", { displayName: "Mom" });
  seed("guardian_links/sarah_mom", { guardianId: "sarah", protectedPersonId: "mom", status: "active", permissions: { canSeeLocation: true } });
  seed("guardian_links/kevin_mom", { guardianId: "kevin", protectedPersonId: "mom", status: "active", permissions: { canSeeLocation: false } });
  seed("guardian_links/lucy_mom", { guardianId: "lucy", protectedPersonId: "mom", status: "revoked" });
});

describe("POST /v1/evidence/share authorization", () => {
  const share = (uid: string, body: object) => request(app).post("/v1/evidence/share").set(auth(uid)).send(body);

  it("the person and a guardian who can see location may share", async () => {
    expect((await share("mom", { protectedPersonId: "mom" })).status).toBe(200);
    const r = await share("sarah", { protectedPersonId: "mom", expiresInHours: 12 });
    expect(r.status).toBe(200);
    expect(r.body.shareUrl).toMatch(/^https:\/\/us-central1-test\.cloudfunctions\.net\/api\/v1\/evidence\/share\/[0-9a-f]{64}$/);
    expect(r.body.expiresInHours).toBe(12);
  });

  it("strangers, revoked guardians and guardians without location access may not", async () => {
    expect((await share("mallory", { protectedPersonId: "mom" })).status).toBe(403);
    expect((await share("lucy", { protectedPersonId: "mom" })).status).toBe(403);
    expect((await share("kevin", { protectedPersonId: "mom" })).status).toBe(403);
  });

  it("caps the link lifetime at 48 hours", async () => {
    expect((await share("mom", { protectedPersonId: "mom", expiresInHours: 24 * 30 })).status).toBe(400);
    expect((await share("mom", { protectedPersonId: "mom", expiresInHours: 0 })).status).toBe(400);
    const ok = await share("mom", { protectedPersonId: "mom", expiresInHours: 48 });
    const doc = readDoc(`evidence_shares/${ok.body.token}`)!;
    const hours = (doc.expiresAt.toMillis() - Date.now()) / 3600_000;
    expect(hours).toBeLessThanOrEqual(48.01);
  });
});

describe("GET /v1/evidence/share/:token", () => {
  it("serves a minimal HTML page to browsers (the SMS link) without internal data", async () => {
    seed("evidence_shares/tok", { protectedPersonId: "mom", expiresAt: ts(Date.now() + 3600_000), accessCount: 0, maxAccess: 10 });
    seed("user_telemetry/mom", { latitude: 30.6, longitude: 104.0, locationTimestamp: ts(Date.now()), batteryLevel: 0.2 });
    seed("sos_events/s1", { protectedPersonId: "mom", resolvedAt: null, triggeredAt: ts(Date.now()), acknowledgedBy: null,
      escalationLog: [{ callSid: "CA-secret" }], clientSOSIds: ["local-1"] });
    const html = await request(app).get("/v1/evidence/share/tok").set("Accept", "text/html");
    expect(html.status).toBe(200);
    expect(html.text).toContain("maps.apple.com/?ll=30.6,104");
    expect(html.text).toContain("battery 20%");
    expect(html.text).not.toContain("CA-secret");
    const json = await request(app).get("/v1/evidence/share/tok").set("Accept", "application/json");
    expect(JSON.stringify(json.body)).not.toContain("CA-secret");
    expect(JSON.stringify(json.body)).not.toContain("local-1");
    expect(json.body.activeSOS).toHaveLength(1);
  });

  it("expired links are gone", async () => {
    seed("evidence_shares/old", { protectedPersonId: "mom", expiresAt: ts(Date.now() - 1000), accessCount: 0, maxAccess: 10 });
    expect((await request(app).get("/v1/evidence/share/old")).status).toBe(410);
  });
});
