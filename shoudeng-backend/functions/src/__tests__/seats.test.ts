/**
 * Per-person pricing (services/seats.ts, docs/pricing/SEATS.md):
 *  - $1.99 per person looked after, $2.99 the first guardian, +$1 each further
 *    guardian, +$1 when the payer is looked after too; charged up to 4 + 3
 *  - sold as price levels; the app buys the cheapest level covering the seats
 *  - household limits follow the seats paid for; seats can't drop below the family
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("../services/bigquery", () => ({ insertConsentAudit: jest.fn(async () => undefined) }));

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor, FakeTimestamp } from "./helpers/fakeAdmin";
import {
  seatPriceCents, seatLevelFor, seatProductFor, seatProductId, seatLevelOf, productCovers, fitSeats,
  seatLimits, invalidSeatConfig, SEAT_LEVELS, SEAT_PRODUCT_IDS, SeatConfig,
} from "../services/seats";
import { checkNewLink, LinkGraph } from "../services/household";
import { mapProductToPlan, PlanId } from "../services/payment";

const cfg = (p: number, g = 1, dual = false): SeatConfig => ({ protected: p, guardians: g, dual });

describe("prices", () => {
  it("1v1, 1v2, 2v2 and both roles, monthly and yearly", () => {
    expect(seatPriceCents(cfg(1), "monthly")).toBe(498);
    expect(seatPriceCents(cfg(2), "monthly")).toBe(697);
    expect(seatPriceCents(cfg(2, 2), "monthly")).toBe(797);
    expect(seatPriceCents(cfg(2, 1, true), "monthly")).toBe(797);
    expect(seatPriceCents(cfg(1), "yearly")).toBe(4998);
    expect(seatPriceCents(cfg(2), "yearly")).toBe(6997);
  });

  it("capped at 4 looked after and 3 looking after", () => {
    expect(seatPriceCents(cfg(9, 7), "monthly")).toBe(seatPriceCents(cfg(4, 3), "monthly"));
    expect(seatLimits(cfg(4, 3))).toEqual({ maxProtected: -1, maxGuardians: -1 });
    expect(seatLimits(cfg(2, 1))).toEqual({ maxProtected: 2, maxGuardians: 1 });
  });

  it("every config lands on a level, the cheapest one at or above its price", () => {
    for (const period of ["monthly", "yearly"] as const) {
      for (let p = 1; p <= 12; p++) for (let g = 1; g <= 8; g++) for (const dual of [false, true]) {
        const level = seatLevelFor(cfg(p, g, dual), period);
        expect(level).not.toBeNull();
        expect(level!).toBeGreaterThanOrEqual(seatPriceCents(cfg(p, g, dual), period));
        expect(SEAT_LEVELS[period].filter((c) => c >= seatPriceCents(cfg(p, g, dual), period))[0]).toBe(level);
      }
    }
    expect(seatProductFor(cfg(1), "monthly")).toBe("com.shoudeng.app.seats.monthly.499");
    expect(seatProductFor(cfg(2), "monthly")).toBe("com.shoudeng.app.seats.monthly.699");
    expect(seatProductFor(cfg(2), "yearly")).toBe("com.shoudeng.app.seats.yearly.6999");
  });

  it("products: the levels in one plan; a level covers what's at or under it", () => {
    expect(SEAT_PRODUCT_IDS).toHaveLength(20);
    expect(SEAT_PRODUCT_IDS.every((id) => mapProductToPlan(id) === "seats")).toBe(true);
    expect(seatLevelOf("com.shoudeng.app.seats.yearly.8999")).toEqual({ period: "yearly", cents: 8999 });
    expect(seatLevelOf("com.shoudeng.app.family.monthly")).toBeNull();
    expect(productCovers(seatProductId("monthly", 699), cfg(2))).toBe(true);
    expect(productCovers(seatProductId("monthly", 699), cfg(3))).toBe(false);
  });

  it("a lower level (App Store downgrade) trims extra guardians, then both roles, then people", () => {
    expect(fitSeats(cfg(2, 2, true), seatProductId("monthly", 699))).toEqual(cfg(2, 1, false));
    expect(fitSeats(cfg(3, 1), seatProductId("monthly", 499))).toEqual(cfg(1, 1, false));
    expect(fitSeats(cfg(2), null)).toEqual(cfg(1, 1, false));
  });

  it("rejects configs that aren't whole numbers in range", () => {
    expect(invalidSeatConfig(cfg(1))).toBeNull();
    expect(invalidSeatConfig({ protected: 0, guardians: 1, dual: false })).toMatch(/protected/);
    expect(invalidSeatConfig({ protected: 1.5, guardians: 1, dual: false })).toMatch(/protected/);
    expect(invalidSeatConfig({ protected: 1, guardians: 9, dual: false })).toMatch(/guardians/);
    expect(invalidSeatConfig({ protected: 1, guardians: 1, dual: "yes" })).toMatch(/dual/);
  });
});

describe("household limits follow the seats paid for", () => {
  const graph = (links: [string, string][], seats?: SeatConfig): LinkGraph => ({
    links: links.map(([guardianId, protectedPersonId]) => ({ guardianId, protectedPersonId })),
    paid: new Map<string, PlanId>([["sarah", "seats"]]),
    seats: seats ? new Map([["sarah", seats]]) : undefined,
  });

  it("1v2: Mom and Dad; a third person needs another seat", () => {
    expect(checkNewLink(graph([["sarah", "mom"]], cfg(2)), "sarah", "dad")).toBeNull();
    expect(checkNewLink(graph([["sarah", "mom"], ["sarah", "dad"]], cfg(2)), "sarah", "grandma"))
      .toMatchObject({ limit: "protected", max: 2, planId: "seats", payerId: "sarah" });
  });

  it("a brother needs a guardian seat; at the cap anyone can join", () => {
    expect(checkNewLink(graph([["sarah", "mom"]], cfg(1, 1)), "kevin", "mom"))
      .toMatchObject({ limit: "guardians", max: 1, planId: "seats" });
    expect(checkNewLink(graph([["sarah", "mom"]], cfg(1, 2)), "kevin", "mom")).toBeNull();
    const four: [string, string][] = ["a", "b", "c", "d", "e"].map((p) => ["sarah", p]);
    expect(checkNewLink(graph(four, cfg(4)), "sarah", "f")).toBeNull();
  });

  it("before the app reports the seats: 1 + 1", () => {
    expect(checkNewLink(graph([["sarah", "mom"]]), "sarah", "dad"))
      .toMatchObject({ limit: "protected", max: 1, planId: "seats" });
  });
});

describe("routes", () => {
  const app = express();
  app.use(express.json());
  app.use("/v1/payment", require("../routes/payment").default);
  const put = (uid: string, body: object) =>
    request(app).put("/v1/payment/seats").set("Authorization", `Bearer ${tokenFor(uid)}`).send(body);
  const subscribe = (uid: string, productId: string, extra: object = {}) => seed(`subscriptions/${uid}`, {
    userId: uid, planId: "seats", status: "active", appleProductId: productId,
    currentPeriodStart: FakeTimestamp.now(),
    currentPeriodEnd: FakeTimestamp.fromDate(new Date(Date.now() + 30 * 86400_000)), ...extra,
  });

  beforeEach(() => {
    resetFakeAdmin();
    seed("users/sarah", { displayName: "Sarah", role: "guardian", createdAt: FakeTimestamp.now() });
  });

  it("pricing is public and lists the levels", async () => {
    const res = await request(app).get("/v1/payment/seats/pricing");
    expect(res.status).toBe(200);
    expect(res.body.prices.monthly).toMatchObject({ protected: 199, firstGuardian: 299 });
    expect(res.body.productIds).toHaveLength(20);
  });

  it("keeps seats the level pays for; asks for a higher level otherwise", async () => {
    subscribe("sarah", seatProductId("monthly", 699));
    expect((await put("sarah", cfg(2))).status).toBe(200);
    expect(readDoc("subscriptions/sarah")?.seats).toMatchObject({ protected: 2, guardians: 1, dual: false });
    const more = await put("sarah", cfg(3));
    expect(more.status).toBe(402);
    expect(more.body).toMatchObject({ code: "SEATS_NOT_PAID", productId: "com.shoudeng.app.seats.monthly.899" });
  });

  it("can't go below the people already in the family", async () => {
    subscribe("sarah", seatProductId("monthly", 699));
    seed("guardian_links/l1", { guardianId: "sarah", protectedPersonId: "mom", status: "active" });
    seed("guardian_links/l2", { guardianId: "sarah", protectedPersonId: "dad", status: "active" });
    const res = await put("sarah", cfg(1));
    expect(res.status).toBe(409);
    expect(res.body).toMatchObject({ code: "SEATS_IN_USE", inUse: { protected: 2, guardians: 1 } });
  });

  it("only for the per-person plan; bad input is a 400", async () => {
    expect((await put("sarah", cfg(1))).status).toBe(409);
    expect((await put("sarah", { protected: 0, guardians: 1, dual: false })).status).toBe(400);
  });

  it("the subscription shows the seats chosen and what they pay for", async () => {
    subscribe("sarah", seatProductId("monthly", 699), { seats: cfg(2, 2, true) });
    const res = await request(app).get("/v1/payment/subscription").set("Authorization", `Bearer ${tokenFor("sarah")}`);
    expect(res.status).toBe(200);
    expect(res.body.planId).toBe("seats");
    expect(res.body.seats.paidFor).toEqual(cfg(2, 1, false)); // $6.99 pays for 1v2 only
  });
});
