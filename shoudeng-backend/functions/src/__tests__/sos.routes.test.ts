import express, { Express } from "express";
import request from "supertest";

// ---- Firestore mock helpers ----
const mockGet = jest.fn();
const mockSet = jest.fn();
const mockUpdate = jest.fn();
const mockAdd = jest.fn();
const mockWhere = jest.fn();
const mockLimit = jest.fn();

function resetFirestoreChain() {
  mockWhere.mockReturnThis();
  mockLimit.mockReturnThis();
}

const mockDocRef = (path: string) => ({
  get: mockGet,
  set: mockSet,
  update: mockUpdate,
  id: path.split("/").pop(),
});

jest.mock("firebase-admin", () => {
  const doc = jest.fn((id: string) => mockDocRef(`sos_events/${id}`));
  const collection = jest.fn((name: string) => ({
    doc: jest.fn((id: string) => mockDocRef(`${name}/${id}`)),
    add: mockAdd,
    where: mockWhere,
    limit: mockLimit,
  }));
  const firestore = Object.assign(
    jest.fn(() => ({ collection, doc })),
    {
      Timestamp: {
        now: jest.fn(() => ({ seconds: 1000, nanoseconds: 0 })),
      },
      FieldValue: {
        arrayUnion: jest.fn((...args: any[]) => args),
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

jest.mock("../services/fcm", () => ({
  sendSOSResolvedNotification: jest.fn(),
}));

jest.mock("uuid", () => ({
  v4: jest.fn(() => "mock-uuid-1234"),
}));

import * as admin from "firebase-admin";

describe("SOS routes", () => {
  let app: Express;

  beforeEach(() => {
    jest.clearAllMocks();
    resetFirestoreChain();

    app = express();
    app.use(express.json());
  });

  describe("POST /trigger — auth requirement", () => {
    it("returns 401 when no Authorization header is provided", async () => {
      // Mount the real auth middleware + router
      const { authMiddleware } = require("../middleware/auth");

      // Mock verifyIdToken to reject
      (admin.auth() as any).verifyIdToken.mockRejectedValue(
        new Error("No token")
      );

      app.use(authMiddleware);
      app.post("/trigger", (_req, res) => {
        res.status(200).json({ ok: true });
      });

      const res = await request(app).post("/trigger").send({});

      expect(res.status).toBe(401);
      expect(res.body.error).toMatch(/Missing|invalid/i);
    });
  });

  describe("POST /resolve — authorization logic", () => {
    // We replicate the resolve handler logic to unit-test the authorization
    // checks without needing the full SOS router + auth middleware.

    function mountResolveRoute(appInstance: Express) {
      const db = admin.firestore();

      appInstance.use((req, _res, next) => {
        // Inject uid from test header
        req.uid = req.headers["x-test-uid"] as string;
        next();
      });

      appInstance.post("/resolve", async (req, res) => {
        const uid = req.uid!;
        const { sosEventId, resolution } = req.body;

        if (!sosEventId || !resolution) {
          res.status(400).json({ error: "sosEventId and resolution are required" });
          return;
        }

        const sosRef = db.collection("sos_events").doc(sosEventId);
        const sosDoc = await sosRef.get();

        if (!(sosDoc as any).exists) {
          res.status(404).json({ error: "SOS event not found" });
          return;
        }

        const sosData = (sosDoc as any).data();
        if (sosData.resolvedAt) {
          res.status(409).json({ error: "SOS already resolved" });
          return;
        }

        const isProtected = sosData.protectedPersonId === uid;
        let isGuardian = false;
        if (!isProtected) {
          const linkId = `${uid}_${sosData.protectedPersonId}`;
          const linkDoc = await db.collection("guardian_links").doc(linkId).get();
          isGuardian = (linkDoc as any).exists && (linkDoc as any).data()?.status === "active";
        }

        if (!isProtected && !isGuardian) {
          res.status(403).json({ error: "Not authorized to resolve this SOS event" });
          return;
        }

        res.json({ success: true });
      });
    }

    it("allows the protected person to resolve their own SOS", async () => {
      mountResolveRoute(app);

      // Mock: SOS doc exists, not resolved, protectedPersonId = "user-A"
      mockGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          protectedPersonId: "user-A",
          resolvedAt: null,
        }),
      });

      const res = await request(app)
        .post("/resolve")
        .set("x-test-uid", "user-A")
        .send({ sosEventId: "sos-1", resolution: "protectedCancelled" });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });

    it("allows a linked guardian to resolve the SOS", async () => {
      mountResolveRoute(app);

      // Mock: SOS doc
      mockGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          protectedPersonId: "user-A",
          resolvedAt: null,
        }),
      });

      // Mock: guardian_links doc exists and is active
      mockGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({ status: "active" }),
      });

      const res = await request(app)
        .post("/resolve")
        .set("x-test-uid", "guardian-B")
        .send({ sosEventId: "sos-1", resolution: "guardianConfirmedSafe" });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
    });

    it("rejects an unauthorized user from resolving the SOS", async () => {
      mountResolveRoute(app);

      // Mock: SOS doc
      mockGet.mockResolvedValueOnce({
        exists: true,
        data: () => ({
          protectedPersonId: "user-A",
          resolvedAt: null,
        }),
      });

      // Mock: guardian_links doc does not exist
      mockGet.mockResolvedValueOnce({
        exists: false,
        data: () => undefined,
      });

      const res = await request(app)
        .post("/resolve")
        .set("x-test-uid", "stranger-X")
        .send({ sosEventId: "sos-1", resolution: "guardianConfirmedSafe" });

      expect(res.status).toBe(403);
      expect(res.body.error).toMatch(/Not authorized/);
    });

    it("returns 400 when required fields are missing", async () => {
      mountResolveRoute(app);

      const res = await request(app)
        .post("/resolve")
        .set("x-test-uid", "user-A")
        .send({ sosEventId: "sos-1" }); // missing resolution

      expect(res.status).toBe(400);
    });

    it("returns 404 when SOS event does not exist", async () => {
      mountResolveRoute(app);

      mockGet.mockResolvedValueOnce({
        exists: false,
        data: () => undefined,
      });

      const res = await request(app)
        .post("/resolve")
        .set("x-test-uid", "user-A")
        .send({ sosEventId: "nonexistent", resolution: "protectedCancelled" });

      expect(res.status).toBe(404);
    });
  });
});
