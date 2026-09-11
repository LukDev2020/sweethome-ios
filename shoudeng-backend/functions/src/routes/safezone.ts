import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { v4 as uuidv4 } from "uuid";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/safe-zone/save
 * Create or update a safe zone for the current user.
 */
router.post("/save", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { name, latitude, longitude, radius, id: existingId } = req.body;

  if (!name || latitude === undefined || longitude === undefined) {
    res
      .status(400)
      .json({ error: "name, latitude, and longitude are required" });
    return;
  }

  try {
    const zoneId = existingId || uuidv4();

    await db
      .collection("safe_zones")
      .doc(zoneId)
      .set(
        {
          userId: uid,
          name,
          latitude,
          longitude,
          radiusMeters: radius || 100,
          type: "custom",
          isActive: true,
          createdAt: admin.firestore.Timestamp.now(),
        },
        { merge: true }
      );

    res.json({
      id: zoneId,
      name,
      latitude,
      longitude,
      radius: radius || 100,
      isAutoSuggested: false,
    });
  } catch (error) {
    console.error("[SafeZone] save error:", error);
    res.status(500).json({ error: "Failed to save safe zone" });
  }
});

/**
 * GET /v1/safe-zones
 * Get all active safe zones for the current user.
 */
router.get("/", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    const snapshot = await db
      .collection("safe_zones")
      .where("userId", "==", uid)
      .where("isActive", "==", true)
      .get();

    const zones = snapshot.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        name: data.name,
        latitude: data.latitude,
        longitude: data.longitude,
        radius: data.radiusMeters,
        isAutoSuggested: data.type !== "custom",
      };
    });

    res.json(zones);
  } catch (error) {
    console.error("[SafeZone] fetch error:", error);
    res.status(500).json({ error: "Failed to fetch safe zones" });
  }
});

export default router;
