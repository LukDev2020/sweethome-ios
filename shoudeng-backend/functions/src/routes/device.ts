import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { isSendableDeviceToken } from "../services/apns";
import { sendPushToUser } from "../services/push";
import { alertCopyFor, nameOr } from "../services/pushCopy";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/device/token
 * Register or update an APNs device token for push notifications.
 * Sent straight to Apple by services/apns.ts (not FCM: the app has no Firebase Messaging).
 */
router.post("/token", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { token, platform, environment } = req.body;

  if (!token || !platform) {
    res.status(400).json({ error: "token and platform are required" });
    return;
  }
  // Raw APNs device token (hex). It goes into the APNs request path, so nothing else.
  if (!isSendableDeviceToken(token)) {
    res.status(400).json({ error: "token must be an APNs device token" });
    return;
  }

  try {
    // Use token as document ID to avoid duplicates
    const tokenId = `${uid}_${platform}`;

    await db
      .collection("device_tokens")
      .doc(tokenId)
      .set({
        userId: uid,
        token,
        platform,
        // "development" = Xcode debug build (APNs sandbox); TestFlight / App Store = production.
        environment: environment === "development" || environment === "sandbox" ? "development" : "production",
        updatedAt: admin.firestore.Timestamp.now(),
      });

    res.json({ success: true });
  } catch (error) {
    console.error("[Device] token registration error:", error);
    res.status(500).json({ error: "Failed to register device token" });
  }
});

/**
 * POST /v1/device/ble-tag
 * Sync a paired/unpaired BLE tracker tag.
 */
router.post("/ble-tag", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tagId, name, type, action } = req.body;

  if (!tagId || !name || !type || !action) {
    res.status(400).json({ error: "tagId, name, type, and action are required" });
    return;
  }

  try {
    if (action === "paired") {
      await db.collection("users").doc(uid).collection("ble_tags").doc(tagId).set({
        name,
        type,
        pairedAt: admin.firestore.Timestamp.now(),
        isActive: true,
      });
    } else if (action === "unpaired") {
      await db.collection("users").doc(uid).collection("ble_tags").doc(tagId).delete();
    }
    res.json({ success: true });
  } catch (error) {
    console.error("[Device] BLE tag sync error:", error);
    res.status(500).json({ error: "Failed to sync BLE tag" });
  }
});

/**
 * POST /v1/device/ble-sightings
 * Batch upload BLE tag sighting locations.
 */
router.post("/ble-sightings", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { sightings } = req.body;

  if (!Array.isArray(sightings) || sightings.length === 0) {
    res.status(400).json({ error: "sightings array is required" });
    return;
  }

  try {
    const batch = db.batch();
    for (const s of sightings.slice(0, 50)) {
      const ref = db.collection("users").doc(uid).collection("ble_sightings").doc();
      batch.set(ref, {
        tagId: s.tagId,
        latitude: s.latitude,
        longitude: s.longitude,
        rssi: s.rssi,
        timestamp: s.timestamp ? new Date(s.timestamp) : admin.firestore.Timestamp.now(),
      });
    }
    await batch.commit();
    res.json({ success: true });
  } catch (error) {
    console.error("[Device] BLE sighting upload error:", error);
    res.status(500).json({ error: "Failed to upload sightings" });
  }
});

/**
 * POST /v1/device/ble-separation
 * Notify guardians that a BLE tag went out of range.
 */
router.post("/ble-separation", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { tagName, latitude, longitude } = req.body;

  if (!tagName) {
    res.status(400).json({ error: "tagName is required" });
    return;
  }

  try {
    // Get all guardians linked to this protected person
    const links = await db.collection("guardian_links")
      .where("protectedPersonId", "==", uid)
      .where("status", "==", "active")
      .get();
    const tag = String(tagName).slice(0, 60);

    const data: Record<string, string> = {
      type: "ble_separation",
      tagName: tag,
      protectedPersonId: uid,
      ...(latitude ? { latitude: String(latitude) } : {}),
      ...(longitude ? { longitude: String(longitude) } : {}),
    };
    await Promise.all(links.docs.map(async (link) => {
      const guardianId = link.data().guardianId;
      const copy = await alertCopyFor(guardianId);
      return sendPushToUser(guardianId, {
        notification: {
          title: copy.bleSeparationTitle,
          body: copy.bleSeparationBody(tag),
        },
        data,
      }, "BLE separation");
    }));

    // Records timeline (the collection guardians and the person read)
    const own = await alertCopyFor(uid);
    await db.collection("timeline_entries").add({
      userId: uid,
      type: "ble_separation",
      description: own.bleSeparationBody(tag),
      detail: null,
      latitude: typeof latitude === "number" ? latitude : null,
      longitude: typeof longitude === "number" ? longitude : null,
      timestamp: admin.firestore.Timestamp.now(),
    });

    res.json({ success: true });
  } catch (error) {
    console.error("[Device] BLE separation alert error:", error);
    res.status(500).json({ error: "Failed to send separation alert" });
  }
});

export default router;
