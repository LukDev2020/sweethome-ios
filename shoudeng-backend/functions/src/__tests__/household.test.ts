/**
 * Households (services/household.ts): one plan shared by the family.
 *  - Essential: 2 guardians + 2 protected; Family: 4 + 6; free: 1 + 1
 *  - everyone in a payer's household uses the payer's plan
 *  - limits are checked when a link is made, per household
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("../services/bigquery", () => ({ insertConsentAudit: jest.fn(async () => undefined) }));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, ts, tokenFor } from "./helpers/fakeAdmin";
import { checkNewLink, effectivePlanIn, householdIn, LinkGraph, householdSummary } from "../services/household";
import { PlanId } from "../services/payment";

const graph = (links: [string, string][], paid: Record<string, PlanId> = {}): LinkGraph => ({
  links: links.map(([guardianId, protectedPersonId]) => ({ guardianId, protectedPersonId })),
  paid: new Map(Object.entries(paid)),
});

describe("effective plan", () => {
  it("a free sibling uses the household plan of whoever pays for their parent", () => {
    const g = graph([["sarah", "mom"], ["sarah", "dad"], ["kevin", "mom"], ["kevin", "dad"]], { sarah: "family" });
    expect(effectivePlanIn(g, "kevin")).toEqual({ planId: "family", payerId: "sarah" });
    expect(effectivePlanIn(g, "mom")).toEqual({ planId: "family", payerId: "sarah" });
    expect(effectivePlanIn(g, "sarah")).toEqual({ planId: "family", payerId: "sarah" });
  });

  it("the best plan wins when someone is in two households", () => {
    const g = graph([["sarah", "mom"], ["bob", "grandma"], ["kevin", "mom"], ["kevin", "grandma"]],
      { sarah: "single", bob: "family" });
    expect(effectivePlanIn(g, "kevin").planId).toBe("family");
  });

  it("guarding someone nobody pays for gives nothing", () => {
    expect(effectivePlanIn(graph([["kevin", "mom"]]), "kevin")).toEqual({ planId: "free", payerId: null });
  });

  it("a household is the payer's protected people and all their guardians", () => {
    const h = householdIn(graph([["sarah", "mom"], ["kevin", "mom"], ["lucy", "dad"]], { sarah: "family" }), "sarah")!;
    expect([...h.protectedIds]).toEqual(["mom"]);
    expect([...h.guardianIds].sort()).toEqual(["kevin", "sarah"]);
  });
});

describe("limits on a new link", () => {
  it("free: 1 guardian + 1 protected", () => {
    expect(checkNewLink(graph([]), "sarah", "mom")).toBeNull();
    expect(checkNewLink(graph([["sarah", "mom"]]), "sarah", "dad"))
      .toMatchObject({ limit: "protected", max: 1, planId: "free", payerId: null });
    expect(checkNewLink(graph([["sarah", "mom"]]), "kevin", "mom"))
      .toMatchObject({ limit: "guardians", max: 1, planId: "free" });
  });

  it("Essential: Mom and Dad, two children", () => {
    const paid = { sarah: "single" as PlanId };
    expect(checkNewLink(graph([["sarah", "mom"]], paid), "sarah", "dad")).toBeNull();
    expect(checkNewLink(graph([["sarah", "mom"], ["sarah", "dad"]], paid), "sarah", "grandma"))
      .toMatchObject({ limit: "protected", max: 2, planId: "single", payerId: "sarah" });
    expect(checkNewLink(graph([["sarah", "mom"], ["sarah", "dad"]], paid), "kevin", "dad")).toBeNull();
    expect(checkNewLink(graph([["sarah", "mom"], ["kevin", "mom"]], paid), "lucy", "mom"))
      .toMatchObject({ limit: "guardians", max: 2, planId: "single", payerId: "sarah" });
  });

  it("a free sibling can follow both parents Sarah pays for — they don't take his free seat", () => {
    const g = graph([["sarah", "mom"], ["sarah", "dad"], ["kevin", "mom"]], { sarah: "family" });
    expect(checkNewLink(g, "kevin", "dad")).toBeNull();
  });

  it("Family: 6 protected, 4 guardians", () => {
    const six: [string, string][] = ["p1", "p2", "p3", "p4", "p5", "p6"].map((p) => ["sarah", p]);
    const paid = { sarah: "family" as PlanId };
    expect(checkNewLink(graph(six.slice(0, 5), paid), "sarah", "p6")).toBeNull();
    expect(checkNewLink(graph(six, paid), "sarah", "p7")).toMatchObject({ limit: "protected", max: 6 });
    const guardians: [string, string][] = [["sarah", "mom"], ["g2", "mom"], ["g3", "mom"]];
    expect(checkNewLink(graph(guardians, paid), "g4", "mom")).toBeNull();
    expect(checkNewLink(graph([...guardians, ["g4", "mom"]], paid), "g5", "mom"))
      .toMatchObject({ limit: "guardians", max: 4, planId: "family" });
  });

  it("guardians count across the whole household, not per person", () => {
    // Sarah (Essential) guards Mom and Dad; Kevin guards Mom → 2 guardians already
    const g = graph([["sarah", "mom"], ["sarah", "dad"], ["kevin", "mom"]], { sarah: "single" });
    expect(checkNewLink(g, "lucy", "dad")).toMatchObject({ limit: "guardians", max: 2 });
  });

  it("someone paying joins with their own plan's room", () => {
    // Mom already has a free guardian; Bob buys Family and joins
    expect(checkNewLink(graph([["kevin", "mom"]], { bob: "family" }), "bob", "mom")).toBeNull();
  });

  it("re-linking the same pair never counts", () => {
    expect(checkNewLink(graph([["sarah", "mom"]]), "sarah", "mom")).toBeNull();
  });
});

describe("POST /v1/invite/accept with households", () => {
  const app = express();
  app.use(express.json());
  app.use("/v1/invite", require("../routes/invite").default);
  const HOUR = 3600_000;

  beforeEach(() => resetFakeAdmin());

  const user = (id: string, role: string) => seed(`users/${id}`, { displayName: id, avatarInitial: id[0], role });
  const link = (g: string, p: string) => seed(`guardian_links/${g}_${p}`, { guardianId: g, protectedPersonId: p, status: "active" });
  const invite = (createdBy: string, inviterRole: string) => seed("invites/i", {
    code: "ABC123", acceptedBy: null, status: "pending", createdBy, inviterRole,
    createdAt: ts(Date.now() - HOUR), expiresAt: ts(Date.now() + HOUR),
  });
  const pays = (uid: string, planId: string) =>
    seed(`subscriptions/${uid}`, { userId: uid, planId, status: "active", currentPeriodEnd: ts(new Date(Date.now() + 30 * 86400_000)) });
  const accept = (uid: string) =>
    request(app).post("/v1/invite/accept").set("Authorization", `Bearer ${tokenFor(uid)}`).send({ code: "ABC123" });

  it("Kevin (free) can guard Dad when Sarah's Family plan already covers Mom and Dad", async () => {
    ["sarah", "kevin"].forEach((u) => user(u, "guardian"));
    ["mom", "dad"].forEach((u) => user(u, "protected"));
    pays("sarah", "family");
    link("sarah", "mom"); link("sarah", "dad"); link("kevin", "mom");
    invite("dad", "protected");
    expect((await accept("kevin")).status).toBe(200);
  });

  it("the fifth guardian of a Family household is refused, naming the guardian limit", async () => {
    ["sarah", "g2", "g3", "g4", "g5"].forEach((u) => user(u, "guardian"));
    user("mom", "protected");
    pays("sarah", "family");
    ["sarah", "g2", "g3", "g4"].forEach((g) => link(g, "mom"));
    invite("mom", "protected");
    const res = await accept("g5");
    expect(res.status).toBe(403);
    expect(res.body).toMatchObject({ code: "PLAN_LIMIT", limit: "guardians", max: 4, maxGuardians: 4, guardianIsYou: false });
  });

  it("Essential takes a second parent (it used to stop at one)", async () => {
    user("sarah", "guardian"); user("mom", "protected"); user("dad", "protected");
    pays("sarah", "single");
    link("sarah", "mom");
    invite("sarah", "guardian");
    expect((await accept("dad")).status).toBe(200);
  });

  it("summary shows the household plan, who pays, and seats used", async () => {
    ["sarah", "kevin"].forEach((u) => user(u, "guardian"));
    user("mom", "protected"); user("dad", "protected");
    pays("sarah", "family");
    link("sarah", "mom"); link("sarah", "dad"); link("kevin", "mom");
    expect(await householdSummary("kevin")).toEqual({
      planId: "family", payerId: "sarah", payerName: "sarah",
      guardians: 2, maxGuardians: 4, protected: 2, maxProtected: 6,
    });
  });
});
