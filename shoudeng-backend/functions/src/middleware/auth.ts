import { Request, Response, NextFunction } from "express";
import * as admin from "firebase-admin";

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
 * In emulator mode, decodes JWT payload directly (accepts custom tokens
 * and cross-project ID tokens). In production, uses full verification.
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
  const decoded = await admin.auth().verifyIdToken(token);
  return decoded.uid;
}

/**
 * Middleware that verifies Firebase Auth ID token from Authorization header.
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
