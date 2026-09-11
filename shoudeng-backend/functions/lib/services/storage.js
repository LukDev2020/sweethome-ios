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
Object.defineProperty(exports, "__esModule", { value: true });
exports.uploadEvidenceBundle = uploadEvidenceBundle;
exports.uploadEvidencePdf = uploadEvidencePdf;
exports.uploadGpxTrack = uploadGpxTrack;
exports.cleanupExpiredEvidence = cleanupExpiredEvidence;
const admin = __importStar(require("firebase-admin"));
const storage = admin.storage();
const BUCKET_NAME = "shoudeng-evidence"; // Configure via firebase config
/**
 * Upload evidence bundle JSON to Cloud Storage.
 * Returns a signed download URL valid for 7 days.
 */
async function uploadEvidenceBundle(bundleId, data, format) {
    const bucket = storage.bucket();
    const ext = format === "gpx" ? "gpx" : "json";
    const contentType = format === "gpx" ? "application/gpx+xml" : "application/json";
    const filePath = `evidence/${bundleId}.${ext}`;
    const file = bucket.file(filePath);
    const content = format === "json" ? JSON.stringify(data, null, 2) : String(data);
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
async function uploadEvidencePdf(bundleId, pdfBuffer, personName) {
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
async function uploadGpxTrack(bundleId, gpxContent, personName) {
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
async function cleanupExpiredEvidence(olderThanDays) {
    const bucket = storage.bucket();
    const cutoff = new Date(Date.now() - olderThanDays * 24 * 60 * 60 * 1000);
    const [files] = await bucket.getFiles({ prefix: "evidence/" });
    let deleted = 0;
    for (const file of files) {
        const metadata = await file.getMetadata();
        const created = new Date(metadata[0].timeCreated);
        if (created < cutoff) {
            await file.delete();
            deleted++;
        }
    }
    return deleted;
}
//# sourceMappingURL=storage.js.map