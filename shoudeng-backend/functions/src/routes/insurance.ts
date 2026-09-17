import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

const DISCLAIMER =
  "本导出内容来源于用户设备记录与守灯服务器日志，仅供用户自行参考使用。守灯不对记录的准确性、完整性或适用性作任何明示或暗示的保证，不对使用本内容产生的任何后果承担责任。";

router.use(authMiddleware);

/**
 * POST /v1/insurance/claim-materials
 * Export user device records around an incident — reference only.
 * User controls what to include. Vela does NOT certify or guarantee anything.
 */
router.post("/claim-materials", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const {
    incidentDate,
    windowHours = 24,
    description,
    insuranceType,
    policyNumber,
    includeSOS = true,
    includeCheckIns = true,
    includeTimeline = true,
    includeLocation = true,
    includeMedicalCard = true,
  } = req.body;

  if (!incidentDate) {
    res.status(400).json({ error: "incidentDate is required" });
    return;
  }

  try {
    const incidentTime = new Date(incidentDate);
    const halfWindow = windowHours * 60 * 60 * 1000;
    const windowStart = new Date(incidentTime.getTime() - halfWindow);
    const windowEnd = new Date(incidentTime.getTime() + halfWindow);

    const startTs = admin.firestore.Timestamp.fromDate(windowStart);
    const endTs = admin.firestore.Timestamp.fromDate(windowEnd);

    // SOS events (user-controlled)
    let sosEvents = null;
    if (includeSOS) {
      const sosSnap = await db
        .collection("sos_events")
        .where("protectedPersonId", "==", uid)
        .where("triggeredAt", ">=", startTs)
        .where("triggeredAt", "<=", endTs)
        .get();
      sosEvents = sosSnap.docs.map((d) => {
        const data = d.data();
        return {
          triggeredAt: data.triggeredAt.toDate().toISOString(),
          triggerMethod: data.triggerMethod || null,
          resolution: data.resolution || null,
          latitude: includeLocation ? (data.latitude || null) : null,
          longitude: includeLocation ? (data.longitude || null) : null,
        };
      });
    }

    // Check-ins (user-controlled)
    let checkIns = null;
    if (includeCheckIns) {
      const ciSnap = await db
        .collection("checkins")
        .where("userId", "==", uid)
        .where("timestamp", ">=", startTs)
        .where("timestamp", "<=", endTs)
        .orderBy("timestamp", "asc")
        .get();
      checkIns = ciSnap.docs.map((d) => {
        const data = d.data();
        return {
          timestamp: data.timestamp.toDate().toISOString(),
          latitude: includeLocation ? (data.latitude || null) : null,
          longitude: includeLocation ? (data.longitude || null) : null,
          note: data.note || null,
        };
      });
    }

    // Timeline entries (user-controlled)
    let timeline = null;
    if (includeTimeline) {
      const tlSnap = await db
        .collection("timeline_entries")
        .where("userId", "==", uid)
        .where("timestamp", ">=", startTs)
        .where("timestamp", "<=", endTs)
        .orderBy("timestamp", "asc")
        .get();
      timeline = tlSnap.docs.map((d) => {
        const data = d.data();
        return {
          timestamp: data.timestamp.toDate().toISOString(),
          type: data.type || null,
          description: data.description || null,
        };
      });
    }

    // Medical card snapshot (user-controlled)
    let medicalSnapshot = null;
    if (includeMedicalCard) {
      const medDoc = await db.collection("medical_cards").doc(uid).get();
      if (medDoc.exists) {
        const md = medDoc.data()!;
        medicalSnapshot = {
          bloodType: md.bloodType || null,
          allergies: md.allergies || null,
          conditions: md.conditions || null,
          insuranceProvider: md.insuranceProvider || null,
          policyNumber: md.insurancePolicyNumber || null,
        };
      }
    }

    // Get user name
    const userDoc = await db.collection("users").doc(uid).get();
    const userName = userDoc.exists ? userDoc.data()!.displayName : "Unknown";

    const now = new Date();
    const exportId = `EXP-${uid.substring(0, 6).toUpperCase()}-${now.getTime()}`;

    // Build response body (without hash — hash computed over this)
    const body = {
      exportId,
      personName: userName,
      exportedAt: now.toISOString(),
      incidentDate: incidentTime.toISOString(),
      window: {
        start: windowStart.toISOString(),
        end: windowEnd.toISOString(),
      },
      sosEvents,
      checkIns,
      timeline,
      medicalSnapshot,
      contentHash: "", // placeholder
      disclaimer: DISCLAIMER,
    };

    // Compute SHA-256 hash over the content (excluding the hash field itself)
    const hashInput = JSON.stringify({
      ...body,
      contentHash: undefined,
    });
    const contentHash = crypto
      .createHash("sha256")
      .update(hashInput)
      .digest("hex");
    body.contentHash = contentHash;

    // Save minimal metadata only (not the full export)
    await db.collection("claim_material_exports").add({
      exportId,
      userId: uid,
      incidentDate: admin.firestore.Timestamp.fromDate(incidentTime),
      exportedAt: admin.firestore.Timestamp.now(),
      insuranceType: insuranceType || null,
      contentHash,
    });

    res.json(body);
  } catch (error) {
    console.error("[Insurance] claim materials error:", error);
    res.status(500).json({ error: "Failed to export claim materials" });
  }
});

/**
 * GET /v1/insurance/exports
 * List user's past claim material exports (metadata only).
 */
router.get("/exports", async (req: Request, res: Response) => {
  const uid = req.uid!;
  try {
    const snapshot = await db
      .collection("claim_material_exports")
      .where("userId", "==", uid)
      .orderBy("exportedAt", "desc")
      .limit(50)
      .get();

    const exports = snapshot.docs.map((d) => {
      const data = d.data();
      return {
        exportId: data.exportId,
        incidentDate: data.incidentDate.toDate().toISOString(),
        exportedAt: data.exportedAt.toDate().toISOString(),
        insuranceType: data.insuranceType,
      };
    });

    res.json({ exports });
  } catch (error) {
    console.error("[Insurance] list exports error:", error);
    res.status(500).json({ error: "Failed to list exports" });
  }
});

/**
 * POST /v1/insurance/claim-report  (legacy endpoint — kept for compatibility)
 * Generate a timestamped incident report for insurance claims.
 * Includes location trail, SOS events, check-ins, and heartbeat data.
 */
router.post("/claim-report", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { incidentDate, description, protectedPersonId } = req.body;

  if (!incidentDate) {
    res.status(400).json({ error: "incidentDate is required" });
    return;
  }

  try {
    const targetId = protectedPersonId || uid;

    // Verify access
    if (targetId !== uid) {
      const linkSnapshot = await db
        .collection("guardian_links")
        .where("guardianId", "==", uid)
        .where("protectedPersonId", "==", targetId)
        .where("status", "==", "active")
        .limit(1)
        .get();
      if (linkSnapshot.empty) {
        res.status(403).json({ error: "Not authorized" });
        return;
      }
    }

    const incidentTime = new Date(incidentDate);
    const windowStart = new Date(incidentTime.getTime() - 24 * 60 * 60 * 1000);
    const windowEnd = new Date(incidentTime.getTime() + 24 * 60 * 60 * 1000);

    const startTs = admin.firestore.Timestamp.fromDate(windowStart);
    const endTs = admin.firestore.Timestamp.fromDate(windowEnd);

    // Gather SOS events in window
    const sosSnapshot = await db
      .collection("sos_events")
      .where("protectedPersonId", "==", targetId)
      .where("triggeredAt", ">=", startTs)
      .where("triggeredAt", "<=", endTs)
      .get();

    const sosEvents = sosSnapshot.docs.map((d) => {
      const data = d.data();
      return {
        id: d.id,
        triggeredAt: data.triggeredAt.toDate().toISOString(),
        triggerMethod: data.triggerMethod,
        escalationState: data.escalationState,
        resolvedAt: data.resolvedAt
          ? data.resolvedAt.toDate().toISOString()
          : null,
        resolution: data.resolution,
        latitude: data.latitude,
        longitude: data.longitude,
      };
    });

    // Gather check-ins in window
    const checkinsSnapshot = await db
      .collection("checkins")
      .where("userId", "==", targetId)
      .where("timestamp", ">=", startTs)
      .where("timestamp", "<=", endTs)
      .orderBy("timestamp", "asc")
      .get();

    const checkIns = checkinsSnapshot.docs.map((d) => {
      const data = d.data();
      return {
        timestamp: data.timestamp.toDate().toISOString(),
        latitude: data.latitude,
        longitude: data.longitude,
        note: data.note,
      };
    });

    // Gather timeline entries
    const timelineSnapshot = await db
      .collection("timeline_entries")
      .where("userId", "==", targetId)
      .where("timestamp", ">=", startTs)
      .where("timestamp", "<=", endTs)
      .orderBy("timestamp", "asc")
      .get();

    const timeline = timelineSnapshot.docs.map((d) => {
      const data = d.data();
      return {
        timestamp: data.timestamp.toDate().toISOString(),
        type: data.type,
        description: data.description,
      };
    });

    // Get user info
    const userDoc = await db.collection("users").doc(targetId).get();
    const userName = userDoc.exists
      ? userDoc.data()!.displayName
      : "Unknown";

    // Get medical card if exists
    const medicalDoc = await db
      .collection("medical_cards")
      .doc(targetId)
      .get();
    const medicalCard = medicalDoc.exists
      ? {
          bloodType: medicalDoc.data()!.bloodType,
          allergies: medicalDoc.data()!.allergies,
          conditions: medicalDoc.data()!.conditions,
        }
      : null;

    const now = new Date();
    const reportId = `RPT-${targetId.substring(0, 6)}-${now.getTime()}`;

    // Save report record
    await db.collection("insurance_reports").add({
      reportId,
      requestedBy: uid,
      protectedPersonId: targetId,
      incidentDate: admin.firestore.Timestamp.fromDate(incidentTime),
      generatedAt: admin.firestore.Timestamp.now(),
      description: description || null,
    });

    res.json({
      reportId,
      personName: userName,
      incidentDate: incidentTime.toISOString(),
      reportWindow: {
        start: windowStart.toISOString(),
        end: windowEnd.toISOString(),
      },
      sosEvents,
      checkIns,
      timeline,
      medicalCard,
      generatedAt: now.toISOString(),
      dataIntegrity: {
        method: "SHA-256 Merkle tree (daily proof)",
        note: "Daily integrity proofs are computed via scheduled function.",
      },
      disclaimer:
        "此报告由守灯安全系统自动生成，数据基于设备传感器与网络记录，完整性可通过每日 Merkle 根验证。仅供保险理赔参考，不构成法律文件。",
    });
  } catch (error) {
    console.error("[Insurance] claim report error:", error);
    res
      .status(500)
      .json({ error: "Failed to generate claim report" });
  }
});

/**
 * GET /v1/insurance/verify/:reportId
 * Verify an existing report (for insurer access — future: with API key auth).
 */
router.get("/verify/:reportId", async (req: Request, res: Response) => {
  const { reportId } = req.params;

  try {
    const snapshot = await db
      .collection("insurance_reports")
      .where("reportId", "==", reportId)
      .limit(1)
      .get();

    if (snapshot.empty) {
      res.status(404).json({ error: "Report not found" });
      return;
    }

    const data = snapshot.docs[0].data();
    res.json({
      reportId: data.reportId,
      protectedPersonId: data.protectedPersonId,
      incidentDate: data.incidentDate.toDate().toISOString(),
      generatedAt: data.generatedAt.toDate().toISOString(),
      verified: true,
    });
  } catch (error) {
    console.error("[Insurance] verify error:", error);
    res.status(500).json({ error: "Failed to verify report" });
  }
});

export default router;
