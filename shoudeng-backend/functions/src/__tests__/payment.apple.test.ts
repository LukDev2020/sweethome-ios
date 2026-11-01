/**
 * App Store subscriptions end to end (real payment router + fake Firestore):
 *  - Production-first verification with Sandbox fallback; APPLE_APP_ID from env
 *  - one Apple subscription unlocks one account (appAccountToken / originalTransactionId)
 *  - refunded / revoked / expired subscriptions fall back to the free plan
 *  - every App Store Server Notification type the backend handles
 *
 * The Apple library is replaced by a stand-in that "verifies" header.payload.sig
 * JWS the same way the real one checks bundle ID, environment and app ID.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({ query: jest.fn(async () => [[]]) })),
}));
jest.mock("../services/bigquery", () => ({
  insertConsentAudit: jest.fn(async () => undefined),
}));

jest.mock("@apple/app-store-server-library", () => {
  const Environment = { PRODUCTION: "Production", SANDBOX: "Sandbox", XCODE: "Xcode", LOCAL_TESTING: "LocalTesting" };
  const VerificationStatus = {
    OK: 0, VERIFICATION_FAILURE: 1, RETRYABLE_VERIFICATION_FAILURE: 2,
    INVALID_APP_IDENTIFIER: 3, INVALID_ENVIRONMENT: 4,
  };
  class VerificationException extends Error {
    constructor(public status: number) { super(`verification status ${status}`); }
  }
  const created: { environment: string; appAppleId: unknown }[] = [];
  const attempts: string[] = [];
  class SignedDataVerifier {
    constructor(_certs: Buffer[], _online: boolean, private environment: string,
                private bundleId: string, private appAppleId?: number) {
      if (environment === Environment.PRODUCTION && appAppleId === undefined) {
        throw new Error("appAppleId is required when the environment is Production");
      }
      created.push({ environment, appAppleId });
    }
    private decode(jws: string): any {
      attempts.push(this.environment);
      const [, payload, sig] = jws.split(".");
      if (sig === "forged") throw new VerificationException(VerificationStatus.VERIFICATION_FAILURE);
      if (sig === "ocsp") throw new VerificationException(VerificationStatus.RETRYABLE_VERIFICATION_FAILURE);
      return JSON.parse(Buffer.from(payload, "base64url").toString("utf8"));
    }
    async verifyAndDecodeTransaction(jws: string) {
      const p = this.decode(jws);
      if (p.bundleId !== this.bundleId) throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
      if (p.environment !== this.environment) throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
      return p;
    }
    async verifyAndDecodeRenewalInfo(jws: string) {
      const p = this.decode(jws);
      if (p.environment !== this.environment) throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
      return p;
    }
    async verifyAndDecodeNotification(jws: string) {
      const p = this.decode(jws);
      const d = p.data ?? {};
      if (d.bundleId !== this.bundleId ||
          (this.environment === Environment.PRODUCTION && d.appAppleId !== this.appAppleId)) {
        throw new VerificationException(VerificationStatus.INVALID_APP_IDENTIFIER);
      }
      if (d.environment !== this.environment) throw new VerificationException(VerificationStatus.INVALID_ENVIRONMENT);
      return p;
    }
  }
  return { Environment, VerificationStatus, VerificationException, SignedDataVerifier, __created: created, __attempts: attempts };
});

import express from "express";
import request from "supertest";
import { resetFakeAdmin, seed, readDoc, ts, tokenFor } from "./helpers/fakeAdmin";
import {
  appAccountTokenFor, getSubscription, hasPaidAccess, resetAppleVerifiersForTests, verifyAppleReceipt,
} from "../services/payment";
import { requireFeature } from "../middleware/subscription";
import { paidRetentionByUser } from "../services/accountData";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const appleLib = require("@apple/app-store-server-library");

const APP_ID = 6700000001; // test value only
const DAY = 24 * 60 * 60 * 1000;
const BUNDLE = "com.shoudeng.app";

function jws(payload: object, sig = "sig"): string {
  return `eyJhbGciOiJFUzI1NiJ9.${Buffer.from(JSON.stringify(payload)).toString("base64url")}.${sig}`;
}

let txCounter = 0;
function tx(over: Record<string, unknown> = {}) {
  txCounter++;
  return {
    bundleId: BUNDLE,
    environment: "Production",
    productId: "com.shoudeng.app.family.monthly",
    originalTransactionId: "OTX1",
    transactionId: `TX${txCounter}`,
    purchaseDate: Date.now() - DAY,
    expiresDate: Date.now() + 29 * DAY,
    ...over,
  };
}

function notification(type: string, transaction: object, opts: { subtype?: string; renewal?: object; environment?: string; appAppleId?: number | null } = {}) {
  const environment = opts.environment ?? "Production";
  return jws({
    notificationType: type,
    subtype: opts.subtype,
    data: {
      bundleId: BUNDLE,
      environment,
      appAppleId: opts.appAppleId === null ? undefined : (opts.appAppleId ?? (environment === "Production" ? APP_ID : undefined)),
      signedTransactionInfo: jws(transaction),
      signedRenewalInfo: opts.renewal ? jws({ environment, ...opts.renewal }) : undefined,
    },
  });
}

function buildApp() {
  const app = express();
  app.use(express.json());
  app.use("/v1/payment", require("../routes/payment").default);
  app.use("/v1/user", require("../routes/user").default);
  app.get("/gated", (req, _res, next) => { req.uid = String(req.query.uid); next(); },
    requireFeature("export_pdf"), (_req, res) => { res.json({ ok: true }); });
  return app;
}
const app = buildApp();

const as = (uid: string) => ({
  post: (path: string, body: object = {}) =>
    request(app).post(path).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
  get: (path: string) => request(app).get(path).set("Authorization", `Bearer ${tokenFor(uid)}`),
});
const webhook = (signedPayload: string) => request(app).post("/v1/payment/apple-webhook").send({ signedPayload });

function seedUser(id: string, withToken = true) {
  seed(`users/${id}`, {
    displayName: id, role: "guardian", avatarInitial: id[0], createdAt: ts(Date.now() - 30 * DAY),
    ...(withToken ? { appAccountToken: appAccountTokenFor(id) } : {}),
  });
}

const sub = (uid: string) => readDoc(`subscriptions/${uid}`);

beforeEach(() => {
  resetFakeAdmin();
  process.env.APPLE_APP_ID = String(APP_ID);
  delete process.env.APPLE_ALLOW_SANDBOX;
  resetAppleVerifiersForTests();
  appleLib.__created.length = 0;
  appleLib.__attempts.length = 0;
  seedUser("alice");
  seedUser("bob");
});

afterAll(() => {
  delete process.env.APPLE_APP_ID;
  resetAppleVerifiersForTests();
});

// ---------------------------------------------------------------------------

describe("appAccountToken", () => {
  test("is a UUID v5 of the uid (the iOS app derives the same value)", () => {
    // Same vector as ShouDengTests/StoreKitPurchaseTests.swift
    expect(appAccountTokenFor("user-123")).toBe("2596f80f-e7ad-5757-8688-47d61878a0b9");
    expect(appAccountTokenFor("alice")).not.toBe(appAccountTokenFor("bob"));
  });

  test("GET /v1/user/me stores it on the user doc", async () => {
    seedUser("carol", false);
    const res = await as("carol").get("/v1/user/me");
    expect(res.status).toBe(200);
    await new Promise((r) => setImmediate(r));
    expect(readDoc("users/carol")?.appAccountToken).toBe(appAccountTokenFor("carol"));
  });
});

describe("environment: Production first, Sandbox fallback", () => {
  test("a Production transaction verifies with the Production verifier only", async () => {
    const r = await verifyAppleReceipt(jws(tx()));
    expect(r.valid).toBe(true);
    expect(r.environment).toBe("Production");
    expect(appleLib.__attempts).toEqual(["Production"]);
    expect(appleLib.__created).toEqual([
      { environment: "Production", appAppleId: APP_ID },
      { environment: "Sandbox", appAppleId: undefined },
    ]);
  });

  test("a Sandbox (TestFlight) transaction falls back to Sandbox", async () => {
    const r = await verifyAppleReceipt(jws(tx({ environment: "Sandbox" })));
    expect(r.valid).toBe(true);
    expect(r.environment).toBe("Sandbox");
    expect(appleLib.__attempts).toEqual(["Production", "Sandbox"]);
  });

  test("APPLE_ALLOW_SANDBOX=false refuses Sandbox transactions", async () => {
    process.env.APPLE_ALLOW_SANDBOX = "false";
    resetAppleVerifiersForTests();
    expect((await verifyAppleReceipt(jws(tx({ environment: "Sandbox" })))).valid).toBe(false);
    expect((await verifyAppleReceipt(jws(tx()))).valid).toBe(true);
  });

  test("Xcode (local StoreKit) transactions are refused", async () => {
    expect((await verifyAppleReceipt(jws(tx({ environment: "Xcode" })))).valid).toBe(false);
  });

  test("a forged signature is refused without trying Sandbox", async () => {
    const r = await verifyAppleReceipt(jws(tx(), "forged"));
    expect(r.valid).toBe(false);
    expect(appleLib.__attempts).toEqual(["Production"]);
  });

  test("wrong bundle ID is refused", async () => {
    expect((await verifyAppleReceipt(jws(tx({ bundleId: "com.other.app" })))).valid).toBe(false);
  });

  test("without APPLE_APP_ID, Production transactions still verify", async () => {
    delete process.env.APPLE_APP_ID;
    resetAppleVerifiersForTests();
    const res = await as("alice").post("/v1/payment/verify-receipt", {
      signedTransaction: jws(tx({ appAccountToken: appAccountTokenFor("alice") })),
    });
    expect(res.status).toBe(200);
    expect(res.body.subscription.planId).toBe("family");
  });

  test("without APPLE_APP_ID, Production notifications are refused (401) so Apple retries", async () => {
    delete process.env.APPLE_APP_ID;
    resetAppleVerifiersForTests();
    const res = await webhook(notification("DID_RENEW", tx()));
    expect(res.status).toBe(401);
  });

  test("with APPLE_APP_ID, Production notifications are accepted; Sandbox ones fall back", async () => {
    await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: jws(tx({ appAccountToken: appAccountTokenFor("alice") })) });
    expect((await webhook(notification("DID_RENEW", tx()))).status).toBe(200);
    const sandbox = await webhook(notification("DID_RENEW", tx({ environment: "Sandbox" }), { environment: "Sandbox" }));
    expect(sandbox.status).toBe(200);
    expect(sub("alice")?.environment).toBe("Sandbox");
  });

  test("a notification for another app ID is refused", async () => {
    expect((await webhook(notification("DID_RENEW", tx(), { appAppleId: 123 }))).status).toBe(401);
  });

  test("Apple's online check failing answers 503 (retry later)", async () => {
    const res = await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: jws(tx(), "ocsp") });
    expect(res.status).toBe(503);
    expect((await webhook(jws({ notificationType: "TEST" }, "ocsp"))).status).toBe(503);
  });

  test("without root certificates nothing is accepted outside jest / the emulator", async () => {
    let isolated: typeof import("../services/payment") | undefined;
    jest.isolateModules(() => {
      jest.doMock("fs", () => ({ ...jest.requireActual("fs"), existsSync: () => false }));
      isolated = require("../services/payment");
    });
    const worker = process.env.JEST_WORKER_ID;
    try {
      expect((await isolated!.verifyAppleReceipt(jws(tx()))).valid).toBe(true); // jest: payload-only
      delete process.env.JEST_WORKER_ID;
      isolated!.resetAppleVerifiersForTests();
      expect((await isolated!.verifyAppleReceipt(jws(tx()))).valid).toBe(false);
      await expect(isolated!.handleAppleNotification(notification("DID_RENEW", tx()))).rejects.toThrow();
    } finally {
      process.env.JEST_WORKER_ID = worker;
    }
  });
});

describe("one subscription, one account", () => {
  test("a purchase with my appAccountToken binds the subscription to me", async () => {
    const res = await as("alice").post("/v1/payment/verify-receipt", {
      signedTransaction: jws(tx({ appAccountToken: appAccountTokenFor("alice") })),
    });
    expect(res.status).toBe(200);
    expect(res.body.subscription.planId).toBe("family");
    expect(readDoc("apple_subscription_owners/OTX1")?.uid).toBe("alice");
    expect(sub("alice")).toMatchObject({ status: "active", environment: "Production", appAccountToken: appAccountTokenFor("alice") });
  });

  test("someone else's JWS (their appAccountToken) is refused — replay", async () => {
    const signed = jws(tx({ appAccountToken: appAccountTokenFor("alice") }));
    expect((await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: signed })).status).toBe(200);
    const res = await as("bob").post("/v1/payment/verify-receipt", { signedTransaction: signed });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe("SUBSCRIPTION_OWNED_BY_OTHER_ACCOUNT");
    expect(sub("bob")).toBeUndefined();
    // …even before alice ever reported it (her token is on her user doc)
    resetFakeAdmin(); seedUser("alice"); seedUser("bob");
    expect((await as("bob").post("/v1/payment/verify-receipt", { signedTransaction: signed })).status).toBe(409);
  });

  test("without a token, an originalTransactionId already bound to another user is refused", async () => {
    const signed = jws(tx());
    expect((await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: signed })).status).toBe(200);
    expect((await as("bob").post("/v1/payment/verify-receipt", { signedTransaction: signed })).status).toBe(409);
    // the owner can send it again
    expect((await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: jws(tx()) })).status).toBe(200);
  });

  test("restore: someone else's subscription is refused, mine is restored", async () => {
    const signed = jws(tx({ appAccountToken: appAccountTokenFor("alice") }));
    const bob = await as("bob").post("/v1/payment/restore", { signedTransactions: [signed] });
    expect(bob.status).toBe(409);
    expect(bob.body.code).toBe("SUBSCRIPTION_OWNED_BY_OTHER_ACCOUNT");
    const alice = await as("alice").post("/v1/payment/restore", { signedTransactions: [signed] });
    expect(alice.status).toBe(200);
    expect(alice.body.restored).toBe(true);
    expect(alice.body.subscription.planId).toBe("family");
  });

  test("restore with nothing to restore answers restored:false", async () => {
    const res = await as("alice").post("/v1/payment/restore", { signedTransactions: [] });
    expect(res.status).toBe(200);
    expect(res.body.restored).toBe(false);
    expect(res.body.subscription.planId).toBe("free");
  });

  test("the subscription of a deleted account can be used by a new account", async () => {
    const signed = jws(tx());
    await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: signed });
    await require("./helpers/fakeAdmin").fakeDb.collection("users").doc("alice").delete();
    expect((await as("bob").post("/v1/payment/verify-receipt", { signedTransaction: signed })).status).toBe(200);
    expect(readDoc("apple_subscription_owners/OTX1")?.uid).toBe("bob");
  });

  test("a resubscription made with my token takes over a token-less binding", async () => {
    await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: jws(tx()) });
    const res = await as("bob").post("/v1/payment/verify-receipt", {
      signedTransaction: jws(tx({ appAccountToken: appAccountTokenFor("bob"), purchaseDate: Date.now() })),
    });
    expect(res.status).toBe(200);
    expect(readDoc("apple_subscription_owners/OTX1")?.uid).toBe("bob");
    expect(sub("alice")?.status).toBe("transferred");
    expect((await getSubscription("alice")).planId).toBe("free");
  });

  test("restore takes at most 20 transactions", async () => {
    const res = await as("alice").post("/v1/payment/restore", { signedTransactions: Array(21).fill(jws(tx())) });
    expect(res.status).toBe(400);
  });
});

describe("refunded / revoked / expired → free plan", () => {
  const future = () => ts(Date.now() + 10 * DAY);
  const past = () => ts(Date.now() - DAY);
  const seedSub = (data: Record<string, unknown>) =>
    seed("subscriptions/alice", { userId: "alice", planId: "family", currentPeriodEnd: future(), ...data });

  test.each([
    ["cancelled (refund)", { status: "cancelled" }],
    ["expired", { status: "expired" }],
    ["billing_retry", { status: "billing_retry" }],
    ["transferred", { status: "transferred" }],
    ["grace period over", { status: "grace_period", currentPeriodEnd: past(), gracePeriodEnd: past() }],
  ])("%s → free", async (_label, data) => {
    seedSub(data);
    const s = await getSubscription("alice");
    expect(s.planId).toBe("free");
    expect(s.features).not.toContain("export_pdf");
  });

  test("active but past its period → free, and marked expired", async () => {
    seedSub({ status: "active", currentPeriodEnd: past() });
    expect((await getSubscription("alice")).planId).toBe("free");
    expect(sub("alice")?.status).toBe("expired");
  });

  test("active / in grace period → paid", async () => {
    seedSub({ status: "active" });
    expect((await getSubscription("alice")).planId).toBe("family");
    seedSub({ status: "grace_period", currentPeriodEnd: past(), gracePeriodEnd: future() });
    expect((await getSubscription("alice")).planId).toBe("family");
  });

  test("a refunded user loses gated features", async () => {
    seedSub({ status: "cancelled" });
    expect((await request(app).get("/gated?uid=alice")).status).toBe(403);
    seedSub({ status: "active" });
    expect((await request(app).get("/gated?uid=alice")).status).toBe(200);
  });

  test("verify-receipt with a revoked transaction stores it as cancelled", async () => {
    const res = await as("alice").post("/v1/payment/verify-receipt", {
      signedTransaction: jws(tx({ revocationDate: Date.now() - 1000 })),
    });
    expect(res.status).toBe(200);
    expect(res.body.subscription.planId).toBe("free");
    expect(sub("alice")?.status).toBe("cancelled");
  });

  test("restore skips revoked and expired transactions", async () => {
    const res = await as("alice").post("/v1/payment/restore", {
      signedTransactions: [
        jws(tx({ revocationDate: Date.now() - 1000 })),
        jws(tx({ originalTransactionId: "OTX2", expiresDate: Date.now() - DAY })),
      ],
    });
    expect(res.body.restored).toBe(false);
    expect(sub("alice")).toBeUndefined();
  });

  test("paid retention ignores refunded subscriptions", async () => {
    seedSub({ status: "cancelled" });
    seed("subscriptions/bob", { userId: "bob", planId: "single", status: "active", currentPeriodEnd: future() });
    const paid = await paidRetentionByUser();
    expect(paid.has("alice")).toBe(false);
    expect(paid.has("bob")).toBe(true);
  });

  test("hasPaidAccess rejects unknown plans", () => {
    expect(hasPaidAccess({ planId: "gold", status: "active" })).toBe(false);
  });
});

describe("App Store Server Notifications", () => {
  const aliceTx = (over: Record<string, unknown> = {}) => tx({ appAccountToken: appAccountTokenFor("alice"), ...over });
  const purchase = () => as("alice").post("/v1/payment/verify-receipt", { signedTransaction: jws(aliceTx()) });

  test("SUBSCRIBED before the app reports it: linked to the account by appAccountToken", async () => {
    const res = await webhook(notification("SUBSCRIBED", aliceTx(), { subtype: "INITIAL_BUY", renewal: { autoRenewStatus: 1 } }));
    expect(res.status).toBe(200);
    expect(res.body.outcome).toBe("applied");
    expect(sub("alice")).toMatchObject({ planId: "family", status: "active", autoRenew: true });
    expect(readDoc("apple_subscription_owners/OTX1")?.uid).toBe("alice");
  });

  test("a notification nobody can be matched to is acknowledged (nothing to retry)", async () => {
    const res = await webhook(notification("SUBSCRIBED", tx({ appAccountToken: "00000000-0000-5000-8000-000000000000" })));
    expect(res.status).toBe(200);
    expect(res.body.outcome).toBe("unmatched");
  });

  test("DID_RENEW extends the period", async () => {
    await purchase();
    const newEnd = Date.now() + 60 * DAY;
    await webhook(notification("DID_RENEW", aliceTx({ expiresDate: newEnd, purchaseDate: Date.now() })));
    expect(sub("alice")?.currentPeriodEnd.toMillis()).toBe(newEnd);
    expect(sub("alice")?.status).toBe("active");
  });

  test("DID_CHANGE_RENEWAL_PREF UPGRADE switches plan now", async () => {
    await purchase();
    await webhook(notification("DID_CHANGE_RENEWAL_PREF", aliceTx({
      productId: "com.shoudeng.app.ultimate.monthly", transactionId: "UP1", purchaseDate: Date.now(),
    }), { subtype: "UPGRADE" }));
    expect(sub("alice")?.planId).toBe("ultimate");
    expect((await getSubscription("alice")).planId).toBe("ultimate");
  });

  test("DID_CHANGE_RENEWAL_PREF DOWNGRADE is pending until renewal; no subtype cancels it", async () => {
    await purchase();
    await webhook(notification("DID_CHANGE_RENEWAL_PREF", aliceTx(), {
      subtype: "DOWNGRADE", renewal: { autoRenewProductId: "com.shoudeng.app.single.monthly" },
    }));
    expect(sub("alice")).toMatchObject({ planId: "family", pendingPlanId: "single" });
    await webhook(notification("DID_CHANGE_RENEWAL_PREF", aliceTx(), {
      renewal: { autoRenewProductId: "com.shoudeng.app.family.monthly" },
    }));
    expect(sub("alice")?.pendingPlanId).toBeNull();
  });

  test("DID_CHANGE_RENEWAL_STATUS toggles auto-renew", async () => {
    await purchase();
    await webhook(notification("DID_CHANGE_RENEWAL_STATUS", aliceTx(), { subtype: "AUTO_RENEW_DISABLED" }));
    expect(sub("alice")?.autoRenew).toBe(false);
    await webhook(notification("DID_CHANGE_RENEWAL_STATUS", aliceTx(), { subtype: "AUTO_RENEW_ENABLED" }));
    expect(sub("alice")?.autoRenew).toBe(true);
  });

  test.each(["EXPIRED", "GRACE_PERIOD_EXPIRED"])("%s → free", async (type) => {
    await purchase();
    await webhook(notification(type, aliceTx(), { subtype: "VOLUNTARY" }));
    expect(sub("alice")?.status).toBe("expired");
    expect((await getSubscription("alice")).planId).toBe("free");
  });

  test("DID_FAIL_TO_RENEW with GRACE_PERIOD keeps access until the grace period ends", async () => {
    await purchase();
    const graceEnd = Date.now() + 6 * DAY;
    await webhook(notification("DID_FAIL_TO_RENEW", aliceTx(), {
      subtype: "GRACE_PERIOD", renewal: { gracePeriodExpiresDate: graceEnd },
    }));
    expect(sub("alice")?.status).toBe("grace_period");
    expect(sub("alice")?.gracePeriodEnd.toMillis()).toBe(graceEnd);
    expect((await getSubscription("alice")).planId).toBe("family");
  });

  test("DID_FAIL_TO_RENEW without grace period → billing retry, free", async () => {
    await purchase();
    await webhook(notification("DID_FAIL_TO_RENEW", aliceTx()));
    expect(sub("alice")?.status).toBe("billing_retry");
    expect((await getSubscription("alice")).planId).toBe("free");
  });

  test.each(["REFUND", "REVOKE"])("%s → cancelled, free", async (type) => {
    await purchase();
    await webhook(notification(type, aliceTx({ revocationDate: Date.now() })));
    expect(sub("alice")?.status).toBe("cancelled");
    expect(sub("alice")?.cancelledAt).toBeTruthy();
    expect((await getSubscription("alice")).planId).toBe("free");
  });

  test("REFUND_REVERSED restores access", async () => {
    await purchase();
    await webhook(notification("REFUND", aliceTx({ revocationDate: Date.now() })));
    await webhook(notification("REFUND_REVERSED", aliceTx()));
    expect(sub("alice")).toMatchObject({ status: "active", cancelledAt: null });
    expect((await getSubscription("alice")).planId).toBe("family");
  });

  test("OFFER_REDEEMED applies the offer's transaction", async () => {
    const res = await webhook(notification("OFFER_REDEEMED", aliceTx({ productId: "com.shoudeng.app.single.yearly" }), { subtype: "INITIAL_BUY" }));
    expect(res.status).toBe(200);
    expect(sub("alice")).toMatchObject({ planId: "single", status: "active" });
  });

  test("OFFER_REDEEMED DOWNGRADE is pending until renewal", async () => {
    await purchase();
    await webhook(notification("OFFER_REDEEMED", aliceTx(), {
      subtype: "DOWNGRADE", renewal: { autoRenewProductId: "com.shoudeng.app.single.monthly" },
    }));
    expect(sub("alice")).toMatchObject({ planId: "family", pendingPlanId: "single" });
  });

  test("TEST and unknown types are acknowledged and change nothing", async () => {
    await purchase();
    const before = sub("alice");
    expect((await webhook(jws({ notificationType: "TEST", data: { bundleId: BUNDLE, environment: "Production", appAppleId: APP_ID } }))).body.outcome).toBe("ignored");
    expect((await webhook(notification("PRICE_INCREASE", aliceTx()))).body.outcome).toBe("ignored");
    expect(sub("alice")?.status).toBe(before?.status);
  });

  test("a forged notification is refused (401) and changes nothing", async () => {
    await purchase();
    const forged = jws({ notificationType: "REFUND", data: { bundleId: BUNDLE, environment: "Production", appAppleId: APP_ID, signedTransactionInfo: jws(aliceTx()) } }, "forged");
    expect((await webhook(forged)).status).toBe(401);
    expect(sub("alice")?.status).toBe("active");
  });

  test("an older transaction does not overwrite a newer one", async () => {
    await webhook(notification("DID_CHANGE_RENEWAL_PREF", aliceTx({
      productId: "com.shoudeng.app.ultimate.monthly", purchaseDate: Date.now(),
    }), { subtype: "UPGRADE" }));
    // the app reports the old (pre-upgrade) family transaction late
    await as("alice").post("/v1/payment/verify-receipt", { signedTransaction: jws(aliceTx({ purchaseDate: Date.now() - 20 * DAY })) });
    expect(sub("alice")?.planId).toBe("ultimate");
  });

  test("a notification for a deleted account is acknowledged as unmatched", async () => {
    await purchase();
    await require("./helpers/fakeAdmin").fakeDb.collection("users").doc("alice").delete();
    const res = await webhook(notification("DID_RENEW", aliceTx()));
    expect(res.status).toBe(200);
    expect(res.body.outcome).toBe("unmatched");
  });

  test("missing signedPayload → 400", async () => {
    expect((await request(app).post("/v1/payment/apple-webhook").send({})).status).toBe(400);
  });
});
