import { Request, Response, NextFunction } from "express";

// --- Mock Firestore transaction machinery ---
const mockDocData: Record<string, { count: number; expiresAt: unknown } | undefined> = {};

const mockTx = {
  get: jest.fn(async (docRef: { path: string }) => {
    const data = mockDocData[docRef.path];
    return {
      exists: !!data,
      data: () => data,
    };
  }),
  set: jest.fn((docRef: { path: string }, value: any) => {
    mockDocData[docRef.path] = value;
  }),
  update: jest.fn((docRef: { path: string }, value: any) => {
    if (mockDocData[docRef.path]) {
      Object.assign(mockDocData[docRef.path]!, value);
    }
  }),
};

const mockDocRef = (id: string) => ({ path: `rate_limits/${id}`, id });

jest.mock("firebase-admin", () => {
  const doc = jest.fn((id: string) => mockDocRef(id));
  const collection = jest.fn(() => ({ doc }));
  const runTransaction = jest.fn(async (cb: (tx: any) => Promise<any>) => {
    return cb(mockTx);
  });
  const firestore = Object.assign(jest.fn(() => ({ collection, doc, runTransaction })), {
    Timestamp: {
      now: jest.fn(() => ({ seconds: Math.floor(Date.now() / 1000), nanoseconds: 0 })),
      fromDate: jest.fn((d: Date) => ({ seconds: Math.floor(d.getTime() / 1000), nanoseconds: 0 })),
    },
    FieldValue: { arrayUnion: jest.fn() },
  });
  return {
    firestore,
    initializeApp: jest.fn(),
    auth: jest.fn(() => ({ verifyIdToken: jest.fn() })),
  };
});

// Must also mock the named import used in rateLimit.ts
jest.mock("firebase-admin/firestore", () => ({
  Timestamp: {
    now: jest.fn(() => ({ seconds: Math.floor(Date.now() / 1000), nanoseconds: 0 })),
    fromDate: jest.fn((d: Date) => ({ seconds: Math.floor(d.getTime() / 1000), nanoseconds: 0 })),
  },
}));

import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";

function buildReq(overrides: Partial<Request> = {}): Request {
  return {
    uid: "test-user",
    ip: "127.0.0.1",
    headers: {},
    ...overrides,
  } as unknown as Request;
}

function buildRes(): Response {
  const res: Partial<Response> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  res.set = jest.fn().mockReturnValue(res);
  return res as Response;
}

describe("createRateLimiter", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    // Clear mock store
    Object.keys(mockDocData).forEach((k) => delete mockDocData[k]);
  });

  it("allows requests under the limit", async () => {
    const limiter = createRateLimiter({ windowMs: 60_000, maxRequests: 5 });
    const req = buildReq();
    const res = buildRes();
    const next = jest.fn();

    await limiter(req, res, next);

    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalledWith(429);
    expect(res.set).toHaveBeenCalledWith("X-RateLimit-Limit", "5");
  });

  it("returns 429 when limit is exceeded", async () => {
    const limiter = createRateLimiter({ windowMs: 60_000, maxRequests: 2 });

    // Simulate the transaction returning a count that exceeds maxRequests
    mockTx.get.mockResolvedValueOnce({
      exists: true,
      data: () => ({ count: 2, expiresAt: Date.now() + 60000 }),
    });

    const req = buildReq();
    const res = buildRes();
    const next = jest.fn();

    await limiter(req, res, next);

    expect(next).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(429);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ error: "Too many requests" })
    );
    expect(res.set).toHaveBeenCalledWith("Retry-After", expect.any(String));
  });

  it("fails open when Firestore transaction throws", async () => {
    const admin = require("firebase-admin");
    const firestoreInstance = admin.firestore();
    firestoreInstance.runTransaction.mockRejectedValueOnce(new Error("Firestore unavailable"));

    const limiter = createRateLimiter({ windowMs: 60_000, maxRequests: 5 });
    const req = buildReq();
    const res = buildRes();
    const next = jest.fn();

    await limiter(req, res, next);

    // Fail-open: request should be allowed
    expect(next).toHaveBeenCalled();
  });
});

describe("RATE_LIMITS presets", () => {
  it("auth preset allows 5 requests per 60 seconds", () => {
    expect(RATE_LIMITS.auth).toEqual({
      windowMs: 60_000,
      maxRequests: 5,
    });
  });

  it("sms preset allows 3 requests per 10 minutes", () => {
    expect(RATE_LIMITS.sms).toEqual({
      windowMs: 600_000,
      maxRequests: 3,
    });
  });

  it("sos preset allows 3 requests per hour", () => {
    expect(RATE_LIMITS.sos).toEqual({
      windowMs: 3_600_000,
      maxRequests: 3,
    });
  });

  it("general preset allows 100 requests per minute", () => {
    expect(RATE_LIMITS.general).toEqual({
      windowMs: 60_000,
      maxRequests: 100,
    });
  });

  it("publicShare preset allows 20 requests per hour", () => {
    expect(RATE_LIMITS.publicShare).toEqual({
      windowMs: 3_600_000,
      maxRequests: 20,
    });
  });

  it("telemetry preset allows 120 requests per minute", () => {
    expect(RATE_LIMITS.telemetry).toEqual({
      windowMs: 60_000,
      maxRequests: 120,
    });
  });
});
