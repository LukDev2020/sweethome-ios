import express from "express";
import cors from "cors";
import { UPLOAD_JSON_LIMIT } from "./routes/family";

// The Express API, separate from index.ts so tests can mount the full app
// (exact production middleware order) without the Cloud Functions wrappers.

// --- Express App ---
export const app = express();
// iOS-only app: no web origins needed in production.
// Allow all origins only in emulator for local testing.
app.use(
  cors({
    origin: process.env.FUNCTIONS_EMULATOR === "true" ? true : false,
  })
);
// Family photo uploads are base64 JSON (~0.5–1 MB): give that one route a bigger
// limit. It parses first, so the global 100 kB parser below skips the body.
app.use("/v1/family/upload", express.json({ limit: UPLOAD_JSON_LIMIT }));
app.use("/v1/family/upload", (err: any, _req: express.Request, res: express.Response, next: express.NextFunction) => {
  if (err?.type === "entity.too.large") {
    res.status(413).json({ error: "File too large", code: "UPLOAD_TOO_LARGE" });
    return;
  }
  next(err);
});
app.use(express.json());
// Twilio posts application/x-www-form-urlencoded
app.use(express.urlencoded({ extended: false }));
// Behind Google's front end: trust exactly one proxy hop so req.ip is the
// client address Google saw (X-Forwarded-For entries further left are spoofable).
app.set("trust proxy", 1);

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
import voiceNoteRoutes from "./routes/voiceNote";
import silentAlarmRoutes from "./routes/silentAlarm";
import badgeRoutes from "./routes/badges";
import widgetRoutes from "./routes/widget";
import coverageRoutes from "./routes/coverage";
import tripRoutes from "./routes/trip";
import emergencyContactRoutes from "./routes/emergencyContacts";
import crewRoutes from "./routes/crew";
import voiceRoutes from "./routes/voice";
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

// Twilio voice callbacks (public, Twilio-signed)
app.use("/v1", voiceRoutes);

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

// Phase 12: SOS Voice Notes
app.use("/v1/sos", voiceNoteRoutes);

// Phase 13: Silent Alarm (沉默即报警)
app.use("/v1/silent-alarm", silentAlarmRoutes);

// Phase 14: Badge Counts, Widget Data, Coverage Info
app.use("/v1/badges", badgeRoutes);
app.use("/v1/widget", widgetRoutes);
app.use("/v1/coverage", coverageRoutes);

// Phase 15: Trip Recording & History
app.use("/v1/trip", tripRoutes);

// Personal emergency contacts (SMS fallback when there are no guardians)
app.use("/v1/emergency-contacts", emergencyContactRoutes);
// Rider crews: mutual SOS alerts, shifts, caution spots
app.use("/v1/crew", crewRoutes);

// --- Health check ---
app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    service: "shoudeng-backend",
    timestamp: new Date().toISOString(),
  });
});

