import { Router, Request, Response } from "express";
import { endWatchBackWith } from "../services/watchBack";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";
import { guardiansOf } from "../services/guardianList";
export { isoToCalendarWeekday } from "../services/guardianList";

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
    res.json(await guardiansOf(uid));
  } catch (error) {
    console.error("[Protected] fetch guardians error:", error);
    res.status(500).json({ error: "Failed to fetch guardians" });
  }
});

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
