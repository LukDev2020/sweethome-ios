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
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.computeIntegrityProof = exports.ttlCleanup = exports.checkCheckinOverdue = exports.checkHeartbeatMissing = exports.onSOSCreated = exports.api = void 0;
const admin = __importStar(require("firebase-admin"));
const functions = __importStar(require("firebase-functions"));
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
// Initialize Firebase Admin SDK
admin.initializeApp();
// --- Express App ---
const app = (0, express_1.default)();
app.use((0, cors_1.default)({ origin: true }));
app.use(express_1.default.json());
// --- Route Imports ---
const auth_1 = __importDefault(require("./routes/auth"));
const user_1 = __importDefault(require("./routes/user"));
const invite_1 = __importDefault(require("./routes/invite"));
const guardian_1 = __importDefault(require("./routes/guardian"));
const protected_1 = __importDefault(require("./routes/protected"));
const telemetry_1 = __importDefault(require("./routes/telemetry"));
const sos_1 = __importDefault(require("./routes/sos"));
const device_1 = __importDefault(require("./routes/device"));
const safezone_1 = __importDefault(require("./routes/safezone"));
const duty_1 = __importDefault(require("./routes/duty"));
const evidence_1 = __importDefault(require("./routes/evidence"));
const payment_1 = __importDefault(require("./routes/payment"));
const webhooks_1 = __importDefault(require("./routes/webhooks"));
const rateLimit_1 = require("./middleware/rateLimit");
// --- Mount Routes ---
// Phase 1: Auth & Users
app.use("/v1/auth", (0, rateLimit_1.createRateLimiter)(rateLimit_1.RATE_LIMITS.auth, (req) => req.ip || "unknown"), auth_1.default);
app.use("/v1/user", user_1.default);
// Phase 2: Relationships & Core Data
app.use("/v1/invite", invite_1.default);
app.use("/v1/guardian", guardian_1.default);
app.use("/v1/protected", protected_1.default);
app.use("/v1/safe-zone", safezone_1.default);
app.use("/v1/safe-zones", safezone_1.default);
app.use("/v1/duty-schedule", duty_1.default);
// Phase 3: Telemetry
app.use("/v1", telemetry_1.default);
// Phase 4: SOS & Push
app.use("/v1/sos", sos_1.default);
app.use("/v1/device", device_1.default);
// Mount SOS routes at /v1 as well so /v1/voice-call resolves to sosRoutes' /voice-call handler
app.use("/v1", sos_1.default);
// Phase 5: Evidence & Analytics
app.use("/v1/evidence", evidence_1.default);
// Phase 6: Payment & Webhooks
app.use("/v1/payment", payment_1.default);
app.use("/v1/webhooks", webhooks_1.default);
// Diagnostics (crash reports) — uses user route prefix
app.use("/v1", user_1.default);
// --- Voice callback for Twilio ---
app.post("/v1/voice-callback", async (req, res) => {
    const { Digits, CallSid } = req.body;
    if (Digits === "1") {
        // Guardian pressed 1 — acknowledged
        console.log(`[VoiceCallback] Guardian acknowledged via call ${CallSid}`);
        res.set("Content-Type", "text/xml");
        res.send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="zh-CN" voice="alice">
    已收到。请打开守灯应用查看详情并确认接手。
  </Say>
</Response>`);
    }
    else if (Digits === "2") {
        // Replay message
        res.set("Content-Type", "text/xml");
        res.send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Redirect>/v1/voice-replay</Redirect>
</Response>`);
    }
    else {
        res.set("Content-Type", "text/xml");
        res.send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Say language="zh-CN" voice="alice">无效按键。</Say>
</Response>`);
    }
});
// --- Health check ---
app.get("/health", (_req, res) => {
    res.json({
        status: "ok",
        service: "shoudeng-backend",
        timestamp: new Date().toISOString(),
    });
});
// --- Export HTTP function ---
exports.api = functions.https.onRequest(app);
// --- Trigger Exports ---
var onSOSCreated_1 = require("./triggers/onSOSCreated");
Object.defineProperty(exports, "onSOSCreated", { enumerable: true, get: function () { return onSOSCreated_1.onSOSCreated; } });
// --- Scheduled Exports ---
var heartbeatCheck_1 = require("./scheduled/heartbeatCheck");
Object.defineProperty(exports, "checkHeartbeatMissing", { enumerable: true, get: function () { return heartbeatCheck_1.checkHeartbeatMissing; } });
var checkinOverdue_1 = require("./scheduled/checkinOverdue");
Object.defineProperty(exports, "checkCheckinOverdue", { enumerable: true, get: function () { return checkinOverdue_1.checkCheckinOverdue; } });
var ttlCleanup_1 = require("./scheduled/ttlCleanup");
Object.defineProperty(exports, "ttlCleanup", { enumerable: true, get: function () { return ttlCleanup_1.ttlCleanup; } });
var integrityProof_1 = require("./scheduled/integrityProof");
Object.defineProperty(exports, "computeIntegrityProof", { enumerable: true, get: function () { return integrityProof_1.computeIntegrityProof; } });
//# sourceMappingURL=index.js.map