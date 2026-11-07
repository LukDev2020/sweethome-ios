import { Router, Request, Response } from "express";
import { endWatchBackWith } from "../services/watchBack";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { onDutyGuardians } from "../services/escalation";
import { toIso } from "../services/time";

export function isoToCalendarWeekday(iso: number): number {
  return (iso % 7) + 1; // Mon 1 → 2 … Sat 6 → 7, Sun 7 → 1
}

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * GET /v1/protected/guardians
 * Get all guardians for the current protected person.
 * This is the data source for ProtectedHomeView guardian list.
 */
router.get("/guardians", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    // Find all active guardian links where this user is the protected person
    const linksSnapshot = await db
      .collection("guardian_links")
      .where("protectedPersonId", "==", uid)
      .where("status", "==", "active")
      .get();

    if (linksSnapshot.empty) {
      res.json([]);
      return;
    }

    const guardians = [];
    const personTimeZone = (await db.collection("users").doc(uid).get()).data()?.timeZone;

    for (const linkDoc of linksSnapshot.docs) {
      const link = linkDoc.data();
      const guardianId = link.guardianId;

      // Fetch guardian user profile
      const userDoc = await db.collection("users").doc(guardianId).get();
      if (!userDoc.exists) continue;
      const user = userDoc.data()!;

      // Check if guardian is currently on duty
      const isOnDuty = await checkOnDuty(guardianId, uid, personTimeZone);

      // Get duty schedule
      const scheduleSnapshot = await db
        .collection("duty_schedules")
        .where("guardianId", "==", guardianId)
        .where("protectedPersonId", "==", uid)
        .where("isActive", "==", true)
        .get();

      const dutySlots = scheduleSnapshot.docs.map((d) => d.data());

      guardians.push({
        id: guardianId,
        user: {
          id: guardianId,
          displayName: user.displayName,
          role: "guardian",
          avatarInitial: user.avatarInitial ?? String(user.displayName ?? "").charAt(0),
          timeZone: user.timeZone ?? null,
          countryCode: user.countryCode ?? "",
          cityName: user.cityName ?? "",
          createdAt: toIso(user.createdAt),
        },
        permissions: link.permissions || {
          canSeeLocation: true,
          canSeeBattery: true,
          canSeeHealth: false,
          canSeePhoneActivity: false,
          canHearEmergencyAudio: true,
        },
        isOnDuty,
        dutySchedule: dutySlots.length > 0
          ? {
              guardianId,
              slots: dutySlots.map((s) => ({
                startHour: s.startHour,
                endHour: s.endHour,
                // Stored as ISO weekday (1 = Mon … 7 = Sun); iOS DutySlot uses
                // Calendar weekdays (1 = Sun … 7 = Sat)
                dayOfWeek: [isoToCalendarWeekday(s.dayOfWeek)],
                isConfirmed: true,
              })),
            }
          : null,
        averageResponseTime: 120, // Default 2 minutes, would be computed from history
        linkedSince: toIso(link.createdAt) ?? new Date(0).toISOString(),
      });
    }

    res.json(guardians);
  } catch (error) {
    console.error("[Protected] fetch guardians error:", error);
    res.status(500).json({ error: "Failed to fetch guardians" });
  }
});

/**
 * Check if a guardian is currently on duty for a protected person.
 */
async function checkOnDuty(
  guardianId: string,
  protectedPersonId: string,
  personTimeZone?: string
): Promise<boolean> {
  // Duty hours are the protected person's local hours (the server runs in UTC)
  const onDuty = await onDutyGuardians(protectedPersonId, [guardianId], personTimeZone, new Date());
  return onDuty.length > 0;
}

/**
 * PUT /v1/protected/guardians/:guardianId/permissions
 * Update the permissions a protected person grants to a specific guardian.
 */
router.put(
  "/guardians/:guardianId/permissions",
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { guardianId } = req.params;
    const {
      canSeeLocation,
      canSeeBattery,
      canSeeHealth,
      canSeePhoneActivity,
      canHearEmergencyAudio,
    } = req.body;

    try {
      const linkId = `${guardianId}_${uid}`;
      const linkRef = db.collection("guardian_links").doc(linkId);
      const linkDoc = await linkRef.get();

      if (!linkDoc.exists || linkDoc.data()!.status !== "active") {
        res.status(404).json({ error: "Guardian link not found" });
        return;
      }

      // Verify the caller is the protected person in this link
      if (linkDoc.data()!.protectedPersonId !== uid) {
        res.status(403).json({ error: "Only the protected person can update permissions" });
        return;
      }

      await linkRef.update({
        permissions: {
          canSeeLocation: canSeeLocation ?? true,
          canSeeBattery: canSeeBattery ?? true,
          canSeeHealth: canSeeHealth ?? false,
          canSeePhoneActivity: canSeePhoneActivity ?? false,
          canHearEmergencyAudio: canHearEmergencyAudio ?? true,
        },
        permissionsUpdatedAt: admin.firestore.Timestamp.now(),
      });

      res.json({ success: true });
    } catch (error) {
      console.error("[Protected] update permissions error:", error);
      res.status(500).json({ error: "Failed to update permissions" });
    }
  }
);

/**
 * DELETE /v1/protected/guardians/:guardianId
 * Remove a guardian. Sets link status to "revoked".
 * The 6-hour delay is enforced client-side (UI shows pending state).
 */
router.delete(
  "/guardians/:guardianId",
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { guardianId } = req.params;

    try {
      const linkId = `${guardianId}_${uid}`;
      const linkRef = db.collection("guardian_links").doc(linkId);
      const linkDoc = await linkRef.get();

      if (!linkDoc.exists || linkDoc.data()!.status !== "active") {
        res.status(404).json({ error: "Guardian link not found" });
        return;
      }

      if (linkDoc.data()!.protectedPersonId !== uid) {
        res.status(403).json({ error: "Only the protected person can remove a guardian" });
        return;
      }

      await linkRef.update({
        status: "revoked",
        revokedAt: admin.firestore.Timestamp.now(),
        revokedBy: uid,
      });
      // Watching that guardian back ends with it
      await endWatchBackWith(guardianId, uid);

      res.json({ success: true });
    } catch (error) {
      console.error("[Protected] remove guardian error:", error);
      res.status(500).json({ error: "Failed to remove guardian" });
    }
  }
);

export default router;
