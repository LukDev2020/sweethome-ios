import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import { computeDailyMerkleRoot } from "../services/bigquery";

const db = admin.firestore();

/**
 * Scheduled function: runs daily at 4 AM UTC.
 * Computes Merkle roots for the previous day's BigQuery data.
 * Stores in Firestore integrity_proofs collection for tamper detection.
 */
export const computeIntegrityProof = functions.pubsub
  .schedule("0 4 * * *")
  .timeZone("Asia/Shanghai")
  .onRun(async () => {
    // Compute for yesterday
    const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000);
    const dateStr = yesterday.toISOString().substring(0, 10);

    console.log(
      `[Scheduled] Computing integrity proof for ${dateStr}`
    );

    try {
      // Compute Merkle roots for each table
      const [heartbeatResult, locationResult] = await Promise.all([
        computeDailyMerkleRoot("heartbeat_signals", dateStr),
        computeDailyMerkleRoot("location_reports", dateStr),
      ]);

      const totalRecords =
        heartbeatResult.count + locationResult.count;

      // Store in Firestore
      await db
        .collection("integrity_proofs")
        .doc(dateStr)
        .set({
          date: dateStr,
          heartbeatMerkleRoot: heartbeatResult.root,
          locationMerkleRoot: locationResult.root,
          recordCount: totalRecords,
          computedAt: admin.firestore.Timestamp.now(),
        });

      console.log(
        `[Scheduled] Integrity proof for ${dateStr}: ` +
          `heartbeats=${heartbeatResult.count} (${heartbeatResult.root.substring(0, 12)}...), ` +
          `locations=${locationResult.count} (${locationResult.root.substring(0, 12)}...)`
      );
    } catch (error) {
      console.error(
        `[Scheduled] Integrity proof computation failed for ${dateStr}:`,
        error
      );
    }
  });
