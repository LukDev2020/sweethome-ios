/**
 * The Hong Kong relay (docs/ops/CHINA-RELAY.md): req.ip behind phone → relay →
 * Google front end → function, and links people open on mainland networks.
 *
 * supertest connects from 127.0.0.1, which stands in for Google's front end (the
 * socket peer). X-Forwarded-For is what Google forwards: "<…>, <address Google saw>".
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import express from "express";
import request from "supertest";
import { resetFakeAdmin } from "./helpers/fakeAdmin";
import { normalizeIp, trustProxy, trustedRelayIps } from "../config/relay";
import { publicApiBaseUrl, publicLinkBaseUrl, verifyTwilioSignature } from "../services/twilio";

const RELAY = "47.242.10.20";
const RELAY_V6 = "2408:4005:3a0:1::20";
const PHONE_A = "117.136.0.11"; // two people in Shanghai on China Mobile
const PHONE_B = "117.136.0.12";
const ATTACKER = "198.51.100.66";

const probe = express();
probe.set("trust proxy", trustProxy);
probe.get("/ip", (req, res) => res.json({ ip: req.ip }));
const ipFor = async (xff?: string) => {
  const r = request(probe).get("/ip");
  return (await (xff === undefined ? r : r.set("X-Forwarded-For", xff))).body.ip;
};

const saved = { ...process.env };
afterEach(() => {
  process.env = { ...saved };
});

describe("req.ip with the relay configured", () => {
  beforeEach(() => {
    process.env.TRUSTED_RELAY_IPS = `${RELAY}, ${RELAY_V6}`;
  });

  it("through the relay: the phone's address, not the relay's", async () => {
    expect(await ipFor(`${PHONE_A}, ${RELAY}`)).toBe(PHONE_A);
    expect(await ipFor(`${PHONE_B}, ${RELAY_V6.toUpperCase()}`)).toBe(PHONE_B);
  });

  it("direct to Google: the address Google saw, as before", async () => {
    expect(await ipFor(PHONE_A)).toBe(PHONE_A);
  });

  it("a client cannot pick its own address going direct, even by naming the relay", async () => {
    // The attacker sends X-Forwarded-For: "1.2.3.4, <relay>"; Google appends the attacker
    expect(await ipFor(`1.2.3.4, ${RELAY}, ${ATTACKER}`)).toBe(ATTACKER);
    expect(await ipFor(`${RELAY}, ${ATTACKER}`)).toBe(ATTACKER);
  });

  it("nor through the relay, even if the relay appended instead of overwriting", async () => {
    // Client header "6.6.6.6" + relay's $proxy_add_x_forwarded_for + Google's hop
    expect(await ipFor(`6.6.6.6, ${PHONE_A}, ${RELAY}`)).toBe(PHONE_A);
    // A client claiming to be a relay behind the relay is still only one hop deep
    expect(await ipFor(`9.9.9.9, ${RELAY}, ${PHONE_A}, ${RELAY}`)).toBe(PHONE_A);
  });

  it("no X-Forwarded-For at all: the socket peer", async () => {
    expect(normalizeIp(await ipFor())).toBe("127.0.0.1");
  });
});

describe("req.ip without a relay configured", () => {
  it("keeps the old one-hop behaviour: the relay is just a client", async () => {
    delete process.env.TRUSTED_RELAY_IPS;
    expect(await ipFor(`${PHONE_A}, ${RELAY}`)).toBe(RELAY);
    process.env.TRUSTED_RELAY_IPS = "";
    expect(await ipFor(`${PHONE_A}, ${RELAY}`)).toBe(RELAY);
  });
});

describe("trustProxy / TRUSTED_RELAY_IPS parsing", () => {
  it("trusts Google always, the relay only as the second hop", () => {
    process.env.TRUSTED_RELAY_IPS = RELAY;
    expect(trustProxy("10.0.0.1", 0)).toBe(true);
    expect(trustProxy(RELAY, 1)).toBe(true);
    expect(trustProxy(`::ffff:${RELAY}`, 1)).toBe(true);
    expect(trustProxy(RELAY, 2)).toBe(false);
    expect(trustProxy(PHONE_A, 1)).toBe(false);
  });

  it("accepts commas, spaces and new lines; ignores empties", () => {
    expect([...trustedRelayIps(` ${RELAY},,\n${RELAY_V6.toUpperCase()} `)]).toEqual([RELAY, RELAY_V6]);
    expect(trustedRelayIps("").size).toBe(0);
  });
});

describe("sign-in rate limit behind the relay (full app)", () => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { app } = require("../app");
  const login = (xff: string) => request(app).post("/v1/auth/login").set("X-Forwarded-For", xff).send({});

  beforeEach(() => {
    resetFakeAdmin();
    process.env.TRUSTED_RELAY_IPS = RELAY;
  });

  it("counts each phone on its own, not everyone in China as one", async () => {
    for (let i = 0; i < 5; i++) expect((await login(`${PHONE_A}, ${RELAY}`)).status).not.toBe(429);
    expect((await login(`${PHONE_A}, ${RELAY}`)).status).toBe(429);
    // Another person behind the same relay is not locked out
    expect((await login(`${PHONE_B}, ${RELAY}`)).status).not.toBe(429);
  });

  it("without TRUSTED_RELAY_IPS everyone behind the relay shares one bucket (why it matters)", async () => {
    delete process.env.TRUSTED_RELAY_IPS;
    for (let i = 0; i < 5; i++) await login(`${PHONE_A}, ${RELAY}`);
    expect((await login(`${PHONE_B}, ${RELAY}`)).status).toBe(429);
  });
});

describe("links people open vs. Twilio webhooks", () => {
  it("links use PUBLIC_LINK_BASE_URL (the relay); Twilio keeps the Google URL", () => {
    delete process.env.PUBLIC_API_BASE_URL;
    process.env.GCLOUD_PROJECT = "sweethome-b4e82";
    process.env.PUBLIC_LINK_BASE_URL = "https://api.example.hk/";
    expect(publicLinkBaseUrl()).toBe("https://api.example.hk");
    expect(publicApiBaseUrl()).toBe("https://us-central1-sweethome-b4e82.cloudfunctions.net/api");
  });

  it("without PUBLIC_LINK_BASE_URL links use the API base, as before", () => {
    delete process.env.PUBLIC_LINK_BASE_URL;
    process.env.PUBLIC_API_BASE_URL = "https://custom.example.com/api";
    expect(publicLinkBaseUrl()).toBe("https://custom.example.com/api");
  });

  it("Twilio signatures are still checked against the Google URL", () => {
    delete process.env.PUBLIC_API_BASE_URL;
    delete process.env.FUNCTIONS_EMULATOR;
    process.env.GCLOUD_PROJECT = "sweethome-b4e82";
    process.env.PUBLIC_LINK_BASE_URL = "https://api.example.hk";
    const crypto = require("crypto");
    const url = "https://us-central1-sweethome-b4e82.cloudfunctions.net/api/v1/voice-callback";
    const sig = crypto.createHmac("sha1", "tok").update(url + "Digits1").digest("base64");
    expect(verifyTwilioSignature(sig, "/v1/voice-callback", { Digits: "1" }, "tok")).toBe(true);
  });
});
