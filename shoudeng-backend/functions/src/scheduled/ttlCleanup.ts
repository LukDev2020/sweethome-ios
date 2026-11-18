import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { cleanupRateLimits } from "../middleware/rateLimit";
import { PUSH_SECRETS } from "../config/params";
import { cleanupExpiredEvidence } from "../services/storage";
import { applyBigQueryRetention, applyFirestoreRetention, processPendingDeletions } from "../services/accountData";

const db = admin.firestore();

/** One cleanup step; a failure is logged and the next step still runs */
async function step(name: string, run: () => Promise<void>): Promise<void> {
  try {
    await run();
  } catch (error) {
    console.error(`[TTL] ${name} failed:`, error);
  }
}

/** Firestore batches hold at most 500 writes */
async function inBatches(
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
  write: (batch: FirebaseFirestore.WriteBatch, doc: FirebaseFirestore.QueryDocumentSnapshot) => void
): Promise<void> {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    docs.slice(i, i + 400).forEach((doc) => write(batch, doc));
    await batch.commit();
  }
}

/** An SOS nobody closed is treated as over after this long */
export const STALE_SOS_HOURS = 24;

/**
 * Scheduled function: runs daily at 3 AM (Asia/Shanghai).
 * Cleans up expired data from BigQuery, respecting evidence holds.
 */
export const ttlCleanup = functions
  // Push secrets: queued account erasures reach the crew/push services
  .runWith({ timeoutSeconds: 540, secrets: PUSH_SECRETS })
  .pubsub
  .schedule("0 3 * * *")
  .timeZone("Asia/Shanghai")
  .onRun(async () => {
    console.log("[Scheduled] Running TTL cleanup");
    const now = () => admin.firestore.Timestamp.now();

    await step("retention", async () => {
      // Get active evidence holds
      const holdsSnapshot = await db
        .collection("evidence_holds")
        .where("expiresAt", ">", now())
        .get();
      const holds = holdsSnapshot.docs.map((doc) => ({
        protectedPersonId: doc.data().protectedPersonId,
        start: doc.data().timeWindowStart.toDate(),
        end: doc.data().timeWindowEnd.toDate(),
      }));
      console.log(`[TTL] Active evidence holds: ${holds.length}`);
      // Per-plan retention (free 7/30 days; paid plans longer — see PLANS.ttlDays)
      await applyBigQueryRetention(holds);
      await applyFirestoreRetention();
    });

    await step("queued erasures", async () => {
      const erased = await processPendingDeletions();
      console.log(`[TTL] Completed ${erased} queued account erasures`);
    });

    await step("evidence holds", async () => {
      const expiredHolds = await db.collection("evidence_holds").where("expiresAt", "<", now()).get();
      await inBatches(expiredHolds.docs, (b, d) => b.delete(d.ref));
      console.log(`[TTL] Removed expired evidence holds: ${expiredHolds.size}`);
    });

    await step("alipay round trips", async () => {
      // Sign in with Alipay round trips nobody finished (10 minutes each)
      const staleAlipay = await db.collection("alipay_logins").where("expiresAt", "<", now()).get();
      await inBatches(staleAlipay.docs, (b, d) => b.delete(d.ref));
    });

    await step("invites", async () => {
      const expiredInvites = await db
        .collection("invites")
        .where("status", "==", "pending")
        .where("expiresAt", "<", now())
        .get();
      await inBatches(expiredInvites.docs, (b, d) => b.update(d.ref, { status: "expired" }));
      console.log(`[TTL] Expired ${expiredInvites.size} invites`);
    });

    await step("share links", async () => {
      const expiredShares = await db.collection("evidence_shares").where("expiresAt", "<", now()).get();
      await inBatches(expiredShares.docs, (b, d) => b.delete(d.ref));
      console.log(`[TTL] Removed ${expiredShares.size} expired share links`);
    });

    await step("stale SOS", async () => {
      // An SOS still open a day later (nobody pressed "she's safe") would show as
      // active to the family forever; close it as timed out
      const cutoff = admin.firestore.Timestamp.fromMillis(Date.now() - STALE_SOS_HOURS * 60 * 60 * 1000);
      const stale = await db
        .collection("sos_events")
        .where("resolvedAt", "==", null)
        .where("triggeredAt", "<", cutoff)
        .limit(400)
        .get();
      const at = now();
      await inBatches(stale.docs, (b, d) => b.update(d.ref, {
        resolvedAt: at, resolvedBy: "system", resolution: "timeout",
        escalationNextStep: null, escalationNextAt: null, escalationLeaseUntil: null,
      }));
      console.log(`[TTL] Closed ${stale.size} SOS open for over ${STALE_SOS_HOURS} h`);
    });

    await step("rate limits", async () => {
      const rateLimitsCleaned = await cleanupRateLimits();
      console.log(`[TTL] Cleaned ${rateLimitsCleaned} rate limit entries`);
    });

    await step("evidence files", async () => {
      // Expired evidence files in Cloud Storage (older than 90 days)
      const evidenceCleaned = await cleanupExpiredEvidence(90);
      console.log(`[TTL] Cleaned ${evidenceCleaned} expired evidence files`);
    });
  });
