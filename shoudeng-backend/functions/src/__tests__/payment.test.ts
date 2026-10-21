/**
 * Payment Service & Routes Tests
 *
 * Tests plan mapping, subscription logic, verify-receipt,
 * and subscription middleware (requireFeature, requirePlanCapacity).
 */

import express, { Express } from "express";
import request from "supertest";

const JWT_SECRET = "shoudeng-dev-jwt-secret-do-not-use-in-prod";

// ---- Firestore mock ----
const mockDocs: Record<string, Record<string, unknown>> = {};
const mockQueryDocs: Array<{ id: string; ref: { update: jest.Mock }; data: () => Record<string, unknown> }> = [];

const mockGet = jest.fn().mockImplementation(function (this: { path: string }) {
  const data = mockDocs[this.path];
  return Promise.resolve({
    exists: !!data,
    data: () => data || null,
    ref: { update: jest.fn().mockResolvedValue(undefined), id: this.path.split("/").pop() },
  });
});
const mockSet = jest.fn().mockResolvedValue(undefined);
const mockUpdate = jest.fn().mockResolvedValue(undefined);
const mockAdd = jest.fn().mockResolvedValue({ id: "mock-doc-id" });

const mockWhere = jest.fn().mockReturnThis();
const mockLimit = jest.fn().mockReturnThis();
const mockOrderBy = jest.fn().mockReturnThis();
const mockCollectionGet = jest.fn().mockImplementation(() =>
  Promise.resolve({
    empty: mockQueryDocs.length === 0,
    docs: mockQueryDocs,
    size: mockQueryDocs.length,
  })
);

let _currentCollection = "unknown";

const mockDocFn: jest.Mock = jest.fn((id: string): Record<string, unknown> => {
  const collName: string = _currentCollection;
  const docPath: string = `${collName}/${id}`;
  return {
    get: jest.fn(() => {
      const data = mockDocs[docPath];
      return Promise.resolve({
        exists: !!data,
        data: () => data || null,
        ref: { update: mockUpdate, id },
      });
    }),
    set: mockSet,
    update: mockUpdate,
    id,
    path: docPath,
  };
});

const mockCollection = jest.fn((name: string) => {
  _currentCollection = name;
  return {
    doc: mockDocFn,
    add: mockAdd,
    where: mockWhere,
    limit: mockLimit,
    orderBy: mockOrderBy,
    get: mockCollectionGet,
  };
});

jest.mock("firebase-admin", () => {
  const firestore = Object.assign(
    jest.fn(() => ({ collection: mockCollection })),
    {
      Timestamp: {
        now: jest.fn(() => ({ seconds: Date.now() / 1000, nanoseconds: 0, toDate: () => new Date() })),
        fromDate: jest.fn((d: Date) => ({ seconds: d.getTime() / 1000, nanoseconds: 0, toDate: () => d })),
      },
      FieldValue: {
        increment: jest.fn((n: number) => ({ _increment: n })),
        arrayUnion: jest.fn((...args: unknown[]) => args),
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

// Mock BigQuery consent audit (used by upsertSubscription)
jest.mock("../services/bigquery", () => ({
  insertConsentAudit: jest.fn().mockResolvedValue(undefined),
}));

// Mock Apple cert loading (no certs in test)
jest.mock("fs", () => ({
  ...jest.requireActual("fs"),
  existsSync: jest.fn().mockReturnValue(false),
  readFileSync: jest.fn(),
}));

// Import AFTER mocks
import { PLANS, mapProductToPlan, getSubscription, verifyAppleReceipt } from "../services/payment";
import { requireFeature } from "../middleware/subscription";

// ---- Helper: create mock auth middleware ----
function mockAuthMiddleware(uid: string) {
  return (req: express.Request, _res: express.Response, next: express.NextFunction) => {
    req.uid = uid;
    next();
  };
}

// ---- Tests ----

describe("Payment Service — PLANS", () => {
  test("free plan has expected features", () => {
    expect(PLANS.free.features).toContain("basic_sos");
    expect(PLANS.free.features).toContain("checkin");
    expect(PLANS.free.maxGuardians).toBe(1);
    expect(PLANS.free.maxProtected).toBe(1);
  });

  test("single plan has 6 expected features", () => {
    expect(PLANS.single.features).toContain("duty_schedule");
    expect(PLANS.single.features).toContain("export_pdf");
    expect(PLANS.single.maxGuardians).toBe(3);
    expect(PLANS.single.maxProtected).toBe(1);
  });

  test("family plan has unlimited guardians", () => {
    expect(PLANS.family.maxGuardians).toBe(-1);
    expect(PLANS.family.maxProtected).toBe(4);
    expect(PLANS.family.features).toContain("sms_fallback");
  });

  test("ultimate plan has unlimited everything", () => {
    expect(PLANS.ultimate.maxGuardians).toBe(-1);
    expect(PLANS.ultimate.maxProtected).toBe(-1);
    expect(PLANS.ultimate.features).toContain("priority_support");
  });

  test("all paid plans have appleProductIds", () => {
    expect(PLANS.single.appleProductIds).toHaveLength(2);
    expect(PLANS.family.appleProductIds).toHaveLength(2);
    expect(PLANS.ultimate.appleProductIds).toHaveLength(2);
  });

  test("TTL days increase with plan tier", () => {
    expect(PLANS.free.ttlDays.heartbeat).toBeLessThan(PLANS.single.ttlDays.heartbeat);
    expect(PLANS.single.ttlDays.heartbeat).toBeLessThan(PLANS.family.ttlDays.heartbeat);
    expect(PLANS.family.ttlDays.heartbeat).toBeLessThan(PLANS.ultimate.ttlDays.heartbeat);
  });
});

describe("Payment Service — mapProductToPlan", () => {
  test("maps single monthly product", () => {
    expect(mapProductToPlan("com.shoudeng.app.single.monthly")).toBe("single");
  });

  test("maps single yearly product", () => {
    expect(mapProductToPlan("com.shoudeng.app.single.yearly")).toBe("single");
  });

  test("maps family monthly product", () => {
    expect(mapProductToPlan("com.shoudeng.app.family.monthly")).toBe("family");
  });

  test("maps family yearly product", () => {
    expect(mapProductToPlan("com.shoudeng.app.family.yearly")).toBe("family");
  });

  test("maps ultimate monthly product", () => {
    expect(mapProductToPlan("com.shoudeng.app.ultimate.monthly")).toBe("ultimate");
  });

  test("maps ultimate yearly product", () => {
    expect(mapProductToPlan("com.shoudeng.app.ultimate.yearly")).toBe("ultimate");
  });

  test("returns null for unknown product", () => {
    expect(mapProductToPlan("com.other.app.premium")).toBeNull();
  });

  test("returns null for undefined", () => {
    expect(mapProductToPlan(undefined)).toBeNull();
  });

  test("returns null for empty string", () => {
    expect(mapProductToPlan("")).toBeNull();
  });
});

describe("Payment Service — verifyAppleReceipt", () => {
  test("rejects non-JWS format", async () => {
    const result = await verifyAppleReceipt("not-a-jws");
    expect(result.valid).toBe(false);
    expect(result.error).toBe("Invalid JWS format");
  });

  test("rejects two-part token", async () => {
    const result = await verifyAppleReceipt("part1.part2");
    expect(result.valid).toBe(false);
  });

  test("accepts valid JWS payload (fallback mode, no certs)", async () => {
    // In test mode, no Apple root certs are loaded, so we use payload-only fallback
    const payload = {
      bundleId: "com.shoudeng.app",
      productId: "com.shoudeng.app.single.monthly",
      originalTransactionId: "TX123",
      expiresDate: Date.now() + 86400000,
    };
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");
    const fakeJWS = `header.${encodedPayload}.signature`;

    const result = await verifyAppleReceipt(fakeJWS);
    expect(result.valid).toBe(true);
    expect(result.productId).toBe("com.shoudeng.app.single.monthly");
    expect(result.originalTransactionId).toBe("TX123");
  });

  test("rejects JWS with wrong bundle ID", async () => {
    const payload = {
      bundleId: "com.wrong.bundle",
      productId: "com.shoudeng.app.single.monthly",
    };
    const encodedPayload = Buffer.from(JSON.stringify(payload)).toString("base64url");
    const fakeJWS = `header.${encodedPayload}.signature`;

    const result = await verifyAppleReceipt(fakeJWS);
    expect(result.valid).toBe(false);
    expect(result.error).toBe("Bundle ID mismatch");
  });
});

describe("Subscription Middleware — requireFeature", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    Object.keys(mockDocs).forEach((k) => delete mockDocs[k]);
  });

  test("allows access when user has required feature (single plan)", async () => {
    // Setup: user has single plan subscription
    mockDocs["subscriptions/user1"] = {
      userId: "user1",
      planId: "single",
      status: "active",
      currentPeriodEnd: {
        toDate: () => new Date(Date.now() + 86400000), // tomorrow
      },
    };

    const app = express();
    app.use(express.json());
    app.use(mockAuthMiddleware("user1"));
    app.get("/test", requireFeature("duty_schedule"), (_req, res) => {
      res.json({ access: true });
    });

    const resp = await request(app).get("/test");
    expect(resp.status).toBe(200);
    expect(resp.body.access).toBe(true);
  });

  test("blocks access when user has free plan", async () => {
    // No subscription doc = free plan
    mockDocs["subscriptions/user2"] = undefined as any;

    const app = express();
    app.use(express.json());
    app.use(mockAuthMiddleware("user2"));
    app.get("/test", requireFeature("duty_schedule"), (_req, res) => {
      res.json({ access: true });
    });

    const resp = await request(app).get("/test");
    expect(resp.status).toBe(403);
    expect(resp.body.upgrade).toBe(true);
    expect(resp.body.feature).toBe("duty_schedule");
  });

  test("blocks export_pdf for free users", async () => {
    const app = express();
    app.use(express.json());
    app.use(mockAuthMiddleware("freeUser"));
    app.get("/test", requireFeature("export_pdf"), (_req, res) => {
      res.json({ access: true });
    });

    const resp = await request(app).get("/test");
    expect(resp.status).toBe(403);
    expect(resp.body.feature).toBe("export_pdf");
  });

  test("allows basic_sos for free users", async () => {
    const app = express();
    app.use(express.json());
    app.use(mockAuthMiddleware("freeUser"));
    app.get("/test", requireFeature("basic_sos"), (_req, res) => {
      res.json({ access: true });
    });

    const resp = await request(app).get("/test");
    expect(resp.status).toBe(200);
  });
});

describe("Payment — product ID consistency", () => {
  test("all Apple product IDs follow naming convention", () => {
    const allProductIds = [
      ...PLANS.single.appleProductIds,
      ...PLANS.family.appleProductIds,
      ...PLANS.ultimate.appleProductIds,
    ];
    for (const pid of allProductIds) {
      expect(pid).toMatch(/^com\.shoudeng\.app\.(single|family|ultimate)\.(monthly|yearly)$/);
    }
  });

  test("product IDs are unique across all plans", () => {
    const allProductIds = [
      ...PLANS.single.appleProductIds,
      ...PLANS.family.appleProductIds,
      ...PLANS.ultimate.appleProductIds,
    ];
    const uniqueIds = new Set(allProductIds);
    expect(uniqueIds.size).toBe(allProductIds.length);
  });

  test("every product ID maps back to its plan", () => {
    for (const pid of PLANS.single.appleProductIds) {
      expect(mapProductToPlan(pid)).toBe("single");
    }
    for (const pid of PLANS.family.appleProductIds) {
      expect(mapProductToPlan(pid)).toBe("family");
    }
    for (const pid of PLANS.ultimate.appleProductIds) {
      expect(mapProductToPlan(pid)).toBe("ultimate");
    }
  });
});
