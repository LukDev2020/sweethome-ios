import { Request, Response, NextFunction } from "express";
import jwt from "jsonwebtoken";

const JWT_SECRET =
  process.env.JWT_SECRET || "shoudeng-dev-jwt-secret-do-not-use-in-prod";

// Extend Express Request with authenticated user info
declare global {
  namespace Express {
    interface Request {
      uid?: string;
    }
  }
}

/**
 * Decode a token to extract uid.
 * In emulator mode, decodes JWT payload directly (accepts any JWT shape).
 * In production, verifies the JWT signature and checks token type.
 */
async function decodeToken(token: string): Promise<string> {
  if (process.env.FUNCTIONS_EMULATOR === "true") {
    try {
      const payload = JSON.parse(
        Buffer.from(token.split(".")[1], "base64").toString()
      );
      return payload.uid || payload.user_id || payload.sub;
    } catch {
      throw new Error("Invalid token format");
    }
  }
  const payload = jwt.verify(token, JWT_SECRET) as {
    uid: string;
    type: string;
  };
  if (payload.type !== "access") {
    throw new Error("Not an access token");
  }
  return payload.uid;
}

/**
 * Middleware that verifies JWT access token from Authorization header.
 * Sets req.uid on success.
 */
export async function authMiddleware(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({ error: "Missing or invalid Authorization header" });
    return;
  }

  const token = authHeader.split("Bearer ")[1];

  try {
    req.uid = await decodeToken(token);
    next();
  } catch (error) {
    console.error("[Auth] Token verification failed:", error);
    res.status(401).json({ error: "Invalid or expired token" });
  }
}
