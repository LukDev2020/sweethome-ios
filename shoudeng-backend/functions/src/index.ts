import * as admin from "firebase-admin";
import * as functions from "firebase-functions";
import { API_SECRETS } from "./config/params";

// Initialize Firebase Admin SDK (before any module calls admin.firestore())
admin.initializeApp();

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { app } = require("./app");

// --- Export HTTP function ---
// Secrets: Twilio (SOS SMS/voice, webhook signatures) + Google Maps (geocoding).
// Every function that can reach services/sms or services/twilio must bind TWILIO_SECRETS.
export const api = functions.runWith({ secrets: API_SECRETS }).https.onRequest(app);

// --- Trigger Exports ---
export { onSOSCreated } from "./triggers/onSOSCreated";

// --- Scheduled Exports ---
export { checkHeartbeatMissing } from "./scheduled/heartbeatCheck";
export { checkCheckinOverdue } from "./scheduled/checkinOverdue";
export { ttlCleanup } from "./scheduled/ttlCleanup";
export { computeIntegrityProof } from "./scheduled/integrityProof";
export { checkHomeTimerExpiry } from "./scheduled/homeTimerCheck";
export { checkSilentAlarms } from "./scheduled/silentAlarmCheck";
export { advanceEscalations } from "./scheduled/escalationCheck";
