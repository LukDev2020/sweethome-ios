import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { cleanupRateLimits } from "../middleware/rateLimit";
import { cleanupExpiredEvidence } from "../services/storage";
import { applyBigQueryRetention, applyFirestoreRetention, processPendingDeletions } from "../services/accountData";

const db = admin.firestore();

/**
 * Scheduled function: runs daily at 3 AM UTC.
 * Cleans up expired data from BigQuery, respecting evidence holds.
 */
export const ttlCleanup = functions.pubsub
  .schedule("0 3 * * *")
  .timeZone("Asia/Shanghai")
  .onRun(async () => {
    console.log("[Scheduled] Running TTL cleanup");

    try {
      // Get active evidence holds
      const holdsSnapshot = await db
        .collection("evidence_holds")
        .where("expiresAt", ">", admin.firestore.Timestamp.now())
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
      const erased = await processPendingDeletions();
      console.log(`[TTL] Completed ${erased} queued account erasures`);

      // Clean up expired evidence holds
      const expiredHolds = await db
        .collection("evidence_holds")
        .where("expiresAt", "<", admin.firestore.Timestamp.now())
        .get();

      for (const doc of expiredHolds.docs) {
        await doc.ref.delete();
        console.log(`[TTL] Removed expired evidence hold ${doc.id}`);
      }

      // Clean up expired invite codes
      const expiredInvites = await db
        .collection("invites")
        .where("status", "==", "pending")
        .where("expiresAt", "<", admin.firestore.Timestamp.now())
        .get();

      const batch = db.batch();
      expiredInvites.docs.forEach((doc) => {
        batch.update(doc.ref, { status: "expired" });
      });
      await batch.commit();
      console.log(`[TTL] Expired ${expiredInvites.size} invites`);

      // Clean up expired evidence share links
      const expiredShares = await db
        .collection("evidence_shares")
        .where("expiresAt", "<", admin.firestore.Timestamp.now())
        .get();

      for (const doc of expiredShares.docs) {
        await doc.ref.delete();
      }
      console.log(`[TTL] Removed ${expiredShares.size} expired share links`);

      // Clean up rate limit documents
      const rateLimitsCleaned = await cleanupRateLimits();
      console.log(`[TTL] Cleaned ${rateLimitsCleaned} rate limit entries`);

      // Clean up expired evidence files from Cloud Storage (older than 90 days)
      try {
        const evidenceCleaned = await cleanupExpiredEvidence(90);
        console.log(`[TTL] Cleaned ${evidenceCleaned} expired evidence files`);
      } catch (storageError) {
        console.error("[TTL] Evidence cleanup error:", storageError);
      }
    } catch (error) {
      console.error("[Scheduled] TTL cleanup error:", error);
    }
  });
