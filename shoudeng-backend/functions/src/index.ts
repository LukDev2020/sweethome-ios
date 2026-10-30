import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

// Initialize Firebase Admin SDK (before any module calls admin.firestore())
admin.initializeApp();

// eslint-disable-next-line @typescript-eslint/no-var-requires
const { app } = require("./app");

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
export { checkSilentAlarms } from "./scheduled/silentAlarmCheck";
export { advanceEscalations } from "./scheduled/escalationCheck";
