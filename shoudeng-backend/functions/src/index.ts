import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import express from "express";
import cors from "cors";

// Initialize Firebase Admin SDK
admin.initializeApp();

// --- Express App ---
const app = express();
// iOS-only app: no web origins needed in production.
// Allow all origins only in emulator for local testing.
app.use(
  cors({
    origin: process.env.FUNCTIONS_EMULATOR === "true" ? true : false,
  })
);
app.use(express.json());

// --- Route Imports ---
import authRoutes from "./routes/auth";
import userRoutes from "./routes/user";
import inviteRoutes from "./routes/invite";
import guardianRoutes from "./routes/guardian";
import protectedRoutes from "./routes/protected";
import telemetryRoutes from "./routes/telemetry";
import sosRoutes from "./routes/sos";
import deviceRoutes from "./routes/device";
import safezoneRoutes from "./routes/safezone";
import dutyRoutes from "./routes/duty";
import evidenceRoutes from "./routes/evidence";
import familyRoutes from "./routes/family";
import paymentRoutes from "./routes/payment";
import webhookRoutes from "./routes/webhooks";
import timelineRoutes from "./routes/timeline";
import homeTimerRoutes from "./routes/homeTimer";
import arrivalRoutes from "./routes/arrival";
import itineraryRoutes from "./routes/itinerary";
import medicalCardRoutes from "./routes/medicalCard";
import emergencyTextRoutes from "./routes/emergencyText";
import organizationRoutes from "./routes/organization";
import insuranceRoutes from "./routes/insurance";
import consulateRoutes from "./routes/consulate";
import { createRateLimiter, RATE_LIMITS } from "./middleware/rateLimit";

// --- Mount Routes ---
// Phase 1: Auth & Users
app.use("/v1/auth", createRateLimiter(RATE_LIMITS.auth, (req) => req.ip || "unknown"), authRoutes);
app.use("/v1/user", userRoutes);

// Phase 2: Relationships & Core Data
app.use("/v1/invite", inviteRoutes);
app.use("/v1/guardian", guardianRoutes);
app.use("/v1/protected", protectedRoutes);
app.use("/v1/safe-zone", safezoneRoutes);
app.use("/v1/safe-zones", safezoneRoutes);
app.use("/v1/duty-schedule", dutyRoutes);

// Phase 2.5: Family Feed
app.use("/v1/family", familyRoutes);

// Phase 3: Telemetry
app.use("/v1", telemetryRoutes);

// Phase 4: SOS & Push
app.use("/v1/sos", sosRoutes);
app.use("/v1/device", deviceRoutes);

// Mount SOS routes at /v1 as well so /v1/voice-call resolves to sosRoutes' /voice-call handler
app.use("/v1", sosRoutes);

// Phase 5: Evidence & Analytics
app.use("/v1/evidence", evidenceRoutes);

// Phase 6: Payment & Webhooks
app.use("/v1/payment", paymentRoutes);
app.use("/v1/webhooks", webhookRoutes);

// Phase 5.5: Timeline
app.use("/v1/timeline", timelineRoutes);

// Diagnostics (crash reports) — uses user route prefix
app.use("/v1", userRoutes);

// Phase 7: Daily Use (Iteration 1)
app.use("/v1/home-timer", homeTimerRoutes);
app.use("/v1/arrival-report", arrivalRoutes);
app.use("/v1/itinerary", itineraryRoutes);

// Phase 8: Emergency Utility (Iteration 2)
app.use("/v1/medical-card", medicalCardRoutes);
app.use("/v1/emergency-text", emergencyTextRoutes);

// Phase 9: Organization / B2B (Iteration 3)
app.use("/v1/org", organizationRoutes);

// Phase 10: Insurance & Data (Iteration 4)
app.use("/v1/insurance", insuranceRoutes);

// Phase 11: Consulate Hotline (global embassy data + user selection)
app.use("/v1/consulate", consulateRoutes);

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
  } else if (Digits === "2") {
    // Replay message
    res.set("Content-Type", "text/xml");
    res.send(`<?xml version="1.0" encoding="UTF-8"?>
<Response>
  <Redirect>/v1/voice-replay</Redirect>
</Response>`);
  } else {
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
export const api = functions.https.onRequest(app);

// --- Trigger Exports ---
export { onSOSCreated } from "./triggers/onSOSCreated";

// --- Scheduled Exports ---
export { checkHeartbeatMissing } from "./scheduled/heartbeatCheck";
export { checkCheckinOverdue } from "./scheduled/checkinOverdue";
export { ttlCleanup } from "./scheduled/ttlCleanup";
export { computeIntegrityProof } from "./scheduled/integrityProof";
export { checkHomeTimerExpiry } from "./scheduled/homeTimerCheck";
