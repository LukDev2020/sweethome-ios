/**
 * Auth routes: phone (Firebase ID token), Sign in with Apple, Sign in with Alipay,
 * linking sign-in methods to one account, session refresh, and what account
 * deletion does to Apple sign-ins.
 *
 * Apple's key server and Alipay's gateway are faked with real keys: identity
 * tokens are RS256-signed, Alipay requests must carry a valid RSA2 signature and
 * its answers are signed with "Alipay's" key, exactly as the real services do.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
// Account deletion also clears BigQuery history: no network in tests
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn(() => ({
    createQueryJob: async () => [{ getQueryResults: async () => [[]] }],
    dataset: () => ({ table: () => ({ insert: async () => undefined }) }),
  })),
}));

import express, { Express } from "express";
import request from "supertest";
import jwt from "jsonwebtoken";
import { generateKeyPairSync, createSign, createVerify, KeyObject } from "crypto";
import { resetFakeAdmin, seed, readDoc, listDocs, ts, tokenFor } from "./helpers/fakeAdmin";
import { __setAppleTransportForTests, sha256Hex } from "../services/appleSignIn";
import { __setAlipayTransportForTests, rawJsonNode, signingString, alipayTimestamp } from "../services/alipayAuth";
import { identityDocId } from "../services/identity";
import { __resetConfigReportsForTests } from "../config/params";

const JWT_SECRET = "shoudeng-dev-jwt-secret-do-not-use-in-prod";

// ---- Apple: a signing key and its JWKS ----
const appleKey = generateKeyPairSync("rsa", { modulusLength: 2048 });
const APPLE_KID = "TESTKID1";
const appleJwks = () => [{ ...(appleKey.publicKey.export({ format: "jwk" }) as object), kid: APPLE_KID, alg: "RS256", use: "sig" }];
const siwaKey = generateKeyPairSync("ec", { namedCurve: "P-256" });

function appleToken(claims: Record<string, unknown> = {}, opts: { kid?: string; key?: KeyObject } = {}): string {
  return jwt.sign(
    { iss: "https://appleid.apple.com", aud: "com.shoudeng.app", sub: "001234.apple.sub", nonce: sha256Hex("raw-nonce-1"),
      exp: Math.floor(Date.now() / 1000) + 600, ...claims },
    (opts.key ?? appleKey.privateKey).export({ format: "pem", type: "pkcs8" }) as string,
    { algorithm: "RS256", keyid: opts.kid ?? APPLE_KID },
  );
}

const applePosts: { url: string; form: Record<string, string> }[] = [];
let appleKeysFail = false;

// ---- Alipay: the app's key pair and "Alipay's" key pair ----
const appKeys = generateKeyPairSync("rsa", { modulusLength: 2048 });
const alipayKeys = generateKeyPairSync("rsa", { modulusLength: 2048 });
const bare = (k: KeyObject, type: "pkcs8" | "spki") =>
  (k.export({ format: "pem", type } as any) as string).replace(/-----[^-]+-----|\s/g, "");

const alipayCalls: Record<string, string>[] = [];
let alipayForge = false;
let alipayOpenId = "074a1CcTG1LelxKe4xQC0zgNdId0nxi95b5lsNpazWYoCo5";

function alipayAnswer(nodeName: string, node: object): string {
  const raw = JSON.stringify(node);
  const signer = alipayForge ? appKeys.privateKey : alipayKeys.privateKey; // forged = wrong key
  const sign = createSign("RSA-SHA256").update(raw, "utf8").sign(signer, "base64");
  return `{"${nodeName}":${raw},"sign":"${sign}"}`;
}

async function fakeAlipayGateway(_url: string, form: Record<string, string>): Promise<string> {
  alipayCalls.push(form);
  const ok = createVerify("RSA-SHA256").update(signingString(form), "utf8").verify(appKeys.publicKey, form.sign, "base64");
  if (!ok) return alipayAnswer("error_response", { code: "40002", msg: "Invalid Arguments", sub_code: "isv.invalid-signature" });
  if (form.method === "alipay.system.oauth.token") {
    if (form.code === "bad-code") {
      return alipayAnswer("error_response", { code: "40002", msg: "Invalid Arguments", sub_code: "isv.code-invalid" });
    }
    return alipayAnswer("alipay_system_oauth_token_response",
      { open_id: alipayOpenId, access_token: "at-1", expires_in: 1296000, re_expires_in: 2592000 });
  }
  if (form.method === "alipay.user.info.share") {
    return alipayAnswer("alipay_user_info_share_response", { code: "10000", msg: "Success", nick_name: "小王" });
  }
  return alipayAnswer("error_response", { code: "40004", msg: "Unknown method" });
}

function configureAlipay(on = true) {
  if (on) {
    process.env.ALIPAY_APP_ID = "2021004100000001";
    process.env.ALIPAY_PRIVATE_KEY = bare(appKeys.privateKey, "pkcs8");
    process.env.ALIPAY_PUBLIC_KEY = bare(alipayKeys.publicKey, "spki");
  } else {
    delete process.env.ALIPAY_APP_ID;
    delete process.env.ALIPAY_PRIVATE_KEY;
    delete process.env.ALIPAY_PUBLIC_KEY;
  }
}

function fakeIdToken(uid: string, phone = "+8613800001001"): string {
  const header = Buffer.from(JSON.stringify({ alg: "RS256" })).toString("base64");
  const payload = Buffer.from(JSON.stringify({ uid, user_id: uid, phone_number: phone })).toString("base64");
  return `${header}.${payload}.fake-signature`;
}

function mountApp(): Express {
  const app = express();
  app.use(express.json());
  app.use("/v1/auth", require("../routes/auth").default);
  app.use("/v1/user", require("../routes/user").default);
  return app;
}

const signupBody = (extra: object) => ({ displayName: "Wei", role: "protected", countryCode: "CA", ...extra });

describe("Auth routes", () => {
  let app: Express;

  beforeAll(() => {
    // Phone ID tokens are decoded without Firebase (emulator mode), as before
    process.env.FUNCTIONS_EMULATOR = "true";
    app = mountApp();
  });
  afterAll(() => {
    delete process.env.FUNCTIONS_EMULATOR;
    configureAlipay(false);
  });

  beforeEach(() => {
    resetFakeAdmin();
    __resetConfigReportsForTests();
    applePosts.length = 0;
    alipayCalls.length = 0;
    appleKeysFail = false;
    alipayForge = false;
    alipayOpenId = "074a1CcTG1LelxKe4xQC0zgNdId0nxi95b5lsNpazWYoCo5";
    __setAppleTransportForTests(async () => {
      if (appleKeysFail) throw new Error("network down");
      return appleJwks() as any;
    }, async (url, form) => {
      applePosts.push({ url, form });
      if (url.endsWith("/auth/token")) return { status: 200, body: { refresh_token: `rt-${form.code}`, id_token: "x" } };
      return { status: 200, body: "" };
    });
    __setAlipayTransportForTests(fakeAlipayGateway);
    process.env.APPLE_SIWA_KEY_ID = "SIWAKEY123";
    process.env.APPLE_SIWA_PRIVATE_KEY = siwaKey.privateKey.export({ format: "pem", type: "pkcs8" }) as string;
    configureAlipay(false);
  });

  // MARK: Phone

  describe("phone", () => {
    it("send-code is a no-op kept for old clients", async () => {
      expect((await request(app).post("/v1/auth/send-code").send({ phone: "+8613800001001" })).status).toBe(200);
      expect((await request(app).post("/v1/auth/send-code").send({})).status).toBe(400);
    });

    it("login returns tokens for an existing account", async () => {
      seed("users/user-123", { displayName: "Test User", role: "protected", phone: "+8613800001001" });
      const res = await request(app).post("/v1/auth/login").send({ idToken: fakeIdToken("user-123") });
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({ userId: "user-123", role: "protected", displayName: "Test User" });
      const decoded = jwt.verify(res.body.accessToken, JWT_SECRET) as any;
      expect(decoded).toMatchObject({ uid: "user-123", type: "access" });
    });

    it("login: 404 for an unknown number, 400 without a token", async () => {
      const res = await request(app).post("/v1/auth/login").send({ idToken: fakeIdToken("nobody") });
      expect(res.status).toBe(404);
      expect(res.body.error).toMatch(/not found|sign up/i);
      expect((await request(app).post("/v1/auth/login").send({})).status).toBe(400);
    });

    it("signup creates the account under the phone's uid, country from the number", async () => {
      const res = await request(app).post("/v1/auth/signup")
        .send({ idToken: fakeIdToken("new-user", "+8613800001001"), displayName: "New User", role: "protected" });
      expect(res.status).toBe(201);
      expect(res.body.userId).toBe("new-user");
      expect(readDoc("users/new-user")).toMatchObject({
        displayName: "New User", role: "protected", countryCode: "CN", timeZone: "Asia/Shanghai",
        avatarInitial: "N", phone: "+8613800001001", authProviders: ["phone"],
      });
    });

    it.each([
      ["+14165551001", "CA", "CA", "America/Toronto"],
      ["+33612345678", undefined, "FR", "Europe/Paris"],
      ["+85291234567", undefined, "HK", "Asia/Hong_Kong"],
    ])("signup %s → %s", async (phone, client, country, tz) => {
      const res = await request(app).post("/v1/auth/signup")
        .send({ idToken: fakeIdToken("u", phone), displayName: "X", role: "guardian", countryCode: client });
      expect(res.status).toBe(201);
      expect(readDoc("users/u")).toMatchObject({ countryCode: country, timeZone: tz });
    });

    it("signup: 409 when the account exists, 400 for a bad role or missing fields", async () => {
      seed("users/existing-user", { displayName: "E", role: "guardian" });
      expect((await request(app).post("/v1/auth/signup")
        .send({ idToken: fakeIdToken("existing-user"), displayName: "E", role: "guardian" })).status).toBe(409);
      const bad = await request(app).post("/v1/auth/signup").send({ idToken: fakeIdToken("u"), displayName: "T", role: "admin" });
      expect(bad.status).toBe(400);
      expect(bad.body.error).toMatch(/role/i);
      expect((await request(app).post("/v1/auth/signup").send({ idToken: fakeIdToken("u") })).status).toBe(400);
    });
  });

  // MARK: Refresh

  describe("refresh", () => {
    const refresh = (claims: object, secret = JWT_SECRET, expiresIn: any = "30d") =>
      request(app).post("/v1/auth/refresh").send({ refreshToken: jwt.sign(claims, secret, { expiresIn }) });

    it("issues new tokens while the account exists", async () => {
      seed("users/user-123", { displayName: "T", role: "protected" });
      const res = await refresh({ uid: "user-123", type: "refresh" });
      expect(res.status).toBe(200);
      expect(res.body.userId).toBe("user-123");
      expect(res.body.accessToken).toBeDefined();
    });

    it("a deleted account's refresh token stops working", async () => {
      expect((await refresh({ uid: "gone", type: "refresh" })).status).toBe(401);
    });

    it("rejects access tokens, expired tokens, wrong secrets, and nothing", async () => {
      seed("users/user-123", { displayName: "T", role: "protected" });
      expect((await refresh({ uid: "user-123", type: "access" })).status).toBe(401);
      expect((await refresh({ uid: "user-123", type: "refresh" }, JWT_SECRET, "-1s")).status).toBe(401);
      expect((await refresh({ uid: "user-123", type: "refresh" }, "wrong-secret")).status).toBe(401);
      expect((await request(app).post("/v1/auth/refresh").send({})).status).toBe(400);
    });
  });

  // MARK: Sign in with Apple

  describe("Sign in with Apple", () => {
    const apple = (token = appleToken(), extra: object = {}) =>
      request(app).post("/v1/auth/apple").send({ identityToken: token, rawNonce: "raw-nonce-1", ...extra });

    it("a new Apple ID signs up, then signs straight in", async () => {
      const first = await apple(appleToken({ email: "wei@privaterelay.appleid.com", is_private_email: "true" }),
        { fullName: "Wei Chen", authorizationCode: "code-1" });
      expect(first.status).toBe(200);
      expect(first.body).toMatchObject({ status: "signupRequired", displayName: "Wei Chen", email: "wei@privaterelay.appleid.com" });
      expect(first.body.accessToken).toBeUndefined();

      const created = await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: first.body.signupToken }));
      expect(created.status).toBe(201);
      const uid = created.body.userId;
      expect(readDoc(`users/${uid}`)).toMatchObject({
        displayName: "Wei", phone: "", countryCode: "CA", timeZone: "America/Toronto",
        email: "wei@privaterelay.appleid.com", authProviders: ["apple"],
      });
      expect(readDoc(`auth_identities/${identityDocId("apple", "001234.apple.sub")}`)).toMatchObject({ uid, provider: "apple" });

      const again = await apple();
      expect(again.body).toMatchObject({ status: "signedIn", userId: uid, displayName: "Wei", role: "protected" });
      expect((jwt.verify(again.body.accessToken, JWT_SECRET) as any).uid).toBe(uid);
    });

    it("keeps a refresh token for revocation (client secret signed with the SIWA key)", async () => {
      await apple(undefined, { authorizationCode: "code-9" });
      const exchange = applePosts.find((p) => p.url.endsWith("/auth/token"))!;
      expect(exchange.form).toMatchObject({ client_id: "com.shoudeng.app", code: "code-9", grant_type: "authorization_code" });
      const secret = jwt.verify(exchange.form.client_secret, siwaKey.publicKey.export({ format: "pem", type: "spki" }) as string,
        { algorithms: ["ES256"] }) as any;
      expect(secret).toMatchObject({ iss: "B98QT5LTWZ", sub: "com.shoudeng.app", aud: "https://appleid.apple.com" });
      expect(jwt.decode(exchange.form.client_secret, { complete: true })!.header.kid).toBe("SIWAKEY123");
      expect(readDoc(`apple_tokens/${identityDocId("apple", "001234.apple.sub")}`)?.refreshToken).toBe("rt-code-9");
    });

    it("without the SIWA key sign-in still works (nothing kept)", async () => {
      delete process.env.APPLE_SIWA_PRIVATE_KEY;
      const res = await apple(undefined, { authorizationCode: "code-1" });
      expect(res.body.status).toBe("signupRequired");
      expect(applePosts).toHaveLength(0);
    });

    it.each([
      ["another nonce", () => appleToken({ nonce: sha256Hex("someone-elses") })],
      ["another app", () => appleToken({ aud: "com.other.app" })],
      ["not Apple", () => appleToken({ iss: "https://evil.example" })],
      ["expired", () => appleToken({ exp: Math.floor(Date.now() / 1000) - 60 })],
      ["a key Apple doesn't have", () => appleToken({}, { kid: "OTHER" })],
      ["signed by someone else", () => appleToken({}, { key: generateKeyPairSync("rsa", { modulusLength: 2048 }).privateKey })],
      ["garbage", () => "not.a.jwt"],
    ])("rejects a token from %s", async (_label, make) => {
      const res = await apple(make());
      expect(res.status).toBe(401);
      expect(res.body.code).toBe("APPLE_INVALID");
      expect(listDocs("auth_identities")).toHaveLength(0);
    });

    it("Apple's keys unreachable → 503 (retry), not 'invalid'", async () => {
      appleKeysFail = true;
      expect((await apple()).status).toBe(503);
    });

    it("needs the token and the nonce", async () => {
      expect((await request(app).post("/v1/auth/apple").send({ identityToken: appleToken() })).status).toBe(400);
    });

    it("someone with a phone account connects Apple by signing in with their phone", async () => {
      seed("users/phone-wei", { displayName: "Wei", role: "guardian", phone: "+14165550001" });
      const pending = await apple();
      const login = await request(app).post("/v1/auth/login")
        .send({ idToken: fakeIdToken("phone-wei", "+14165550001"), linkToken: pending.body.signupToken });
      expect(login.status).toBe(200);
      expect(login.body).toMatchObject({ userId: "phone-wei", linked: "apple" });
      expect(readDoc("users/phone-wei")?.authProviders).toEqual(["apple"]);
      expect((await apple()).body).toMatchObject({ status: "signedIn", userId: "phone-wei" });
    });

    it("an Apple ID already on another account isn't moved", async () => {
      seed("users/a", { displayName: "A", role: "guardian" });
      seed("users/b", { displayName: "B", role: "guardian" });
      seed(`auth_identities/${identityDocId("apple", "001234.apple.sub")}`, { uid: "a", provider: "apple", subject: "001234.apple.sub" });
      const token = jwt.sign({ type: "signup", provider: "apple", subject: "001234.apple.sub" }, JWT_SECRET);
      const res = await request(app).post("/v1/auth/login").send({ idToken: fakeIdToken("b"), linkToken: token });
      expect(res.status).toBe(409);
      expect(res.body.code).toBe("IDENTITY_LINKED_ELSEWHERE");
      expect(readDoc(`auth_identities/${identityDocId("apple", "001234.apple.sub")}`)?.uid).toBe("a");
    });

    it("signup tokens can't be forged, reused for a second account, or used as sessions", async () => {
      const forged = jwt.sign({ type: "signup", provider: "apple", subject: "x" }, "wrong-secret");
      const r1 = await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: forged }));
      expect(r1.status).toBe(400);
      expect(r1.body.code).toBe("SIGNUP_EXPIRED");

      const pending = await apple();
      expect((await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: pending.body.signupToken }))).status).toBe(201);
      expect((await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: pending.body.signupToken }))).status).toBe(409);
      expect(listDocs("users")).toHaveLength(1);

      // (outside emulator mode, where access tokens are really checked)
      delete process.env.FUNCTIONS_EMULATOR;
      const asSession = await request(app).get("/v1/auth/methods").set("Authorization", `Bearer ${pending.body.signupToken}`);
      process.env.FUNCTIONS_EMULATOR = "true";
      expect(asSession.status).toBe(401);
    });

    it("deleting the account revokes the Apple sign-in and removes the links", async () => {
      const pending = await apple(undefined, { authorizationCode: "code-del" });
      const uid = (await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: pending.body.signupToken }))).body.userId;
      const del = await request(app).post("/v1/user/delete").set("Authorization", `Bearer ${tokenFor(uid)}`);
      expect(del.status).toBe(200);
      const revoke = applePosts.find((p) => p.url.endsWith("/auth/revoke"))!;
      expect(revoke.form).toMatchObject({ client_id: "com.shoudeng.app", token: "rt-code-del", token_type_hint: "refresh_token" });
      expect(listDocs("apple_tokens")).toHaveLength(0);
      expect(listDocs("auth_identities")).toHaveLength(0);
      expect(readDoc(`users/${uid}`)).toBeUndefined();
      // Signing in with Apple again starts over
      expect((await apple()).body.status).toBe("signupRequired");
    });
  });

  // MARK: Sign in with Alipay

  describe("Sign in with Alipay", () => {
    const start = () => request(app).post("/v1/auth/alipay/start").send({});
    const callback = (state: string, code?: string) =>
      request(app).get("/v1/auth/alipay/callback").query({ state, app_id: "2021004100000001", ...(code ? { auth_code: code } : {}) });
    const complete = (state: string, secret: string) => request(app).post("/v1/auth/alipay/complete").send({ state, secret });

    it("is off (and hidden) until the Alipay keys are set", async () => {
      expect((await request(app).get("/v1/auth/providers")).body).toEqual({ phone: true, apple: true, alipay: false });
      const res = await start();
      expect(res.status).toBe(503);
      expect(res.body.code).toBe("ALIPAY_UNAVAILABLE");
      configureAlipay();
      expect((await request(app).get("/v1/auth/providers")).body.alipay).toBe(true);
    });

    it("the whole round trip: Alipay app → callback → back in the app → sign up → next time signed in", async () => {
      configureAlipay();
      const s = (await start()).body;
      expect(s.authUrl).toContain("https://openauth.alipay.com/oauth2/publicAppAuthorize.htm?app_id=2021004100000001&scope=auth_user");
      expect(s.authUrl).toContain(`redirect_uri=${encodeURIComponent("https://us-central1-sweethome-b4e82.cloudfunctions.net/api/v1/auth/alipay/callback")}`);
      expect(s.authUrl).toContain(`state=${s.state}`);
      expect(s.alipayAppUrl).toBe(`alipays://platformapi/startapp?appId=20000067&url=${encodeURIComponent(s.authUrl)}`);
      expect(readDoc(`alipay_logins/${s.state}`)?.secretHash).not.toContain(s.secret);

      // Back in the app too early: still waiting for Alipay
      expect((await complete(s.state, s.secret)).status).toBe(202);

      const page = await callback(s.state, "good-code");
      expect(page.status).toBe(200);
      expect(page.text).toContain(`shoudeng://auth/alipay?state=${s.state}`);
      expect(page.text).toContain("已确认");
      const tokenCall = alipayCalls.find((c) => c.method === "alipay.system.oauth.token")!;
      expect(tokenCall).toMatchObject({ app_id: "2021004100000001", grant_type: "authorization_code", code: "good-code", sign_type: "RSA2", charset: "utf-8" });

      const done = await complete(s.state, s.secret);
      expect(done.body).toMatchObject({ status: "signupRequired", displayName: "小王" });
      // One-time
      expect((await complete(s.state, s.secret)).status).toBe(404);

      const created = await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: done.body.signupToken, countryCode: "CN" }));
      expect(created.status).toBe(201);
      expect(readDoc(`users/${created.body.userId}`)).toMatchObject({ authProviders: ["alipay"], countryCode: "CN", phone: "" });
      expect(readDoc(`auth_identities/${identityDocId("alipay", `oid:${alipayOpenId}`)}`)?.uid).toBe(created.body.userId);

      const s2 = (await start()).body;
      await callback(s2.state, "good-code-2");
      expect((await complete(s2.state, s2.secret)).body).toMatchObject({ status: "signedIn", userId: created.body.userId });
    });

    it("only the phone that started it can collect the result", async () => {
      configureAlipay();
      const s = (await start()).body;
      await callback(s.state, "good-code");
      expect((await complete(s.state, "f".repeat(48))).status).toBe(404);
      expect((await complete("not-a-state", s.secret)).status).toBe(404);
      expect((await complete(s.state, s.secret)).body.status).toBe("signupRequired");
    });

    it("a forged Alipay answer is refused", async () => {
      configureAlipay();
      alipayForge = true;
      const s = (await start()).body;
      const page = await callback(s.state, "good-code");
      expect(page.text).toContain("未完成");
      const res = await complete(s.state, s.secret);
      expect(res.status).toBe(400);
      expect(res.body.code).toBe("ALIPAY_DENIED");
      expect(listDocs("auth_identities")).toHaveLength(0);
    });

    it("declined on Alipay, or a bad code → not signed in", async () => {
      configureAlipay();
      const declined = (await start()).body;
      await callback(declined.state);
      expect((await complete(declined.state, declined.secret)).body.reason).toBe("declined");
      const bad = (await start()).body;
      await callback(bad.state, "bad-code");
      expect((await complete(bad.state, bad.secret)).body.reason).toBe("exchange");
    });

    it("an old or unknown sign-in shows 'expired' and calls nobody", async () => {
      configureAlipay();
      const s = (await start()).body;
      seed(`alipay_logins/${s.state}`, { ...readDoc(`alipay_logins/${s.state}`), expiresAt: ts(Date.now() - 1000) });
      expect((await callback(s.state, "good-code")).text).toContain("已过期");
      expect((await callback("0".repeat(32), "good-code")).text).toContain("已过期");
      expect(alipayCalls).toHaveLength(0);
    });

    it("older Alipay apps identify people by user_id", async () => {
      configureAlipay();
      __setAlipayTransportForTests(async (url, form) => {
        if (form.method === "alipay.system.oauth.token") {
          alipayCalls.push(form);
          return alipayAnswer("alipay_system_oauth_token_response", { user_id: "2088102150477652", access_token: "at" });
        }
        return fakeAlipayGateway(url, form);
      });
      const s = (await start()).body;
      await callback(s.state, "good-code");
      const res = await complete(s.state, s.secret);
      const created = await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: res.body.signupToken }));
      expect(readDoc(`auth_identities/${identityDocId("alipay", "uid:2088102150477652")}`)?.uid).toBe(created.body.userId);
    });
  });

  // MARK: Adding a phone number / sign-in methods

  describe("linking", () => {
    async function appleAccount(): Promise<string> {
      const pending = await request(app).post("/v1/auth/apple").send({ identityToken: appleToken(), rawNonce: "raw-nonce-1" });
      return (await request(app).post("/v1/auth/signup").send(signupBody({ signupToken: pending.body.signupToken }))).body.userId;
    }
    const as = (uid: string) => ({
      get: (p: string) => request(app).get(p).set("Authorization", `Bearer ${tokenFor(uid)}`),
      post: (p: string, body: object) => request(app).post(p).set("Authorization", `Bearer ${tokenFor(uid)}`).send(body),
    });

    it("an Apple account adds a phone: texts reach them, and they can sign in by phone", async () => {
      const uid = await appleAccount();
      const res = await as(uid).post("/v1/auth/link-phone", { idToken: fakeIdToken("fb-phone-1", "+14165550002") });
      expect(res.status).toBe(200);
      expect(readDoc(`users/${uid}`)).toMatchObject({ phone: "+14165550002", authProviders: ["apple", "phone"] });
      const login = await request(app).post("/v1/auth/login").send({ idToken: fakeIdToken("fb-phone-1", "+14165550002") });
      expect(login.body.userId).toBe(uid);
      expect((await as(uid).get("/v1/auth/methods")).body).toEqual({ phone: "+14165550002", apple: true, alipay: false });
      // and that number can't start a second account
      expect((await request(app).post("/v1/auth/signup")
        .send({ idToken: fakeIdToken("fb-phone-1", "+14165550002"), displayName: "Dup", role: "guardian" })).status).toBe(409);
    });

    it("a number that already has its own account isn't taken over", async () => {
      const uid = await appleAccount();
      seed("users/fb-phone-2", { displayName: "Other", role: "guardian", phone: "+14165550003" });
      const res = await as(uid).post("/v1/auth/link-phone", { idToken: fakeIdToken("fb-phone-2", "+14165550003") });
      expect(res.status).toBe(409);
      expect(res.body.code).toBe("PHONE_HAS_ACCOUNT");
      expect(readDoc(`users/${uid}`)?.phone).toBe("");
    });

    it("a signed-in person connects Apple from Settings", async () => {
      seed("users/p1", { displayName: "P", role: "protected", phone: "+14165550004" });
      const pending = await request(app).post("/v1/auth/apple").send({ identityToken: appleToken(), rawNonce: "raw-nonce-1" });
      const res = await as("p1").post("/v1/auth/link", { signupToken: pending.body.signupToken });
      expect(res.body).toEqual({ success: true, provider: "apple" });
      expect((await as("p1").get("/v1/auth/methods")).body).toMatchObject({ apple: true, phone: "+14165550004" });
      expect((await as("p1").post("/v1/auth/link", { signupToken: "nope" })).status).toBe(400);
    });

    it("account deletion with a phone added also removes that phone sign-in", async () => {
      const uid = await appleAccount();
      await as(uid).post("/v1/auth/link-phone", { idToken: fakeIdToken("fb-phone-3", "+14165550005") });
      expect((await as(uid).post("/v1/user/delete", {})).status).toBe(200);
      expect((await request(app).post("/v1/auth/login").send({ idToken: fakeIdToken("fb-phone-3") })).status).toBe(404);
    });
  });
});

describe("Alipay helpers", () => {
  it("signing string: sorted, no sign, no empties, raw values", () => {
    expect(signingString({ method: "a.b", app_id: "1", sign: "x", empty: "", biz: "中 文&=" })).toBe("app_id=1&biz=中 文&=&method=a.b");
  });

  it("cuts the exact signed bytes out of Alipay's answer", () => {
    const body = `{"alipay_x_response":{"a":"}{\\"","n":{"b":1}},"sign":"S"}`;
    expect(rawJsonNode(body, "alipay_x_response")).toBe(`{"a":"}{\\"","n":{"b":1}}`);
    expect(rawJsonNode(body, "missing")).toBeNull();
  });

  it("timestamps are Beijing time", () => {
    expect(alipayTimestamp(new Date("2026-11-08T20:30:05Z"))).toBe("2026-11-09 04:30:05");
  });
});
