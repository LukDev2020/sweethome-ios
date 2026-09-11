import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";

const storage = admin.storage();
const BUCKET_NAME = "shoudeng-evidence"; // Configure via firebase config

/**
 * Upload evidence bundle JSON to Cloud Storage.
 * Returns a signed download URL valid for 7 days.
 */
export async function uploadEvidenceBundle(
  bundleId: string,
  data: Record<string, unknown>,
  format: "json" | "gpx"
): Promise<string> {
  const bucket = storage.bucket();
  const ext = format === "gpx" ? "gpx" : "json";
  const contentType = format === "gpx" ? "application/gpx+xml" : "application/json";
  const filePath = `evidence/${bundleId}.${ext}`;

  const file = bucket.file(filePath);
  const content =
    format === "json" ? JSON.stringify(data, null, 2) : String(data);

  await file.save(content, {
    contentType,
    metadata: {
      metadata: {
        bundleId,
        generatedAt: new Date().toISOString(),
      },
    },
  });

  // Generate signed URL valid for 7 days
  const [url] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
  });

  return url;
}

/**
 * Upload a PDF evidence report to Cloud Storage.
 * Takes raw PDF buffer and returns a signed download URL.
 */
export async function uploadEvidencePdf(
  bundleId: string,
  pdfBuffer: Buffer,
  personName: string
): Promise<string> {
  const bucket = storage.bucket();
  const filePath = `evidence/${bundleId}_${personName}.pdf`;

  const file = bucket.file(filePath);

  await file.save(pdfBuffer, {
    contentType: "application/pdf",
    metadata: {
      metadata: {
        bundleId,
        personName,
        generatedAt: new Date().toISOString(),
      },
    },
  });

  const [url] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
  });

  return url;
}

/**
 * Upload a GPX track file to Cloud Storage.
 */
export async function uploadGpxTrack(
  bundleId: string,
  gpxContent: string,
  personName: string
): Promise<string> {
  const bucket = storage.bucket();
  const filePath = `evidence/${bundleId}_${personName}_track.gpx`;

  const file = bucket.file(filePath);

  await file.save(gpxContent, {
    contentType: "application/gpx+xml",
    metadata: {
      metadata: {
        bundleId,
        personName,
        generatedAt: new Date().toISOString(),
      },
    },
  });

  const [url] = await file.getSignedUrl({
    action: "read",
    expires: Date.now() + 7 * 24 * 60 * 60 * 1000,
  });

  return url;
}

/**
 * Delete expired evidence files from Cloud Storage.
 * Called by TTL cleanup scheduled function.
 */
export async function cleanupExpiredEvidence(olderThanDays: number): Promise<number> {
  const bucket = storage.bucket();
  const cutoff = new Date(Date.now() - olderThanDays * 24 * 60 * 60 * 1000);

  const [files] = await bucket.getFiles({ prefix: "evidence/" });
  let deleted = 0;

  for (const file of files) {
    const metadata = await file.getMetadata();
    const created = new Date(metadata[0].timeCreated as string);
    if (created < cutoff) {
      await file.delete();
      deleted++;
    }
  }

  return deleted;
}
