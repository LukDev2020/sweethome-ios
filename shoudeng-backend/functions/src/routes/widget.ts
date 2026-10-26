import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * GET /v1/widget/data
 * Lightweight endpoint for iOS widget data.
 * Returns minimal data to populate lock screen / home screen widgets.
 */
router.get("/data", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    // User profile
    const userDoc = await db.collection("users").doc(uid).get();
    if (!userDoc.exists) {
      res.status(404).json({ error: "User not found" });
      return;
    }
    const user = userDoc.data()!;

    // Latest check-in
    const checkinSnap = await db
      .collection("checkins")
      .where("userId", "==", uid)
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();
    const lastCheckIn = checkinSnap.empty
      ? null
      : checkinSnap.docs[0].data().timestamp.toDate().toISOString();

    // Active SOS
    const sosSnap = await db
      .collection("sos_events")
      .where("userId", "==", uid)
      .where("resolvedAt", "==", null)
      .limit(1)
      .get();
    const hasActiveSOS = !sosSnap.empty;

    // Guardian count
    const guardianCount = await db
      .collection("guardian_links")
      .where("protectedPersonId", "==", uid)
      .where("status", "==", "active")
      .count()
      .get();

    // Battery from user telemetry doc
    const telDoc = await db.collection("user_telemetry").doc(uid).get();
    const batteryLevel = telDoc.exists
      ? telDoc.data()?.batteryLevel ?? null
      : null;

    res.json({
      displayName: user.displayName || "",
      role: user.role || "protected",
      cityName: user.cityName || "",
      lastCheckIn,
      hasActiveSOS,
      guardianCount: guardianCount.data().count,
      batteryLevel,
      updatedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error("[Widget] data error:", error);
    res.status(500).json({ error: "Failed to fetch widget data" });
  }
});

export default router;
