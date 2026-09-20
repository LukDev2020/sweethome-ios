import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * PUT /v1/duty-schedule
 * Update duty schedule for a guardian-protected pair.
 * Called by the protected person to assign schedule to a guardian.
 */
router.put("/", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { guardianId, slots } = req.body;

  if (!guardianId || !slots) {
    res.status(400).json({ error: "guardianId and slots are required" });
    return;
  }

  try {
    // Verify the guardian link exists
    const linkId = `${guardianId}_${uid}`;
    const linkDoc = await db.collection("guardian_links").doc(linkId).get();

    if (!linkDoc.exists || linkDoc.data()?.status !== "active") {
      res.status(403).json({ error: "No active guardian link found" });
      return;
    }

    // Delete existing schedules for this pair
    const existingSnapshot = await db
      .collection("duty_schedules")
      .where("guardianId", "==", guardianId)
      .where("protectedPersonId", "==", uid)
      .get();

    const batch = db.batch();
    existingSnapshot.docs.forEach((doc) => batch.delete(doc.ref));

    // Create new schedule entries
    for (const slot of slots) {
      const start = slot.startHour;
      const end = slot.endHour;
      if (typeof start !== "number" || typeof end !== "number" ||
          start < 0 || start > 23 || end < 0 || end > 23 || start >= end) {
        res.status(400).json({ error: "startHour and endHour must be integers 0-23 with startHour < endHour" });
        return;
      }
      const days: number[] = slot.dayOfWeek || [1, 2, 3, 4, 5, 6, 7];
      for (const day of days) {
        const scheduleRef = db.collection("duty_schedules").doc();
        batch.set(scheduleRef, {
          protectedPersonId: uid,
          guardianId,
          dayOfWeek: day,
          startHour: start,
          endHour: end,
          timeZone: "Asia/Shanghai", // Would use user's timezone
          isActive: true,
        });
      }
    }

    await batch.commit();

    res.json({ success: true });
  } catch (error) {
    console.error("[DutySchedule] update error:", error);
    res.status(500).json({ error: "Failed to update duty schedule" });
  }
});

export default router;
