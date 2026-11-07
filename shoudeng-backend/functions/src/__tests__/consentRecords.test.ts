/**
 * Consent taps logged on the phone reach the account (POST /v1/user/consent { records }):
 *  - every record becomes a consent_audit row (kept when an account is deleted)
 *  - the newest Terms / onboarding / guardian-duty versions land on the user doc
 *  - bad batches are refused whole (the app keeps them and resends)
 *  - the older { type: "cross_border_transfer" } shape still works
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
const mockAudit: Record<string, unknown>[] = [];
jest.mock("../services/bigquery", () => ({
  ...jest.requireActual("../services/bigquery"),
  insertConsentAudit: jest.fn(async (row: Record<string, unknown>) => { mockAudit.push(row); }),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor } from "./helpers/fakeAdmin";
import { parseConsentRecords, latestConsentVersions } from "../services/consent";

const app = express();
app.use(express.json());
app.use("/v1/user", require("../routes/user").default);
const post = (uid: string, body: object) =>
  request(app).post("/v1/user/consent").set("Authorization", `Bearer ${tokenFor(uid)}`).send(body);

const rec = (item: string, copyVersion: string, at: string, action = "granted") =>
  ({ item, copyVersion, action, at, appVersion: "1.0.0", locale: "zh_CN", deviceId: "DEVICE-1" });

beforeEach(() => {
  resetFakeAdmin();
  mockAudit.length = 0;
  seed("users/mom", { displayName: "秀兰", role: "protected" });
});

describe("POST /v1/user/consent { records }", () => {
  it("stores every tap and the latest versions", async () => {
    const res = await post("mom", { records: [
      rec("onboard.not_emergency", "v2.0", "2026-11-06T10:00:00Z"),
      rec("onboard.scope", "v2.0", "2026-11-06T10:00:05Z"),
      rec("terms.accept", "2026-11-06", "2026-11-06T10:01:00Z"),
      rec("consent.fall_detect", "v1.1", "2026-11-06T10:05:00Z", "denied"),
    ] });
    expect(res.status).toBe(200);
    expect(res.body.recorded).toBe(4);
    expect(mockAudit).toHaveLength(4);
    expect(mockAudit[0]).toMatchObject({ userId: "mom", consentType: "onboard.not_emergency", action: "granted" });
    expect(String(mockAudit[0].detail)).toContain("copy v2.0");
    expect(mockAudit[3]).toMatchObject({ consentType: "consent.fall_detect", action: "denied" });
    const user = readDoc("users/mom")!;
    expect(user.termsVersion).toBe("2026-11-06");
    expect(user.onboardingCopyVersion).toBe("v2.0");
  });

  it("refuses a bad batch whole", async () => {
    expect((await post("mom", { records: [] })).status).toBe(400);
    expect((await post("mom", { records: [rec("Bad Item!", "v1", "2026-11-06T10:00:00Z")] })).status).toBe(400);
    expect((await post("mom", { records: [rec("terms.accept", "v1", "not a date")] })).status).toBe(400);
    expect((await post("mom", { records: Array.from({ length: 101 }, () => rec("onboard.scope", "v2.0", "2026-11-06T10:00:00Z")) })).status).toBe(400);
    expect(mockAudit).toHaveLength(0);
  });

  it("needs a signed-in user", async () => {
    const res = await request(app).post("/v1/user/consent").send({ records: [rec("terms.accept", "v1", "2026-11-06T10:00:00Z")] });
    expect(res.status).toBe(401);
  });

  it("still takes the data-transfer consent", async () => {
    const res = await post("mom", { type: "cross_border_transfer", version: "2026-10-31" });
    expect(res.status).toBe(200);
    expect(readDoc("users/mom")!.dataTransferConsentVersion).toBe("2026-10-31");
  });
});

describe("consent helpers", () => {
  it("keeps the newest granted version, ignores denials", () => {
    const parsed = parseConsentRecords([
      rec("guardian.duty", "v1.0", "2026-11-06T09:00:00Z"),
      rec("terms.accept", "2026-10-01", "2026-10-01T09:00:00Z"),
      rec("terms.accept", "2026-11-06", "2026-11-06T09:00:00Z"),
      rec("terms.accept", "2027-01-01", "2026-11-07T09:00:00Z", "revoked"),
    ])!;
    expect(latestConsentVersions(parsed)).toMatchObject({ termsVersion: "2026-11-06", guardianDutyVersion: "v1.0" });
  });
});
