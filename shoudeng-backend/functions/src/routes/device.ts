import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/device/token
 * Register or update an APNs device token for push notifications.
 */
router.post("/token", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { token, platform, environment } = req.body;

  if (!token || !platform) {
    res.status(400).json({ error: "token and platform are required" });
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
        environment: environment || "production",
        updatedAt: admin.firestore.Timestamp.now(),
      });

    res.json({ success: true });
  } catch (error) {
    console.error("[Device] token registration error:", error);
    res.status(500).json({ error: "Failed to register device token" });
  }
});

export default router;
