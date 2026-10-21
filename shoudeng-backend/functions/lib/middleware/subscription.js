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
exports.requireFeature = requireFeature;
exports.requirePlanCapacity = requirePlanCapacity;
const payment_1 = require("../services/payment");
/**
 * Middleware factory that gates a route behind a subscription feature.
 * Returns 403 if the user's plan doesn't include the required feature.
 *
 * Usage: router.post("/generate", authMiddleware, requireFeature("export_pdf"), handler)
 */
function requireFeature(feature) {
    return async (req, res, next) => {
        const uid = req.uid;
        if (!uid) {
            res.status(401).json({ error: "Authentication required" });
            return;
        }
        try {
            const sub = await (0, payment_1.getSubscription)(uid);
            if (sub.features.includes(feature)) {
                next();
            }
            else {
                res.status(403).json({
                    error: "Feature not available on your current plan",
                    feature,
                    currentPlan: sub.planId,
                    upgrade: true,
                });
            }
        }
        catch (error) {
            console.error("[Subscription] Feature check failed:", error);
            res.status(500).json({ error: "Failed to check subscription" });
        }
    };
}
/**
 * Middleware factory that gates invite acceptance behind plan limits.
 * Checks guardian count OR protected person count based on the acceptor's role.
 */
function requirePlanCapacity(role) {
    return async (req, res, next) => {
        const uid = req.uid;
        if (!uid) {
            res.status(401).json({ error: "Authentication required" });
            return;
        }
        try {
            const sub = await (0, payment_1.getSubscription)(uid);
            const { PLANS } = await Promise.resolve().then(() => __importStar(require("../services/payment")));
            const plan = PLANS[sub.planId] || PLANS.free;
            // For guardians: check maxProtected (how many people they can watch)
            // For protected: check maxGuardians (how many guardians can watch them)
            // The limit applies to the GUARDIAN's subscription since they are the paying user
            if (role === "guardian") {
                const maxProtected = plan.maxProtected ?? 1;
                if (maxProtected >= 0) {
                    const admin = await Promise.resolve().then(() => __importStar(require("firebase-admin")));
                    const links = await admin.default
                        .firestore()
                        .collection("guardian_links")
                        .where("guardianId", "==", uid)
                        .where("status", "==", "active")
                        .get();
                    if (links.size >= maxProtected) {
                        res.status(403).json({
                            error: "Plan limit reached",
                            detail: `Your plan allows up to ${maxProtected} protected person(s)`,
                            currentCount: links.size,
                            maxAllowed: maxProtected,
                            currentPlan: sub.planId,
                            upgrade: true,
                        });
                        return;
                    }
                }
            }
            next();
        }
        catch (error) {
            console.error("[Subscription] Capacity check failed:", error);
            res.status(500).json({ error: "Failed to check plan capacity" });
        }
    };
}
//# sourceMappingURL=subscription.js.map