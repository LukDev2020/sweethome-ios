/**
 * Phase 2 — Auth Routes Tests
 *
 * Tests the auth flow: send-code, login, signup, refresh.
 * Uses mocked Firestore and JWT.
 */

import express, { Express } from "express";
import request from "supertest";
import jwt from "jsonwebtoken";

const JWT_SECRET = "shoudeng-dev-jwt-secret-do-not-use-in-prod";

// ---- Firestore mock ----
const mockGet = jest.fn();
const mockSet = jest.fn();
const mockDocRef = (path: string) => ({
  get: mockGet,
  set: mockSet,
  id: path.split("/").pop(),
});

jest.mock("firebase-admin", () => {
  const collection = jest.fn((name: string) => ({
    doc: jest.fn((id: string) => mockDocRef(`${name}/${id}`)),
  }));
  const firestore = Object.assign(
    jest.fn(() => ({ collection })),
    {
      Timestamp: {
        now: jest.fn(() => ({ seconds: 1000, nanoseconds: 0 })),
      },
    }
  );
  return {
    firestore,
    initializeApp: jest.fn(),
    auth: jest.fn(() => ({
      verifyIdToken: jest.fn(),
    })),
  };
});

// Import after mocks
import authRouter from "../routes/auth";

function mountApp(): Express {
  const app = express();
  app.use(express.json());
  // Emulator mode for token decoding
  process.env.FUNCTIONS_EMULATOR = "true";
  app.use("/v1/auth", authRouter);
  return app;
}

function fakeIdToken(uid: string, phone: string = "+8613800001001"): string {
  const header = Buffer.from(JSON.stringify({ alg: "RS256" })).toString("base64");
  const payload = Buffer.from(
    JSON.stringify({ uid, user_id: uid, phone_number: phone })
  ).toString("base64");
  return `${header}.${payload}.fake-signature`;
}

describe("Auth Routes", () => {
  let app: Express;

  beforeEach(() => {
    jest.clearAllMocks();
    app = mountApp();
  });

  afterEach(() => {
    delete process.env.FUNCTIONS_EMULATOR;
  });

  // ---- POST /v1/auth/send-code ----

  describe("POST /v1/auth/send-code", () => {
    it("returns success for valid phone", async () => {
      const res = await request(app)
        .post("/v1/auth/send-code")
        .send({ phone: "+8613800001001" });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });

    it("returns 400 when phone is missing", async () => {
      const res = await request(app).post("/v1/auth/send-code").send({});
      expect(res.status).toBe(400);
    });
  });

  // ---- POST /v1/auth/login ----

  describe("POST /v1/auth/login", () => {
    it("returns tokens when user exists", async () => {
      mockGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          displayName: "Test User",
          role: "protected",
          phone: "+8613800001001",
        }),
      });

      const res = await request(app)
        .post("/v1/auth/login")
        .send({ idToken: fakeIdToken("user-123") });

      expect(res.status).toBe(200);
      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
      expect(res.body.userId).toBe("user-123");
      expect(res.body.role).toBe("protected");

      // Verify access token is valid and has correct type
      const decoded = jwt.verify(res.body.accessToken, JWT_SECRET) as any;
      expect(decoded.uid).toBe("user-123");
      expect(decoded.type).toBe("access");
    });

    it("returns 404 when user does not exist", async () => {
      mockGet.mockResolvedValueOnce({ exists: false });

      const res = await request(app)
        .post("/v1/auth/login")
        .send({ idToken: fakeIdToken("nonexistent") });

      expect(res.status).toBe(404);
      expect(res.body.error).toMatch(/not found|sign up/i);
    });

    it("returns 400 when idToken is missing", async () => {
      const res = await request(app).post("/v1/auth/login").send({});
      expect(res.status).toBe(400);
    });
  });

  // ---- POST /v1/auth/signup ----

  describe("POST /v1/auth/signup", () => {
    it("creates a new user and returns 201 with tokens", async () => {
      // User does not exist yet
      mockGet.mockResolvedValueOnce({ exists: false });

      const res = await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("new-user", "+8613800001001"),
          displayName: "New User",
          role: "protected",
        });

      expect(res.status).toBe(201);
      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
      expect(res.body.userId).toBe("new-user");
      expect(res.body.role).toBe("protected");

      // Verify user doc was created with correct fields
      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          displayName: "New User",
          role: "protected",
          countryCode: "CN", // +86 -> CN
          timeZone: "Asia/Shanghai",
          avatarInitial: "N",
        })
      );
    });

    it("returns 409 when user already exists", async () => {
      mockGet.mockResolvedValueOnce({ exists: true });

      const res = await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("existing-user"),
          displayName: "Existing",
          role: "guardian",
        });

      expect(res.status).toBe(409);
    });

    it("returns 400 for invalid role", async () => {
      const res = await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("user"),
          displayName: "Test",
          role: "admin", // invalid
        });

      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/role/i);
    });

    it("returns 400 when required fields missing", async () => {
      const res = await request(app)
        .post("/v1/auth/signup")
        .send({ idToken: fakeIdToken("user") }); // missing displayName, role

      expect(res.status).toBe(400);
    });

    it("uses client-provided countryCode over phone-derived", async () => {
      mockGet.mockResolvedValueOnce({ exists: false });

      const res = await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("user-ca", "+14165551001"),
          displayName: "Canadian",
          role: "guardian",
          countryCode: "CA",
        });

      expect(res.status).toBe(201);
      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          countryCode: "CA",
          timeZone: "America/Toronto",
        })
      );
    });

    it("derives CN country code from +86 phone number", async () => {
      mockGet.mockResolvedValueOnce({ exists: false });

      await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("user-cn", "+8613800001001"),
          displayName: "Chinese User",
          role: "protected",
        });

      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          countryCode: "CN",
          timeZone: "Asia/Shanghai",
        })
      );
    });

    it("derives FR country code from +33 phone number", async () => {
      mockGet.mockResolvedValueOnce({ exists: false });

      await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("user-fr", "+33612345678"),
          displayName: "French User",
          role: "guardian",
        });

      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          countryCode: "FR",
          timeZone: "Europe/Paris",
        })
      );
    });

    it("derives HK from +852 (3-digit prefix)", async () => {
      mockGet.mockResolvedValueOnce({ exists: false });

      await request(app)
        .post("/v1/auth/signup")
        .send({
          idToken: fakeIdToken("user-hk", "+85291234567"),
          displayName: "HK User",
          role: "protected",
        });

      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          countryCode: "HK",
          timeZone: "Asia/Hong_Kong",
        })
      );
    });
  });

  // ---- POST /v1/auth/refresh ----

  describe("POST /v1/auth/refresh", () => {
    it("issues new tokens for valid refresh token", async () => {
      const refreshToken = jwt.sign(
        { uid: "user-123", type: "refresh" },
        JWT_SECRET,
        { expiresIn: "30d" }
      );

      const res = await request(app)
        .post("/v1/auth/refresh")
        .send({ refreshToken });

      expect(res.status).toBe(200);
      expect(res.body.accessToken).toBeDefined();
      expect(res.body.refreshToken).toBeDefined();
      expect(res.body.userId).toBe("user-123");
    });

    it("rejects access token used as refresh token", async () => {
      const accessToken = jwt.sign(
        { uid: "user-123", type: "access" },
        JWT_SECRET,
        { expiresIn: "1h" }
      );

      const res = await request(app)
        .post("/v1/auth/refresh")
        .send({ refreshToken: accessToken });

      expect(res.status).toBe(401);
    });

    it("rejects expired refresh token", async () => {
      const expired = jwt.sign(
        { uid: "user-123", type: "refresh" },
        JWT_SECRET,
        { expiresIn: "-1s" }
      );

      const res = await request(app)
        .post("/v1/auth/refresh")
        .send({ refreshToken: expired });

      expect(res.status).toBe(401);
    });

    it("returns 400 when refresh token is missing", async () => {
      const res = await request(app).post("/v1/auth/refresh").send({});
      expect(res.status).toBe(400);
    });

    it("rejects token signed with wrong secret", async () => {
      const wrongSecret = jwt.sign(
        { uid: "user-123", type: "refresh" },
        "wrong-secret",
        { expiresIn: "30d" }
      );

      const res = await request(app)
        .post("/v1/auth/refresh")
        .send({ refreshToken: wrongSecret });

      expect(res.status).toBe(401);
    });
  });
});
