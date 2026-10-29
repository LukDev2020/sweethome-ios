import express, { Express } from "express";
import request from "supertest";

// Mock auth middleware to pass through with x-test-uid header
jest.mock("../middleware/auth", () => ({
  authMiddleware: (req: any, res: any, next: any) => {
    const uid = req.headers["x-test-uid"];
    if (!uid) {
      res.status(401).json({ error: "Missing auth" });
      return;
    }
    req.uid = uid;
    next();
  },
}));

// ---- Firestore mock helpers ----
const mockGet = jest.fn();
const mockSet = jest.fn();
const mockUpdate = jest.fn();
const mockBatchSet = jest.fn();
const mockBatchUpdate = jest.fn();
const mockBatchCommit = jest.fn();
const mockWhere = jest.fn();
const mockOrderBy = jest.fn();
const mockLimit = jest.fn();
const mockGetDocs = jest.fn();

function resetChain() {
  mockWhere.mockReturnThis();
  mockOrderBy.mockReturnThis();
  mockLimit.mockReturnThis();
  mockGetDocs.mockResolvedValue({ docs: [], size: 0 });
}

const mockDocRef = (path: string) => ({
  get: mockGet,
  set: mockSet,
  update: mockUpdate,
  id: path.split("/").pop(),
  collection: jest.fn(() => ({
    doc: jest.fn(() => ({ set: mockBatchSet })),
    orderBy: mockOrderBy,
    get: mockGetDocs,
  })),
});

jest.mock("firebase-admin", () => {
  const doc = jest.fn((id: string) => mockDocRef(`trips/${id}`));
  const collection = jest.fn((name: string) => ({
    doc: jest.fn((id: string) => mockDocRef(`${name}/${id}`)),
    where: mockWhere,
    orderBy: mockOrderBy,
    limit: mockLimit,
    get: mockGetDocs,
  }));
  const firestore = Object.assign(
    jest.fn(() => ({ collection, doc, batch: jest.fn(() => ({
      set: mockBatchSet,
      update: mockBatchUpdate,
      commit: mockBatchCommit,
    })) })),
    {
      Timestamp: {
        now: jest.fn(() => ({
          seconds: 1000,
          nanoseconds: 0,
          toDate: () => new Date("2026-10-28T12:00:00Z"),
        })),
      },
      FieldValue: {
        increment: jest.fn((n: number) => ({ _increment: n }),),
      },
    }
  );
  return {
    firestore,
    initializeApp: jest.fn(),
  };
});

jest.mock("uuid", () => ({
  v4: jest.fn(() => "trip-uuid-1234"),
}));

import tripRouter from "../routes/trip";

function createApp(): Express {
  const app = express();
  app.use(express.json());
  app.use("/", tripRouter);
  return app;
}

describe("Trip routes", () => {
  let app: Express;

  beforeEach(() => {
    jest.clearAllMocks();
    resetChain();
    app = createApp();
  });

  // =================== POST /start ===================
  describe("POST /start", () => {
    it("creates a new trip and returns tripId + startTime", async () => {
      mockSet.mockResolvedValue(undefined);

      const res = await request(app)
        .post("/start")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(201);
      expect(res.body.tripId).toBe("trip-uuid-1234");
      expect(res.body.startTime).toBeDefined();
    });

    it("sets correct initial trip data", async () => {
      mockSet.mockResolvedValue(undefined);

      await request(app)
        .post("/start")
        .set("x-test-uid", "user-1")
        .send({});

      expect(mockSet).toHaveBeenCalledWith(
        expect.objectContaining({
          userId: "user-1",
          status: "recording",
          totalDistanceMeters: 0,
          pointCount: 0,
          durationSeconds: 0,
          primaryTransportMode: null,
          segments: [],
          endTime: null,
        })
      );
    });

    it("returns 500 when Firestore write fails", async () => {
      mockSet.mockRejectedValueOnce(new Error("Firestore down"));

      const res = await request(app)
        .post("/start")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(500);
      expect(res.body.error).toBe("Failed to start trip");
    });
  });

  // =================== POST /:tripId/points ===================
  describe("POST /:tripId/points", () => {
    it("returns 400 when points array is missing", async () => {
      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/points/i);
    });

    it("returns 400 when points array is empty", async () => {
      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points: [] });

      expect(res.status).toBe(400);
    });

    it("returns 404 when trip not found", async () => {
      mockGet.mockResolvedValue({ exists: false });

      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points: [{ latitude: 39.9, longitude: 116.4 }] });

      expect(res.status).toBe(404);
    });

    it("returns 404 when trip belongs to different user", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "other-user", status: "recording" }),
      });

      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points: [{ latitude: 39.9, longitude: 116.4 }] });

      expect(res.status).toBe(404);
    });

    it("returns 400 when trip is not recording (completed)", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "user-1", status: "completed" }),
      });

      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points: [{ latitude: 39.9, longitude: 116.4 }] });

      expect(res.status).toBe(400);
      expect(res.body.error).toMatch(/not recording/i);
    });

    it("returns 400 when trip is cancelled", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "user-1", status: "cancelled" }),
      });

      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points: [{ latitude: 39.9, longitude: 116.4 }] });

      expect(res.status).toBe(400);
      expect(res.body.error).toBe("Trip is not recording");
    });

    it("adds 2 GPS points to an active trip", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "user-1", status: "recording" }),
      });
      mockBatchCommit.mockResolvedValue(undefined);

      const points = [
        { latitude: 40.7128, longitude: -74.006, accuracy: 5 },
        { latitude: 40.7138, longitude: -74.005, accuracy: 3 },
      ];

      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.added).toBe(2);
      expect(mockBatchSet).toHaveBeenCalledTimes(2);
      expect(mockBatchUpdate).toHaveBeenCalledTimes(1);
      expect(mockBatchCommit).toHaveBeenCalledTimes(1);
    });

    it("caps points batch at 100 per request", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "user-1", status: "recording" }),
      });
      mockBatchCommit.mockResolvedValue(undefined);

      // Send 105 points — should cap at 100
      const points = Array.from({ length: 105 }, (_, i) => ({
        latitude: 39.9 + i * 0.001,
        longitude: 116.4 + i * 0.001,
        accuracy: 10,
      }));

      const res = await request(app)
        .post("/trip-1/points")
        .set("x-test-uid", "user-1")
        .send({ points });

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(res.body.added).toBe(100);
    });
  });

  // =================== POST /:tripId/end ===================
  describe("POST /:tripId/end", () => {
    it("returns 404 when trip not found", async () => {
      mockGet.mockResolvedValue({ exists: false });

      const res = await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(404);
    });

    it("returns 400 when trip is not recording", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "user-1", status: "completed" }),
      });

      const res = await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(400);
    });

    it("ends a recording trip and returns summary", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "recording",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });
      mockGetDocs.mockResolvedValue({
        docs: [
          { data: () => ({ latitude: 39.90, longitude: 116.40, speed: 1.5, timestamp: "2026-10-28T10:00:00Z" }) },
          { data: () => ({ latitude: 39.91, longitude: 116.41, speed: 1.6, timestamp: "2026-10-28T10:30:00Z" }) },
        ],
        size: 2,
      });
      mockUpdate.mockResolvedValue(undefined);

      const res = await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(200);
      expect(res.body.tripId).toBe("trip-1");
      expect(res.body.totalDistanceMeters).toBeGreaterThan(0);
      expect(res.body.pointCount).toBe(2);
      expect(res.body.durationSeconds).toBeGreaterThan(0);
    });

    it("infers walking mode for low-speed trips (~5 km/h)", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "recording",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });
      // Speed ~1.5 m/s = ~5.4 km/h => walking
      mockGetDocs.mockResolvedValue({
        size: 2,
        docs: [
          { data: () => ({ latitude: 40.7128, longitude: -74.006, speed: 1.5 }) },
          { data: () => ({ latitude: 40.7138, longitude: -74.005, speed: 1.5 }) },
        ],
      });

      await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ primaryTransportMode: "walking" })
      );
    });

    it("infers cycling mode for medium-speed trips (~30 km/h)", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "recording",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });
      // Speed ~8 m/s = ~28.8 km/h => cycling
      mockGetDocs.mockResolvedValue({
        size: 2,
        docs: [
          { data: () => ({ latitude: 40.7128, longitude: -74.006, speed: 8 }) },
          { data: () => ({ latitude: 40.7138, longitude: -74.005, speed: 8 }) },
        ],
      });

      await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ primaryTransportMode: "cycling" })
      );
    });

    it("infers driving mode for high-speed trips (~90 km/h)", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "recording",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });
      // Speed ~25 m/s = ~90 km/h => driving
      mockGetDocs.mockResolvedValue({
        size: 2,
        docs: [
          { data: () => ({ latitude: 40.7128, longitude: -74.006, speed: 25 }) },
          { data: () => ({ latitude: 40.7138, longitude: -74.005, speed: 25 }) },
        ],
      });

      await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ primaryTransportMode: "driving" })
      );
    });

    it("infers stationary mode when no speed data is available", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "recording",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });
      mockGetDocs.mockResolvedValue({
        size: 1,
        docs: [
          { data: () => ({ latitude: 40.7128, longitude: -74.006, speed: null }) },
        ],
      });

      await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ primaryTransportMode: "stationary" })
      );
    });

    it("returns 404 when trip is not owned by user", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "other-user", status: "recording" }),
      });

      const res = await request(app)
        .post("/trip-1/end")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(404);
      expect(res.body.error).toBe("Trip not found");
    });
  });

  // =================== POST /:tripId/cancel ===================
  describe("POST /:tripId/cancel", () => {
    it("returns 404 when trip not found", async () => {
      mockGet.mockResolvedValue({ exists: false });

      const res = await request(app)
        .post("/trip-1/cancel")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(404);
    });

    it("cancels an owned trip", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "user-1", status: "recording" }),
      });
      mockUpdate.mockResolvedValue(undefined);

      const res = await request(app)
        .post("/trip-1/cancel")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(200);
      expect(res.body.success).toBe(true);
      expect(mockUpdate).toHaveBeenCalledWith(
        expect.objectContaining({ status: "cancelled" })
      );
    });

    it("returns 404 when trip is not owned by user", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ userId: "other-user", status: "recording" }),
      });

      const res = await request(app)
        .post("/trip-1/cancel")
        .set("x-test-uid", "user-1")
        .send({});

      expect(res.status).toBe(404);
      expect(res.body.error).toBe("Trip not found");
    });
  });

  // =================== GET /list ===================
  describe("GET /list", () => {
    it("lists own trips", async () => {
      mockGetDocs.mockResolvedValue({
        docs: [
          {
            id: "trip-1",
            data: () => ({
              userId: "user-1",
              status: "completed",
              startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
              endTime: { toDate: () => new Date("2026-10-28T11:00:00Z") },
              totalDistanceMeters: 5000,
              pointCount: 100,
              durationSeconds: 3600,
              primaryTransportMode: "walking",
            }),
          },
        ],
      });

      const res = await request(app)
        .get("/list")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(200);
      expect(res.body.trips).toHaveLength(1);
      expect(res.body.trips[0].id).toBe("trip-1");
      expect(res.body.trips[0].totalDistanceMeters).toBe(5000);
    });

    it("returns 403 when querying another user without guardian link", async () => {
      // First call: guardian_links doc check
      mockGet.mockResolvedValue({ exists: false });

      const res = await request(app)
        .get("/list?userId=protected-1")
        .set("x-test-uid", "guardian-1");

      expect(res.status).toBe(403);
    });

    it("allows guardian to view protected person trips with active link", async () => {
      // guardian_links doc check
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ status: "active" }),
      });
      // trips query
      mockGetDocs.mockResolvedValue({ docs: [] });

      const res = await request(app)
        .get("/list?userId=protected-1")
        .set("x-test-uid", "guardian-1");

      expect(res.status).toBe(200);
      expect(res.body.trips).toEqual([]);
    });

    it("returns 403 when guardian link exists but is not active", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({ status: "pending" }),
      });

      const res = await request(app)
        .get("/list?userId=protected-1")
        .set("x-test-uid", "guardian-1");

      expect(res.status).toBe(403);
      expect(res.body.error).toMatch(/Not authorized/);
    });
  });

  // =================== GET /:tripId ===================
  describe("GET /:tripId (detail)", () => {
    it("returns 404 for non-existent trip", async () => {
      mockGet.mockResolvedValue({ exists: false });

      const res = await request(app)
        .get("/trip-1")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(404);
    });

    it("returns 403 for unauthorized user", async () => {
      mockGet
        .mockResolvedValueOnce({
          exists: true,
          data: () => ({ userId: "other-user", status: "completed" }),
        })
        .mockResolvedValueOnce({ exists: false }); // guardian_links check

      const res = await request(app)
        .get("/trip-1")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(403);
    });

    it("returns trip detail with points for owner", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        id: "trip-1",
        data: () => ({
          userId: "user-1",
          status: "completed",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
          endTime: { toDate: () => new Date("2026-10-28T11:00:00Z") },
          totalDistanceMeters: 5000,
          pointCount: 2,
          durationSeconds: 3600,
          primaryTransportMode: "walking",
          segments: [],
        }),
      });
      mockGetDocs.mockResolvedValue({
        docs: [
          { data: () => ({ latitude: 39.9, longitude: 116.4, timestamp: "2026-10-28T10:00:00Z" }) },
          { data: () => ({ latitude: 39.91, longitude: 116.41, timestamp: "2026-10-28T10:30:00Z" }) },
        ],
      });

      const res = await request(app)
        .get("/trip-1")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(200);
      expect(res.body.trip.id).toBe("trip-1");
      expect(res.body.points).toHaveLength(2);
      expect(res.body.segments).toEqual([]);
    });

    it("allows a linked guardian to view trip detail", async () => {
      mockGet
        .mockResolvedValueOnce({
          exists: true,
          id: "trip-1",
          data: () => ({
            userId: "protected-1",
            status: "completed",
            startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
            endTime: { toDate: () => new Date("2026-10-28T11:00:00Z") },
            totalDistanceMeters: 5000,
            pointCount: 1,
            durationSeconds: 3600,
            primaryTransportMode: "walking",
            segments: [],
          }),
        })
        .mockResolvedValueOnce({
          exists: true,
          data: () => ({ status: "active" }),
        });

      mockGetDocs.mockResolvedValue({
        docs: [
          { data: () => ({ latitude: 40.7128, longitude: -74.006 }) },
        ],
      });

      const res = await request(app)
        .get("/trip-1")
        .set("x-test-uid", "guardian-1");

      expect(res.status).toBe(200);
      expect(res.body.trip).toBeDefined();
      expect(res.body.points).toHaveLength(1);
    });
  });

  // =================== GET /:tripId/export ===================
  describe("GET /:tripId/export (GPX)", () => {
    it("returns 404 for non-existent trip", async () => {
      mockGet.mockResolvedValue({ exists: false });

      const res = await request(app)
        .get("/trip-1/export")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(404);
    });

    it("exports valid GPX XML for owner", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "completed",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });
      mockGetDocs.mockResolvedValue({
        docs: [
          { data: () => ({ latitude: 39.9, longitude: 116.4, altitude: 50, speed: 1.5, timestamp: "2026-10-28T10:00:00Z" }) },
          { data: () => ({ latitude: 39.91, longitude: 116.41, altitude: 52, speed: 1.6, timestamp: "2026-10-28T10:30:00Z" }) },
        ],
      });

      const res = await request(app)
        .get("/trip-1/export")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(200);
      expect(res.headers["content-type"]).toMatch(/gpx/);
      expect(res.text).toContain('<?xml version="1.0"');
      expect(res.text).toContain("<gpx");
      expect(res.text).toContain("<trkpt");
      expect(res.text).toContain('lat="39.9"');
      expect(res.text).toContain('lon="116.4"');
      expect(res.text).toContain("<ele>50</ele>");
      expect(res.text).toContain("<speed>1.5</speed>");
    });

    it("returns 403 for unauthorized user without guardian link", async () => {
      mockGet
        .mockResolvedValueOnce({
          exists: true,
          data: () => ({ userId: "other-user" }),
        })
        .mockResolvedValueOnce({ exists: false }); // guardian_links

      const res = await request(app)
        .get("/trip-1/export")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(403);
    });

    it("allows a linked guardian to export trip GPX", async () => {
      mockGet
        .mockResolvedValueOnce({
          exists: true,
          data: () => ({
            userId: "protected-1",
            status: "completed",
            startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
          }),
        })
        .mockResolvedValueOnce({
          exists: true,
          data: () => ({ status: "active" }),
        });

      mockGetDocs.mockResolvedValue({
        docs: [
          {
            data: () => ({
              latitude: 40.7128,
              longitude: -74.006,
              altitude: null,
              timestamp: "2026-10-28T10:00:00Z",
              speed: null,
            }),
          },
        ],
      });

      const res = await request(app)
        .get("/trip-1/export")
        .set("x-test-uid", "guardian-1");

      expect(res.status).toBe(200);
      expect(res.text).toContain("<gpx");
      expect(res.text).toContain('<trkpt lat="40.7128" lon="-74.006">');
      // No altitude or speed tags when values are null
      expect(res.text).not.toContain("<ele>");
      expect(res.text).not.toContain("<speed>");
    });

    it("sets Content-Disposition filename with trip start date", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "completed",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });

      mockGetDocs.mockResolvedValue({ docs: [] });

      const res = await request(app)
        .get("/trip-1/export")
        .set("x-test-uid", "user-1");

      expect(res.status).toBe(200);
      expect(res.headers["content-disposition"]).toContain("trip-2026-10-28.gpx");
    });

    it("includes full GPX structure with trk, trkseg, and trkpt elements", async () => {
      mockGet.mockResolvedValue({
        exists: true,
        data: () => ({
          userId: "user-1",
          status: "completed",
          startTime: { toDate: () => new Date("2026-10-28T10:00:00Z") },
        }),
      });

      mockGetDocs.mockResolvedValue({
        docs: [
          {
            data: () => ({
              latitude: 40.7128,
              longitude: -74.006,
              altitude: 15,
              timestamp: "2026-10-28T10:00:00Z",
              speed: 2.0,
            }),
          },
        ],
      });

      const res = await request(app)
        .get("/trip-1/export")
        .set("x-test-uid", "user-1");

      const gpx = res.text;
      expect(gpx).toContain('<?xml version="1.0" encoding="UTF-8"?>');
      expect(gpx).toContain("Lantern Care");
      expect(gpx).toContain("<trk>");
      expect(gpx).toContain("<trkseg>");
      expect(gpx).toContain("</trkseg>");
      expect(gpx).toContain("</trk>");
      expect(gpx).toContain("</gpx>");
      expect(gpx).toContain("<ele>15</ele>");
      expect(gpx).toContain("<time>2026-10-28T10:00:00Z</time>");
      expect(gpx).toContain("<speed>2</speed>");
    });
  });
});
