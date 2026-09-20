import express, { Express } from "express";
import request from "supertest";
import * as crypto from "crypto";

// ---- Mock firebase-admin ----
jest.mock("firebase-admin", () => {
  const mockAdd = jest.fn().mockResolvedValue({ id: "mock-doc" });
  const mockGet = jest.fn().mockResolvedValue({ docs: [] });
  const mockWhere = jest.fn().mockReturnThis();
  const collection = jest.fn(() => ({
    add: mockAdd,
    where: mockWhere,
    get: mockGet,
    doc: jest.fn(() => ({
      get: jest.fn().mockResolvedValue({ exists: false }),
      update: jest.fn(),
    })),
  }));
  const firestore = Object.assign(jest.fn(() => ({ collection })), {
    Timestamp: {
      now: jest.fn(() => ({ seconds: 1000, nanoseconds: 0 })),
    },
    FieldValue: {
      arrayUnion: jest.fn(),
    },
  });
  return {
    firestore,
    initializeApp: jest.fn(),
    auth: jest.fn(() => ({ verifyIdToken: jest.fn() })),
  };
});

// ---- Mock firebase-functions config ----
jest.mock("firebase-functions", () => ({
  config: jest.fn(() => ({
    twilio: { auth_token: "test-auth-token-secret" },
  })),
  https: { onRequest: jest.fn() },
}));

/**
 * Compute a valid Twilio-style HMAC-SHA1 signature.
 *
 * Twilio signs: url + sorted(key+value for each POST param)
 */
function computeTwilioSignature(
  authToken: string,
  url: string,
  params: Record<string, string>
): string {
  const sortedKeys = Object.keys(params).sort();
  const data = url + sortedKeys.map((k) => k + params[k]).join("");
  return crypto
    .createHmac("sha1", authToken)
    .update(Buffer.from(data, "utf-8"))
    .digest("base64");
}

describe("Webhook signature verification", () => {
  let app: Express;
  const AUTH_TOKEN = "test-auth-token-secret";

  beforeEach(() => {
    jest.clearAllMocks();

    // Ensure we are NOT in emulator mode (emulator bypasses verification)
    delete process.env.FUNCTIONS_EMULATOR;

    app = express();
    app.use(express.json());
    app.use(express.urlencoded({ extended: false }));

    // Import and mount the webhooks router
    // Note: the module is re-evaluated but the jest.mock at top hoists correctly
    const webhookRouter = require("../routes/webhooks").default;
    app.use("/v1/webhooks", webhookRouter);
  });

  it("rejects requests without X-Twilio-Signature header", async () => {
    const res = await request(app)
      .post("/v1/webhooks/twilio/call-status")
      .send({ CallSid: "CA123", CallStatus: "completed" });

    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Invalid signature/i);
  });

  it("rejects requests with an invalid X-Twilio-Signature", async () => {
    const res = await request(app)
      .post("/v1/webhooks/twilio/call-status")
      .set("x-twilio-signature", "totally-wrong-signature")
      .send({ CallSid: "CA123", CallStatus: "completed" });

    expect(res.status).toBe(403);
    expect(res.body.error).toMatch(/Invalid signature/i);
  });

  it("accepts requests with a valid HMAC-SHA1 signature (call-status)", async () => {
    const params = {
      CallSid: "CA123",
      CallStatus: "completed",
      CallDuration: "45",
      To: "+15551234567",
      From: "+15559876543",
    };

    // The URL Twilio would use — supertest connects via http://127.0.0.1:PORT
    // We need to compute the signature using the URL as the server sees it.
    // supertest uses a random port; we compute what the server will reconstruct:
    // protocol = x-forwarded-proto || "https", host from headers.host
    const protocol = "https";
    const host = "us-central1-shoudeng.cloudfunctions.net";
    const path = "/v1/webhooks/twilio/call-status";
    const url = `${protocol}://${host}${path}`;

    const signature = computeTwilioSignature(AUTH_TOKEN, url, params);

    const res = await request(app)
      .post(path)
      .set("x-twilio-signature", signature)
      .set("x-forwarded-proto", protocol)
      .set("host", host)
      .type("form")
      .send(params);

    // 204 means the webhook accepted and processed the request
    expect(res.status).toBe(204);
  });

  it("accepts requests with a valid HMAC-SHA1 signature (sms-status)", async () => {
    const params = {
      MessageSid: "SM456",
      MessageStatus: "delivered",
      To: "+15551234567",
    };

    const protocol = "https";
    const host = "us-central1-shoudeng.cloudfunctions.net";
    const path = "/v1/webhooks/twilio/sms-status";
    const url = `${protocol}://${host}${path}`;

    const signature = computeTwilioSignature(AUTH_TOKEN, url, params);

    const res = await request(app)
      .post(path)
      .set("x-twilio-signature", signature)
      .set("x-forwarded-proto", protocol)
      .set("host", host)
      .type("form")
      .send(params);

    expect(res.status).toBe(204);
  });

  it("rejects sms-status without signature", async () => {
    const res = await request(app)
      .post("/v1/webhooks/twilio/sms-status")
      .send({ MessageSid: "SM456", MessageStatus: "delivered" });

    expect(res.status).toBe(403);
  });
});
