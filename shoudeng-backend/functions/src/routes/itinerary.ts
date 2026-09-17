import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/itinerary
 * Add a shared itinerary (flight, train, bus).
 * Family can see ETA and status without the protected person doing anything.
 */
router.post("/", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const {
    type,
    carrierCode,
    flightNumber,
    departureCity,
    arrivalCity,
    departureTime,
    arrivalTime,
    note,
  } = req.body;

  if (!type || !departureCity || !arrivalCity || !departureTime) {
    res.status(400).json({
      error: "type, departureCity, arrivalCity, and departureTime are required",
    });
    return;
  }

  try {
    const now = admin.firestore.Timestamp.now();
    const docRef = await db.collection("itineraries").add({
      userId: uid,
      type: type || "flight",
      carrierCode: carrierCode || null,
      flightNumber: flightNumber || null,
      departureCity,
      arrivalCity,
      departureTime: admin.firestore.Timestamp.fromDate(
        new Date(departureTime)
      ),
      arrivalTime: arrivalTime
        ? admin.firestore.Timestamp.fromDate(new Date(arrivalTime))
        : null,
      note: note || null,
      status: "scheduled",
      createdAt: now,
    });

    // Add timeline entry
    const typeLabels: Record<string, string> = {
      flight: "航班",
      train: "列车",
      bus: "大巴",
    };
    await db.collection("timeline_entries").add({
      userId: uid,
      timestamp: now,
      type: "itineraryAdded",
      description: `添加了${typeLabels[type] || "行程"}：${departureCity} → ${arrivalCity}`,
      detail: carrierCode && flightNumber ? `${carrierCode}${flightNumber}` : null,
    });

    res.status(201).json({
      id: docRef.id,
      success: true,
    });
  } catch (error) {
    console.error("[Itinerary] create error:", error);
    res.status(500).json({ error: "Failed to create itinerary" });
  }
});

/**
 * GET /v1/itinerary
 * Get itineraries. Protected person sees own; guardian sees all linked persons'.
 */
router.get("/", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    // Get user role
    const userDoc = await db.collection("users").doc(uid).get();
    const role = userDoc.exists ? userDoc.data()!.role : "protected";

    const personIds = [uid];

    if (role === "guardian") {
      const linksSnapshot = await db
        .collection("guardian_links")
        .where("guardianId", "==", uid)
        .where("status", "==", "active")
        .get();
      for (const linkDoc of linksSnapshot.docs) {
        personIds.push(linkDoc.data().protectedPersonId);
      }
    }

    // Query upcoming/active itineraries (last 24h + future)
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 24 * 60 * 60 * 1000)
    );

    const results = [];
    for (const personId of personIds) {
      const snapshot = await db
        .collection("itineraries")
        .where("userId", "==", personId)
        .where("departureTime", ">=", cutoff)
        .orderBy("departureTime", "asc")
        .limit(20)
        .get();

      const pUserDoc = await db.collection("users").doc(personId).get();
      const displayName = pUserDoc.exists
        ? pUserDoc.data()!.displayName
        : "未知";

      for (const doc of snapshot.docs) {
        const data = doc.data();
        results.push({
          id: doc.id,
          userId: personId,
          displayName,
          type: data.type,
          carrierCode: data.carrierCode,
          flightNumber: data.flightNumber,
          departureCity: data.departureCity,
          arrivalCity: data.arrivalCity,
          departureTime: data.departureTime.toDate().toISOString(),
          arrivalTime: data.arrivalTime
            ? data.arrivalTime.toDate().toISOString()
            : null,
          note: data.note,
          status: data.status,
        });
      }
    }

    res.json(results);
  } catch (error) {
    console.error("[Itinerary] list error:", error);
    res.status(500).json({ error: "Failed to fetch itineraries" });
  }
});

/**
 * DELETE /v1/itinerary/:id
 * Remove an itinerary.
 */
router.delete("/:id", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { id } = req.params;

  try {
    const docRef = db.collection("itineraries").doc(id);
    const doc = await docRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "Itinerary not found" });
      return;
    }

    if (doc.data()!.userId !== uid) {
      res.status(403).json({ error: "Not authorized" });
      return;
    }

    await docRef.delete();
    res.json({ success: true });
  } catch (error) {
    console.error("[Itinerary] delete error:", error);
    res.status(500).json({ error: "Failed to delete itinerary" });
  }
});

export default router;
