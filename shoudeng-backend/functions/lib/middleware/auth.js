"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.authMiddleware = authMiddleware;
const admin = __importStar(require("firebase-admin"));
/**
 * Decode a token to extract uid.
 * In emulator mode, decodes JWT payload directly (accepts custom tokens
 * and cross-project ID tokens). In production, uses full verification.
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
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded.uid;
}
/**
 * Middleware that verifies Firebase Auth ID token from Authorization header.
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