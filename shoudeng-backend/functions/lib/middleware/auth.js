"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authMiddleware = authMiddleware;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
function getJwtSecret() {
    const secret = process.env.JWT_SECRET;
    if (secret)
        return secret;
    const isDev = process.env.FUNCTIONS_EMULATOR === "true" || !!process.env.JEST_WORKER_ID;
    if (!isDev) {
        throw new Error("JWT_SECRET environment variable is required in production");
    }
    return "shoudeng-dev-jwt-secret-do-not-use-in-prod";
}
/**
 * Decode a token to extract uid.
 * In emulator mode, decodes JWT payload directly (accepts any JWT shape).
 * In production, verifies the JWT signature and checks token type.
 */
async function decodeToken(token) {
    if (process.env.FUNCTIONS_EMULATOR === "true") {
        try {
            const payload = JSON.parse(Buffer.from(token.split(".")[1], "base64").toString());
            return payload.uid || payload.user_id || payload.sub;
        }
        catch {
            throw new Error("Invalid token format");
        }
    }
    const payload = jsonwebtoken_1.default.verify(token, getJwtSecret());
    if (payload.type !== "access") {
        throw new Error("Not an access token");
    }
    return payload.uid;
}
/**
 * Middleware that verifies JWT access token from Authorization header.
 * Sets req.uid on success.
 */
async function authMiddleware(req, res, next) {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
        res.status(401).json({ error: "Missing or invalid Authorization header" });
        return;
    }
    const token = authHeader.split("Bearer ")[1];
    try {
        req.uid = await decodeToken(token);
        next();
    }
    catch (error) {
        console.error("[Auth] Token verification failed:", error);
        res.status(401).json({ error: "Invalid or expired token" });
    }
}
//# sourceMappingURL=auth.js.map