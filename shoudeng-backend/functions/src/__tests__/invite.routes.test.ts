/**
 * Invites carry their own direction (docs/roles/ROLES.md, phase A):
 *  - any two accounts link in the invite's direction, whatever their account roles;
 *  - invites made before `inviterRole` existed use the creator's role;
 *  - GET /v1/invite/preview is read-only;
 *  - every failure has a machine-readable `code`.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

const mockConsentAudits: any[] = [];
jest.mock("../services/bigquery", () => ({
  insertConsentAudit: jest.fn(async (row: any) => { mockConsentAudits.push(row); }),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, listDocs, ts, tokenFor } from "./helpers/fakeAdmin";

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use("/v1/invite", require("../routes/invite").default);
  return app;
}

const app = buildApp();
const as = (uid: string) => ({
  post: (path: string, body: object = {}) =>
    request(app).post(path).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
  get: (path: string) =>
    request(app).get(path).set("Authorization", `Bearer ${tokenFor(uid)}`),
});

const HOUR = 60 * 60 * 1000;

function seedUser(id: string, role: "protected" | "guardian", displayName = id) {
  seed(`users/${id}`, { displayName, avatarInitial: displayName.charAt(0), role });
}

function seedInvite(id: string, data: Record<string, unknown>) {
  seed(`invites/${id}`, {
    code: "ABC123",
    acceptedBy: null,
    status: "pending",
    createdAt: ts(Date.now() - HOUR),
    expiresAt: ts(Date.now() + HOUR),
    ...data,
  });
}

async function createInvite(uid: string, inviterRole?: string) {
  const res = await as(uid).post("/v1/invite/create", inviterRole ? { inviterRole } : {});
  expect(res.status).toBe(201);
  return res.body as { code: string; inviteId: string; inviterRole: string };
}

beforeEach(() => {
  resetFakeAdmin();
  mockConsentAudits.length = 0;
});

describe("POST /v1/invite/create", () => {
  it("stores the direction the app sends", async () => {
    seedUser("mom", "protected");
    const { inviteId, inviterRole } = await createInvite("mom", "guardian");
    expect(inviterRole).toBe("guardian");
    expect(readDoc(`invites/${inviteId}`)).toMatchObject({ inviterRole: "guardian", createdBy: "mom", status: "pending" });
  });

  it("defaults to the creator's account role for older apps", async () => {
    seedUser("mom", "protected");
    seedUser("dad", "guardian");
    expect((await createInvite("mom")).inviterRole).toBe("protected");
    // An old guardian app sends { role: "guardian" }; the account role decides anyway
    const res = await as("dad").post("/v1/invite/create", { role: "protected" });
    expect(res.body.inviterRole).toBe("guardian");
  });

  it("ignores an unknown inviterRole", async () => {
    seedUser("mom", "protected");
    expect((await createInvite("mom", "admin")).inviterRole).toBe("protected");
  });
});

describe("POST /v1/invite/accept links in the invite's direction", () => {
  const cases: [string, "protected" | "guardian", "protected" | "guardian"][] = [
    ["both protected", "protected", "protected"],
    ["both guardians", "guardian", "guardian"],
    ["protected inviter, guardian acceptor", "protected", "guardian"],
    ["guardian inviter, protected acceptor", "guardian", "protected"],
  ];

  for (const [label, inviterAccountRole, acceptorAccountRole] of cases) {
    for (const direction of ["protected", "guardian"] as const) {
      it(`${label}: inviterRole=${direction}`, async () => {
        seedUser("inviter", inviterAccountRole);
        seedUser("acceptor", acceptorAccountRole);
        const { code } = await createInvite("inviter", direction);

        const res = await as("acceptor").post("/v1/invite/accept", { code });
        expect(res.status).toBe(200);

        const guardianId = direction === "protected" ? "acceptor" : "inviter";
        const protectedPersonId = direction === "protected" ? "inviter" : "acceptor";
        expect(res.body).toMatchObject({
          success: true,
          guardianId,
          protectedPersonId,
          linkId: `${guardianId}_${protectedPersonId}`,
          acceptorRole: direction === "protected" ? "guardian" : "protected",
        });
        expect(readDoc(`guardian_links/${guardianId}_${protectedPersonId}`)).toMatchObject({ status: "active", guardianId, protectedPersonId });
        expect(listDocs("invites")[0].data).toMatchObject({ status: "accepted", acceptedBy: "acceptor" });
        // Acceptor had no links yet: their home view becomes their side of the link
        expect(readDoc("users/acceptor")!.role).toBe(res.body.acceptorRole);
        // The inviter's account is never touched
        expect(readDoc("users/inviter")!.role).toBe(inviterAccountRole);
      });
    }
  }

  it("keeps the home view of an acceptor who already has links", async () => {
    seedUser("mom", "protected");
    seedUser("grandma", "protected");
    seed("guardian_links/kid_mom", { guardianId: "kid", protectedPersonId: "mom", status: "active" });
    // Grandma asks Mom to guard her
    seedInvite("i1", { createdBy: "grandma", inviterRole: "protected" });

    const res = await as("mom").post("/v1/invite/accept", { code: "abc123" });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ guardianId: "mom", protectedPersonId: "grandma" });
    expect(readDoc("users/mom")!.role).toBe("protected");
  });

  it("records consent and the guardian's critical-alert choice", async () => {
    seedUser("mom", "protected");
    seedUser("kid", "protected");
    const { code } = await createInvite("mom", "protected");
    await as("kid").post("/v1/invite/accept", { code, criticalAlertConsent: true });

    expect(mockConsentAudits.map((a) => a.consentType)).toEqual(["guardian_link", "sos_critical_alerts"]);
    expect(mockConsentAudits[0]).toMatchObject({ userId: "mom", grantedTo: "kid" });
    expect(mockConsentAudits[1]).toMatchObject({ userId: "kid", action: "granted" });
    expect(readDoc("users/kid")!.notificationPrefs).toEqual({ sosCriticalAlerts: true });
  });

  it("does not record a critical-alert choice for someone who becomes protected", async () => {
    seedUser("dad", "guardian");
    seedUser("mom", "guardian");
    const { code } = await createInvite("dad", "guardian");
    await as("mom").post("/v1/invite/accept", { code, criticalAlertConsent: true });
    expect(mockConsentAudits.map((a) => a.consentType)).toEqual(["guardian_link"]);
    expect(readDoc("users/mom")!.notificationPrefs).toBeUndefined();
  });

  it("accepts by inviteId too", async () => {
    seedUser("mom", "protected");
    seedUser("kid", "guardian");
    const { inviteId } = await createInvite("mom", "protected");
    const res = await as("kid").post("/v1/invite/accept", { inviteId });
    expect(res.status).toBe(200);
    expect(res.body.guardianId).toBe("kid");
  });
});

describe("invites created before inviterRole existed", () => {
  it("use the creator's role at accept time (protected creator)", async () => {
    seedUser("mom", "protected");
    seedUser("kid", "protected");
    seedInvite("old", { createdBy: "mom", role: "guardian" }); // old default `role`, no inviterRole

    const res = await as("kid").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ guardianId: "kid", protectedPersonId: "mom" });
  });

  it("use the creator's role at accept time (guardian creator)", async () => {
    seedUser("dad", "guardian");
    seedUser("mom", "guardian");
    seedInvite("old", { createdBy: "dad", role: "guardian" });

    const res = await as("mom").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ guardianId: "dad", protectedPersonId: "mom" });
    expect(readDoc("users/mom")!.role).toBe("protected");
  });

  it("preview reports the inferred direction", async () => {
    seedUser("mom", "protected", "Mom");
    seedUser("kid", "guardian");
    seedInvite("old", { createdBy: "mom" });
    const res = await as("kid").get("/v1/invite/preview?code=ABC123");
    expect(res.body.inviterRole).toBe("protected");
  });
});

describe("GET /v1/invite/preview", () => {
  it("returns the inviter and direction without changing anything", async () => {
    seedUser("mom", "protected", "Chen Xiulan");
    seedUser("kid", "protected");
    const { code, inviteId } = await createInvite("mom", "protected");
    const before = readDoc(`invites/${inviteId}`);

    const res = await as("kid").get(`/v1/invite/preview?code=${code.toLowerCase()}`);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      code,
      inviterName: "Chen Xiulan",
      avatarInitial: "C",
      inviterRole: "protected",
      status: "pending",
      isOwnInvite: false,
    });
    expect(new Date(res.body.expiresAt).getTime()).toBeGreaterThan(Date.now());

    expect(readDoc(`invites/${inviteId}`)).toEqual(before);
    expect(listDocs("guardian_links")).toEqual([]);
    expect(readDoc("users/kid")!.role).toBe("protected");
  });

  it("flags the user's own invite", async () => {
    seedUser("mom", "protected");
    const { code } = await createInvite("mom");
    const res = await as("mom").get(`/v1/invite/preview?code=${code}`);
    expect(res.body.isOwnInvite).toBe(true);
  });

  it("reports expired and used invites without the inviter's name", async () => {
    seedUser("mom", "protected", "Mom");
    seedInvite("gone", { code: "EEEEEE", createdBy: "mom", expiresAt: ts(Date.now() - 1000) });
    seedInvite("used", { code: "UUUUUU", createdBy: "mom", status: "accepted", acceptedBy: "x" });

    const expired = await as("kid").get("/v1/invite/preview?code=EEEEEE");
    expect(expired.body).toMatchObject({ status: "expired", inviterName: null });
    const used = await as("kid").get("/v1/invite/preview?code=UUUUUU");
    expect(used.body).toMatchObject({ status: "accepted", inviterName: null });
  });

  it("prefers the pending invite when an old one shares the code", async () => {
    seedUser("mom", "protected", "Mom");
    seedInvite("old", { createdBy: "mom", status: "accepted", createdAt: ts(Date.now() - 3 * HOUR) });
    seedInvite("new", { createdBy: "mom" });
    const res = await as("kid").get("/v1/invite/preview?code=ABC123");
    expect(res.body.status).toBe("pending");
  });

  it("404s with NOT_FOUND for an unknown or malformed code", async () => {
    for (const q of ["?code=ZZZZZZ", "?code=", "", "?code=%24%24"]) {
      const res = await as("kid").get(`/v1/invite/preview${q}`);
      expect(res.status).toBe(404);
      expect(res.body.code).toBe("NOT_FOUND");
    }
  });

  it("requires sign-in", async () => {
    const res = await request(app).get("/v1/invite/preview?code=ABC123");
    expect(res.status).toBe(401);
  });
});

describe("error codes", () => {
  beforeEach(() => {
    seedUser("mom", "protected");
    seedUser("kid", "guardian");
  });

  it("NOT_FOUND for an unknown code", async () => {
    const res = await as("kid").post("/v1/invite/accept", { code: "ZZZZZZ" });
    expect(res.status).toBe(404);
    expect(res.body).toMatchObject({ code: "NOT_FOUND", error: expect.any(String) });
  });

  it("NOT_FOUND for an unknown inviteId", async () => {
    const res = await as("kid").post("/v1/invite/accept", { inviteId: "nope" });
    expect(res.status).toBe(404);
    expect(res.body.code).toBe("NOT_FOUND");
  });

  it("INVITE_EXPIRED for a pending invite past its expiry", async () => {
    seedInvite("i", { createdBy: "mom", expiresAt: ts(Date.now() - 1000) });
    const res = await as("kid").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(410);
    expect(res.body.code).toBe("INVITE_EXPIRED");
    expect(listDocs("guardian_links")).toEqual([]);
  });

  it("INVITE_EXPIRED for an invite the cleanup job marked expired", async () => {
    seedInvite("i", { createdBy: "mom", status: "expired" });
    const res = await as("kid").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(410);
    expect(res.body.code).toBe("INVITE_EXPIRED");
  });

  it("INVITE_USED for an accepted invite", async () => {
    const { code } = await createInvite("mom", "protected");
    expect((await as("kid").post("/v1/invite/accept", { code })).status).toBe(200);
    seedUser("other", "guardian");
    const res = await as("other").post("/v1/invite/accept", { code });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("INVITE_USED");
  });

  it("SELF_ACCEPT for your own invite", async () => {
    const { code } = await createInvite("mom", "protected");
    const res = await as("mom").post("/v1/invite/accept", { code });
    expect(res.status).toBe(400);
    expect(res.body.code).toBe("SELF_ACCEPT");
  });

  it("PLAN_LIMIT when the inviter (guardian) is full", async () => {
    seed("guardian_links/kid_someone", { guardianId: "kid", protectedPersonId: "someone", status: "active" });
    seedUser("grandma", "protected");
    seedInvite("i", { createdBy: "kid", inviterRole: "guardian" });
    const res = await as("grandma").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(403);
    expect(res.body).toMatchObject({ code: "PLAN_LIMIT", upgrade: true, maxProtected: 1, guardianIsYou: false });
  });

  it("PLAN_LIMIT tells the acceptor when it is their own plan that is full", async () => {
    seed("guardian_links/kid_someone", { guardianId: "kid", protectedPersonId: "someone", status: "active" });
    seedInvite("i", { createdBy: "mom", inviterRole: "protected" });
    const res = await as("kid").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(403);
    expect(res.body).toMatchObject({ code: "PLAN_LIMIT", guardianIsYou: true });
  });

  it("re-linking the same pair doesn't count against the plan", async () => {
    seed("guardian_links/kid_mom", { guardianId: "kid", protectedPersonId: "mom", status: "active" });
    seedInvite("i", { createdBy: "mom", inviterRole: "protected" });
    const res = await as("kid").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(200);
  });

  it("USER_NOT_FOUND when the acceptor has no profile", async () => {
    seedInvite("i", { createdBy: "mom", inviterRole: "protected" });
    const res = await as("ghost").post("/v1/invite/accept", { code: "ABC123" });
    expect(res.status).toBe(404);
    expect(res.body.code).toBe("USER_NOT_FOUND");
  });

  it("400 without code or inviteId", async () => {
    const res = await as("kid").post("/v1/invite/accept", {});
    expect(res.status).toBe(400);
  });
});
