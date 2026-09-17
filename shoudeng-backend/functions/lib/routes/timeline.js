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
const express_1 = require("express");
const admin = __importStar(require("firebase-admin"));
const auth_1 = require("../middleware/auth");
const router = (0, express_1.Router)();
const db = admin.firestore();
router.use(auth_1.authMiddleware);
/**
 * GET /v1/timeline
 * Retrieve timeline entries for the authenticated user.
 * Supports pagination via ?limit=N&before=ISO_DATE
 */
router.get("/", async (req, res) => {
    const uid = req.uid;
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    const before = req.query.before;
    try {
        let query = db
            .collection("timeline_entries")
            .where("userId", "==", uid)
            .orderBy("timestamp", "desc")
            .limit(limit);
        if (before) {
            const beforeDate = new Date(before);
            if (!isNaN(beforeDate.getTime())) {
                query = query.where("timestamp", "<", admin.firestore.Timestamp.fromDate(beforeDate));
            }
        }
        const snapshot = await query.get();
        const entries = snapshot.docs.map((doc) => {
            const data = doc.data();
            return {
                id: doc.id,
                type: data.type,
                description: data.description,
                detail: data.detail || null,
                timestamp: data.timestamp?.toDate?.()?.toISOString() ||
                    new Date().toISOString(),
            };
        });
        res.json({ entries });
    }
    catch (error) {
        console.error("[Timeline] fetch error:", error);
        res.status(500).json({ error: "Failed to fetch timeline" });
    }
});
exports.default = router;
//# sourceMappingURL=timeline.js.map