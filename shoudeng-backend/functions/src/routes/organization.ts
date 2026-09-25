import { Router, Request, Response } from "express";
import * as admin from "firebase-admin";
import { authMiddleware } from "../middleware/auth";

const router = Router();
const db = admin.firestore();

router.use(authMiddleware);

/**
 * POST /v1/org
 * Create an organization (for B2B institutional clients).
 */
router.post("/", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { name, type, contactEmail, contactPhone } = req.body;

  if (!name || !type) {
    res.status(400).json({ error: "name and type are required" });
    return;
  }

  try {
    const now = admin.firestore.Timestamp.now();
    const orgRef = await db.collection("organizations").add({
      name,
      type,
      contactEmail: contactEmail || null,
      contactPhone: contactPhone || null,
      adminIds: [uid],
      memberCount: 0,
      activatedCount: 0,
      createdAt: now,
      updatedAt: now,
    });

    res.status(201).json({ orgId: orgRef.id, success: true });
  } catch (error) {
    console.error("[Org] create error:", error);
    res.status(500).json({ error: "Failed to create organization" });
  }
});

/**
 * GET /v1/org/dashboard
 * Compliance dashboard: member status overview.
 */
router.get("/dashboard", async (req: Request, res: Response) => {
  const uid = req.uid!;

  try {
    // Find orgs where user is admin
    const orgsSnapshot = await db
      .collection("organizations")
      .where("adminIds", "array-contains", uid)
      .get();

    if (orgsSnapshot.empty) {
      res.status(404).json({ error: "No organization found" });
      return;
    }

    const org = orgsSnapshot.docs[0];
    const orgData = org.data();
    const orgId = org.id;

    // Get all members
    const membersSnapshot = await db
      .collection("org_members")
      .where("orgId", "==", orgId)
      .get();

    let totalMembers = 0;
    let activated = 0;
    let permissionsAbnormal = 0;
    let notInstalled = 0;
    let recentCheckIns = 0;
    let overdueCheckIns = 0;

    const memberDetails = [];
    const cutoff = new Date(Date.now() - 8 * 60 * 60 * 1000);

    for (const memberDoc of membersSnapshot.docs) {
      const member = memberDoc.data();
      totalMembers++;

      const userDoc = await db
        .collection("users")
        .doc(member.userId)
        .get();

      if (!userDoc.exists) {
        notInstalled++;
        memberDetails.push({
          userId: member.userId,
          displayName: member.displayName || "未激活",
          status: "not_installed",
          lastCheckIn: null,
        });
        continue;
      }

      activated++;

      // Check latest check-in
      const checkinSnapshot = await db
        .collection("checkins")
        .where("userId", "==", member.userId)
        .orderBy("timestamp", "desc")
        .limit(1)
        .get();

      let lastCheckIn = null;
      let memberStatus = "normal";
      if (!checkinSnapshot.empty) {
        lastCheckIn = checkinSnapshot.docs[0]
          .data()
          .timestamp.toDate()
          .toISOString();
        if (checkinSnapshot.docs[0].data().timestamp.toDate() < cutoff) {
          overdueCheckIns++;
          memberStatus = "overdue";
        } else {
          recentCheckIns++;
        }
      } else {
        overdueCheckIns++;
        memberStatus = "overdue";
      }

      // Check permissions
      const tokenSnapshot = await db
        .collection("device_tokens")
        .where("userId", "==", member.userId)
        .limit(1)
        .get();
      if (tokenSnapshot.empty) {
        permissionsAbnormal++;
        memberStatus = "permissions_abnormal";
      }

      memberDetails.push({
        userId: member.userId,
        displayName: userDoc.data()!.displayName,
        status: memberStatus,
        lastCheckIn,
        cityName: userDoc.data()!.cityName,
        countryCode: userDoc.data()!.countryCode,
      });
    }

    res.json({
      orgId,
      orgName: orgData.name,
      orgType: orgData.type,
      summary: {
        totalMembers,
        activated,
        permissionsAbnormal,
        notInstalled,
        recentCheckIns,
        overdueCheckIns,
      },
      members: memberDetails,
    });
  } catch (error) {
    console.error("[Org] dashboard error:", error);
    res.status(500).json({ error: "Failed to load dashboard" });
  }
});

/**
 * POST /v1/org/members
 * Add members to organization (batch).
 */
router.post("/members", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { orgId, members } = req.body;

  if (!orgId || !members || !Array.isArray(members)) {
    res.status(400).json({ error: "orgId and members array are required" });
    return;
  }

  try {
    // Verify admin
    const orgDoc = await db.collection("organizations").doc(orgId).get();
    if (
      !orgDoc.exists ||
      !orgDoc.data()!.adminIds.includes(uid)
    ) {
      res.status(403).json({ error: "Not authorized" });
      return;
    }

    const batch = db.batch();
    const now = admin.firestore.Timestamp.now();

    for (const member of members) {
      const memberRef = db.collection("org_members").doc();
      batch.set(memberRef, {
        orgId,
        userId: member.userId || null,
        displayName: member.displayName || member.name || "",
        email: member.email || null,
        phone: member.phone || null,
        role: member.role || "member",
        addedAt: now,
        addedBy: uid,
      });
    }

    // Update member count
    batch.update(db.collection("organizations").doc(orgId), {
      memberCount: admin.firestore.FieldValue.increment(members.length),
      updatedAt: now,
    });

    await batch.commit();
    res.json({ success: true, added: members.length });
  } catch (error) {
    console.error("[Org] add members error:", error);
    res.status(500).json({ error: "Failed to add members" });
  }
});

/**
 * POST /v1/org/alert
 * Send a regional alert to all members in a specific area or all members.
 */
router.post("/alert", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { orgId, title, body, countryCode, severity } = req.body;

  if (!orgId || !title || !body) {
    res
      .status(400)
      .json({ error: "orgId, title, and body are required" });
    return;
  }

  try {
    // Verify admin
    const orgDoc = await db.collection("organizations").doc(orgId).get();
    if (
      !orgDoc.exists ||
      !orgDoc.data()!.adminIds.includes(uid)
    ) {
      res.status(403).json({ error: "Not authorized" });
      return;
    }

    const now = admin.firestore.Timestamp.now();

    // Log the alert
    const alertRef = await db.collection("org_alerts").add({
      orgId,
      title,
      body,
      countryCode: countryCode || null,
      severity: severity || "warning",
      sentBy: uid,
      sentAt: now,
      confirmedCount: 0,
      noResponseCount: 0,
    });

    // Get target members
    let membersQuery = db
      .collection("org_members")
      .where("orgId", "==", orgId);

    const membersSnapshot = await membersQuery.get();

    let sentCount = 0;
    for (const memberDoc of membersSnapshot.docs) {
      const member = memberDoc.data();
      if (!member.userId) continue;

      // Filter by country if specified
      if (countryCode) {
        const userDoc = await db
          .collection("users")
          .doc(member.userId)
          .get();
        if (
          userDoc.exists &&
          userDoc.data()!.countryCode !== countryCode
        ) {
          continue;
        }
      }

      // Send push notification
      const tokenSnapshot = await db
        .collection("device_tokens")
        .where("userId", "==", member.userId)
        .get();

      const tokens = tokenSnapshot.docs.map((d) => d.data().token);
      if (tokens.length > 0) {
        try {
          await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title, body },
            apns: {
              headers: {
                "apns-priority": severity === "critical" ? "10" : "5",
              },
              payload: {
                aps: {
                  sound:
                    severity === "critical"
                      ? "sos_alert.caf"
                      : "default",
                  "interruption-level":
                    severity === "critical"
                      ? "critical"
                      : "active",
                },
              },
            },
            data: {
              action: "org_alert",
              alertId: alertRef.id,
              orgId,
            },
          });
          sentCount++;
        } catch {
          // Continue on individual send failure
        }
      }

      // Create a roll call entry for tracking responses
      await db.collection("org_roll_calls").add({
        alertId: alertRef.id,
        orgId,
        userId: member.userId,
        displayName: member.displayName,
        status: "pending",
        sentAt: now,
        respondedAt: null,
      });
    }

    // Update alert with sent count
    await alertRef.update({ sentCount });

    res.json({
      success: true,
      alertId: alertRef.id,
      sentCount,
    });
  } catch (error) {
    console.error("[Org] alert error:", error);
    res.status(500).json({ error: "Failed to send alert" });
  }
});

/**
 * POST /v1/org/roll-call/respond
 * Member responds to a roll call (confirms safe).
 */
router.post("/roll-call/respond", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { alertId } = req.body;

  if (!alertId) {
    res.status(400).json({ error: "alertId is required" });
    return;
  }

  try {
    const rollCallSnapshot = await db
      .collection("org_roll_calls")
      .where("alertId", "==", alertId)
      .where("userId", "==", uid)
      .limit(1)
      .get();

    if (rollCallSnapshot.empty) {
      res.status(404).json({ error: "Roll call entry not found" });
      return;
    }

    const rollCallRef = rollCallSnapshot.docs[0].ref;
    await rollCallRef.update({
      status: "confirmed",
      respondedAt: admin.firestore.Timestamp.now(),
    });

    // Update alert confirmed count
    await db
      .collection("org_alerts")
      .doc(alertId)
      .update({
        confirmedCount: admin.firestore.FieldValue.increment(1),
      });

    res.json({ success: true });
  } catch (error) {
    console.error("[Org] roll-call respond error:", error);
    res.status(500).json({ error: "Failed to respond" });
  }
});

/**
 * GET /v1/org/roll-call/:alertId
 * Get roll call status for an alert.
 */
router.get(
  "/roll-call/:alertId",
  async (req: Request, res: Response) => {
    const uid = req.uid!;
    const { alertId } = req.params;

    try {
      const alertDoc = await db
        .collection("org_alerts")
        .doc(alertId)
        .get();
      if (!alertDoc.exists) {
        res.status(404).json({ error: "Alert not found" });
        return;
      }

      // Verify caller is an admin of the org that owns this alert
      const alertOrgId = alertDoc.data()!.orgId;
      const orgDoc = await db.collection("organizations").doc(alertOrgId).get();
      if (!orgDoc.exists || !orgDoc.data()!.adminIds.includes(uid)) {
        // Also allow if caller is a member of the org
        const memberSnap = await db
          .collection("org_members")
          .where("orgId", "==", alertOrgId)
          .where("userId", "==", uid)
          .limit(1)
          .get();
        if (memberSnap.empty) {
          res.status(403).json({ error: "Not authorized to view this roll call" });
          return;
        }
      }

      const rollCallSnapshot = await db
        .collection("org_roll_calls")
        .where("alertId", "==", alertId)
        .get();

      const entries = rollCallSnapshot.docs.map((d) => {
        const data = d.data();
        return {
          userId: data.userId,
          displayName: data.displayName,
          status: data.status,
          respondedAt: data.respondedAt
            ? data.respondedAt.toDate().toISOString()
            : null,
        };
      });

      const confirmed = entries.filter(
        (e) => e.status === "confirmed"
      ).length;
      const pending = entries.filter(
        (e) => e.status === "pending"
      ).length;

      res.json({
        alertId,
        title: alertDoc.data()!.title,
        totalMembers: entries.length,
        confirmed,
        noResponse: pending,
        entries,
      });
    } catch (error) {
      console.error("[Org] roll-call status error:", error);
      res.status(500).json({ error: "Failed to get roll call status" });
    }
  }
);

/**
 * GET /v1/org/reports
 * Generate a compliance/duty-of-care report for the organization.
 */
router.get("/reports", async (req: Request, res: Response) => {
  const uid = req.uid!;
  const { orgId, startDate, endDate } = req.query;

  if (!orgId) {
    res.status(400).json({ error: "orgId query parameter is required" });
    return;
  }

  try {
    const orgDoc = await db
      .collection("organizations")
      .doc(orgId as string)
      .get();
    if (
      !orgDoc.exists ||
      !orgDoc.data()!.adminIds.includes(uid)
    ) {
      res.status(403).json({ error: "Not authorized" });
      return;
    }

    const start = startDate
      ? admin.firestore.Timestamp.fromDate(new Date(startDate as string))
      : admin.firestore.Timestamp.fromDate(
          new Date(Date.now() - 365 * 24 * 60 * 60 * 1000)
        );
    const end = endDate
      ? admin.firestore.Timestamp.fromDate(new Date(endDate as string))
      : admin.firestore.Timestamp.now();

    // Count check-ins in period
    const membersSnapshot = await db
      .collection("org_members")
      .where("orgId", "==", orgId)
      .get();

    const memberIds = membersSnapshot.docs
      .map((d) => d.data().userId)
      .filter(Boolean);

    let totalCheckIns = 0;
    let totalAlerts = 0;
    let totalSOSEvents = 0;

    for (const memberId of memberIds) {
      const checkins = await db
        .collection("checkins")
        .where("userId", "==", memberId)
        .where("timestamp", ">=", start)
        .where("timestamp", "<=", end)
        .count()
        .get();
      totalCheckIns += checkins.data().count;
    }

    // Count org alerts
    const alertsSnapshot = await db
      .collection("org_alerts")
      .where("orgId", "==", orgId)
      .where("sentAt", ">=", start)
      .where("sentAt", "<=", end)
      .count()
      .get();
    totalAlerts = alertsSnapshot.data().count;

    // Count SOS events for members
    for (const memberId of memberIds) {
      const sosSnapshot = await db
        .collection("sos_events")
        .where("protectedPersonId", "==", memberId)
        .where("triggeredAt", ">=", start)
        .where("triggeredAt", "<=", end)
        .count()
        .get();
      totalSOSEvents += sosSnapshot.data().count;
    }

    res.json({
      orgId,
      orgName: orgDoc.data()!.name,
      reportPeriod: {
        start: start.toDate().toISOString(),
        end: end.toDate().toISOString(),
      },
      summary: {
        totalMembers: memberIds.length,
        totalCheckIns,
        totalAlerts,
        totalSOSEvents,
        avgCheckInsPerMember:
          memberIds.length > 0
            ? Math.round(totalCheckIns / memberIds.length)
            : 0,
      },
      generatedAt: new Date().toISOString(),
      disclaimer:
        "此报告由守灯安全系统自动生成，仅供合规审计参考。",
    });
  } catch (error) {
    console.error("[Org] reports error:", error);
    res.status(500).json({ error: "Failed to generate report" });
  }
});

export default router;
