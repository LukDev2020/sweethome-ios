import { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";
import { authMiddleware } from "../middleware/auth";

// The middleware uses this as fallback when JWT_SECRET env var is not set
const TEST_JWT_SECRET = "shoudeng-dev-jwt-secret-do-not-use-in-prod";

function buildReq(headers: Record<string, string> = {}): Request {
  return { headers } as unknown as Request;
}

function buildRes(): Response {
  const res: Partial<Response> = {};
  res.status = jest.fn().mockReturnValue(res);
  res.json = jest.fn().mockReturnValue(res);
  return res as Response;
}

describe("authMiddleware", () => {
  const next: NextFunction = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.FUNCTIONS_EMULATOR;
    delete process.env.JWT_SECRET;
  });

  it("returns 401 when no Authorization header is present", async () => {
    const req = buildReq();
    const res = buildRes();

    await authMiddleware(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ error: expect.stringContaining("Missing") })
    );
    expect(next).not.toHaveBeenCalled();
  });

  it("returns 401 when Authorization header does not start with Bearer", async () => {
    const req = buildReq({ authorization: "Basic abc123" });
    const res = buildRes();

    await authMiddleware(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("returns 401 when the token is invalid", async () => {
    const req = buildReq({ authorization: "Bearer invalid-token" });
    const res = buildRes();

    await authMiddleware(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(res.json).toHaveBeenCalledWith(
      expect.objectContaining({ error: expect.stringContaining("Invalid") })
    );
    expect(next).not.toHaveBeenCalled();
  });

  it("returns 401 when a refresh token is used as access token", async () => {
    const refreshToken = jwt.sign(
      { uid: "user-123", type: "refresh" },
      TEST_JWT_SECRET,
      { expiresIn: "30d" }
    );
    const req = buildReq({ authorization: `Bearer ${refreshToken}` });
    const res = buildRes();

    await authMiddleware(req, res, next);

    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });

  it("passes through and sets req.uid with a valid access token", async () => {
    const accessToken = jwt.sign(
      { uid: "user-123", type: "access" },
      TEST_JWT_SECRET,
      { expiresIn: "1h" }
    );
    const req = buildReq({ authorization: `Bearer ${accessToken}` });
    const res = buildRes();

    await authMiddleware(req, res, next);

    expect(req.uid).toBe("user-123");
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  it("decodes token directly when running in emulator mode", async () => {
    process.env.FUNCTIONS_EMULATOR = "true";

    // Build a simple JWT-shaped token with a uid in the payload
    const payload = Buffer.from(
      JSON.stringify({ uid: "emulator-uid-456" })
    ).toString("base64");
    const fakeJwt = `header.${payload}.signature`;

    const req = buildReq({ authorization: `Bearer ${fakeJwt}` });
    const res = buildRes();

    await authMiddleware(req, res, next);

    expect(req.uid).toBe("emulator-uid-456");
    expect(next).toHaveBeenCalled();
  });
});
