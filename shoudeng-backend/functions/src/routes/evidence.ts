import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { requireFeature } from "../middleware/subscription";
import {
  generateEvidenceBundle,
  generateGPX,
  createShareToken,
} from "../services/evidence";
import { queryLocations, queryHeartbeats } from "../services/bigquery";
import { uploadEvidenceBundle, uploadGpxTrack } from "../services/storage";
import { publicApiBaseUrl } from "../services/twilio";
import { toIso } from "../services/time";
import { createRateLimiter, RATE_LIMITS } from "../middleware/rateLimit";

const router = Router();
const db = admin.firestore();

/**
 * POST /v1/evidence/generate
 * Generate an evidence bundle (PDF data, JSON, or GPX) for a protected person.
 * Requires authentication + export_pdf feature (single+ plan).
 */
router.post("/generate", authMiddleware, requireFeature("export_pdf"), async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { protectedPersonId, timeWindowStart, timeWindowEnd, format, reason } =
    req.body;

  if (!protectedPersonId || !timeWindowStart || !timeWindowEnd) {
    res.status(400).json({
      error:
        "protectedPersonId, timeWindowStart, and timeWindowEnd are required",
    });
    return;
  }

  try {
    // Verify requester is a guardian of this person
    const linkId = `${uid}_${protectedPersonId}`;
    const linkDoc = await db.collection("guardian_links").doc(linkId).get();
    if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
      // Also check if the user is the protected person themselves
      if (uid !== protectedPersonId) {
        res.status(403).json({ error: "Not authorized to access this data" });
        return;
      }
    }

    const bundle = await generateEvidenceBundle({
      protectedPersonId,
      timeWindowStart,
      timeWindowEnd,
      format: format || "json",
      requestedBy: uid,
      reason: reason || "user_request",
    });

    if (format === "gpx") {
      // Return GPX XML
      const userDoc = await db
        .collection("users")
        .doc(protectedPersonId)
        .get();
      const personName = userDoc.exists
        ? userDoc.data()!.displayName
        : "Unknown";
      const gpx = generateGPX(bundle.locations, personName);

      res.set("Content-Type", "application/gpx+xml");
      res.set(
        "Content-Disposition",
        `attachment; filename="${personName}_track.gpx"`
      );
      res.send(gpx);
      return;
    }

    // Upload to Cloud Storage and return download URL + inline data
    try {
      const downloadUrl = await uploadEvidenceBundle(
        bundle.bundleId,
        bundle as unknown as Record<string, unknown>,
        "json"
      );
      res.json({ ...bundle, downloadUrl });
    } catch {
      // If storage upload fails, still return the data inline
      res.json(bundle);
    }
  } catch (error) {
    console.error("[Evidence] generate error:", error);
    res.status(500).json({ error: "Failed to generate evidence bundle" });
  }
});

export const MAX_SHARE_HOURS = 48; // privacy policy: emergency links live at most 48 h

/**
 * POST /v1/evidence/share
 * Create a time-limited share link for emergency data.
 * Only the person themselves, or an active guardian allowed to see their
 * location, may create one; the link lives at most 48 hours.
 */
router.post("/share", authMiddleware, async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { protectedPersonId, expiresInHours } = req.body;

  if (typeof protectedPersonId !== "string" || !protectedPersonId) {
    res.status(400).json({ error: "protectedPersonId is required" });
    return;
  }
  const hours = expiresInHours === undefined ? MAX_SHARE_HOURS : Number(expiresInHours);
  if (!Number.isFinite(hours) || hours <= 0 || hours > MAX_SHARE_HOURS) {
    res.status(400).json({ error: `expiresInHours must be between 1 and ${MAX_SHARE_HOURS}` });
    return;
  }

  try {
    if (uid !== protectedPersonId) {
      const link = await db.collection("guardian_links").doc(`${uid}_${protectedPersonId}`).get();
      const data = link.data();
      if (!link.exists || data?.status !== "active" || data?.permissions?.canSeeLocation === false) {
        res.status(403).json({ error: "Not authorized to share this person's location" });
        return;
      }
    }

    const token = await createShareToken({
      protectedPersonId,
      createdBy: uid,
      expiresInHours: hours,
    });

    const shareUrl = `${publicApiBaseUrl()}/v1/evidence/share/${token}`;
    res.json({ token, shareUrl, expiresInHours: hours });
  } catch (error) {
    console.error("[Evidence] share creation error:", error);
    res.status(500).json({ error: "Failed to create share link" });
  }
});

function esc(s: unknown): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

/**
 * GET /v1/evidence/share/:token
 * Public (token = capability). Returns the last 24 h of location / battery and
 * the active SOS. Browsers (the SMS link) get a small HTML page; API clients JSON.
 */
router.get("/share/:token", createRateLimiter(RATE_LIMITS.publicShare, (req) => `ip:${req.ip}`), async (req: Request, res: Response) => {
  const { token } = req.params;
  const wantsHtml = req.accepts(["json", "html"]) === "html";

  try {
    const shareDoc = await db.collection("evidence_shares").doc(token).get();

    if (!shareDoc.exists) {
      res.status(404).json({ error: "Share link not found" });
      return;
    }

    const shareData = shareDoc.data()!;

    // Check expiry
    if (!shareData.expiresAt?.toDate || shareData.expiresAt.toDate() < new Date()) {
      res.status(410).json({ error: "Share link has expired" });
      return;
    }

    // Check access count
    if (shareData.accessCount >= shareData.maxAccess) {
      res.status(410).json({ error: "Share link access limit reached" });
      return;
    }

    // Increment access count
    await shareDoc.ref.update({
      accessCount: admin.firestore.FieldValue.increment(1),
    });

    const protectedPersonId = shareData.protectedPersonId;
    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    const [locations, heartbeats, userDoc, telemetryDoc, sosSnapshot] = await Promise.all([
      queryLocations(protectedPersonId, oneDayAgo.toISOString(), now.toISOString()).catch(() => []),
      queryHeartbeats(protectedPersonId, oneDayAgo.toISOString(), now.toISOString()).catch(() => []),
      db.collection("users").doc(protectedPersonId).get(),
      db.collection("user_telemetry").doc(protectedPersonId).get(),
      db.collection("sos_events")
        .where("protectedPersonId", "==", protectedPersonId)
        .where("resolvedAt", "==", null)
        .get(),
    ]);
    const userName = userDoc.exists ? userDoc.data()!.displayName : "Unknown";
    const tel = telemetryDoc.exists ? telemetryDoc.data()! : {};

    // Only what an emergency helper needs — never internal logs, call ids or tokens
    const activeSOS = sosSnapshot.docs.map((d) => {
      const x = d.data();
      return {
        triggeredAt: toIso(x.triggeredAt),
        latitude: x.latitude ?? null,
        longitude: x.longitude ?? null,
        batteryLevel: x.batteryLevel ?? null,
        acknowledged: !!x.acknowledgedBy,
      };
    });
    const latest = {
      latitude: typeof tel.latitude === "number" ? tel.latitude : activeSOS[0]?.latitude ?? null,
      longitude: typeof tel.longitude === "number" ? tel.longitude : activeSOS[0]?.longitude ?? null,
      at: toIso(tel.locationTimestamp) ?? activeSOS[0]?.triggeredAt ?? null,
      batteryLevel: typeof tel.batteryLevel === "number" ? tel.batteryLevel : activeSOS[0]?.batteryLevel ?? null,
    };

    if (wantsHtml) {
      const map = latest.latitude != null && latest.longitude != null
        ? `https://maps.apple.com/?ll=${latest.latitude},${latest.longitude}&q=${encodeURIComponent(String(userName))}`
        : null;
      res.set("Content-Type", "text/html; charset=utf-8");
      res.set("Cache-Control", "no-store");
      res.set("X-Robots-Tag", "noindex");
      res.send(`<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(userName)} — Lantern Care</title>
<style>body{font:16px -apple-system,system-ui,sans-serif;margin:24px;color:#12203a}h1{font-size:22px;color:#c4453c}a.btn{display:block;margin:16px 0;padding:14px;border-radius:10px;background:#c4453c;color:#fff;text-align:center;text-decoration:none}small{color:#667}</style></head>
<body><h1>${esc(userName)}${activeSOS.length ? " · SOS" : ""}</h1>
${activeSOS.length ? `<p>SOS since ${esc(activeSOS[0].triggeredAt)}${activeSOS[0].acknowledged ? " — a family member is handling it" : ""}</p>` : ""}
<p>Last location: ${latest.at ? esc(latest.at) : "unknown"}${latest.batteryLevel != null ? ` · battery ${Math.round(Number(latest.batteryLevel) * 100)}%` : ""}</p>
${map ? `<a class="btn" href="${esc(map)}">Open location in Maps</a>` : ""}
<p>If someone is in danger, call your local emergency number.</p>
<small>Shared by Lantern Care for emergencies. Link expires ${esc(toIso(shareData.expiresAt))}.</small>
</body></html>`);
      return;
    }

    res.json({
      personName: userName,
      latest,
      locations,
      heartbeats: heartbeats.map((h) => ({
        timestamp: h.timestamp,
        batteryLevel: h.battery_level,
        batteryState: h.battery_state,
      })),
      activeSOS,
      generatedAt: now.toISOString(),
      expiresAt: toIso(shareData.expiresAt),
      disclaimer:
        "此数据由守灯安全应用自动生成，仅供紧急参考。数据完整性可通过 SHA-256 哈希验证。",
    });
  } catch (error) {
    console.error("[Evidence] share access error:", error);
    res.status(500).json({ error: "Failed to retrieve shared data" });
  }
});

export default router;
