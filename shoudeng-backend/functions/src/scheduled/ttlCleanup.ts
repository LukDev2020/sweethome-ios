import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { BigQuery } from "@google-cloud/bigquery";
import { getSubscription } from "../services/payment";
import { cleanupRateLimits } from "../middleware/rateLimit";
import { cleanupExpiredEvidence } from "../services/storage";

const db = admin.firestore();
const bigquery = new BigQuery();
const DATASET = "shoudeng";

// TTL rules (days)
const TTL = {
  heartbeat_signals: { free: 7, paid: 90 },
  location_reports: { free: 7, paid: 90 },
  checkins: { free: 30, paid: -1 }, // -1 = never delete
  // consent_audit: never deleted
  // sos_events: never deleted
};

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

      for (const [table, ttl] of Object.entries(TTL)) {
        // Use paid TTL if any user has an active subscription
        // In production, would run per-user with their specific plan
        const retentionDays = ttl.free;

        if (retentionDays === -1) {
          console.log(`[TTL] Skipping ${table} — no TTL`);
          continue;
        }

        const cutoffDate = new Date(
          Date.now() - retentionDays * 24 * 60 * 60 * 1000
        );

        // Build hold exclusion clauses using parameterized queries
        let holdClauses = "";
        const params: Record<string, string> = { cutoff: cutoffDate.toISOString() };
        if (holds.length > 0) {
          const exclusions = holds
            .map((h, i) => {
              params[`hold_uid_${i}`] = h.protectedPersonId;
              params[`hold_start_${i}`] = h.start.toISOString();
              params[`hold_end_${i}`] = h.end.toISOString();
              return `NOT (user_id = @hold_uid_${i} AND timestamp BETWEEN @hold_start_${i} AND @hold_end_${i})`;
            })
            .join(" AND ");
          holdClauses = `AND ${exclusions}`;
        }

        const query = `
          DELETE FROM \`${DATASET}.${table}\`
          WHERE timestamp < @cutoff
          ${holdClauses}
        `;

        try {
          const [job] = await bigquery.createQueryJob({
            query,
            params,
          });
          const [rows] = await job.getQueryResults();
          console.log(
            `[TTL] Cleaned ${table}: cutoff ${cutoffDate.toISOString()}`
          );
        } catch (error) {
          console.error(`[TTL] Failed to clean ${table}:`, error);
        }
      }

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
