import * as admin from "firebase-admin";

const db = admin.firestore();

/**
 * Get all device tokens for a user.
 */
async function getTokensForUser(userId: string): Promise<string[]> {
  const snapshot = await db
    .collection("device_tokens")
    .where("userId", "==", userId)
    .get();
  return snapshot.docs.map((doc) => doc.data().token);
}

/**
 * Check if a user has a specific notification type enabled.
 * Returns true by default if no preference is stored.
 */
async function isNotifEnabled(
  userId: string,
  prefKey: string
): Promise<boolean> {
  const userDoc = await db.collection("users").doc(userId).get();
  if (!userDoc.exists) return true;
  const prefs = userDoc.data()?.notificationPrefs;
  if (!prefs || prefs[prefKey] === undefined) return true;
  return prefs[prefKey] === true;
}

/**
 * Send SOS critical alert to a guardian.
 */
export async function sendSOSAlert(
  guardianId: string,
  protectedPersonName: string,
  sosEventId: string,
  locationDescription?: string
): Promise<void> {
  const tokens = await getTokensForUser(guardianId);
  if (tokens.length === 0) {
    console.warn(`[FCM] No tokens for guardian ${guardianId}`);
    return;
  }

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: "紧急求助",
      body: `${protectedPersonName}正在求助${locationDescription ? "，位于" + locationDescription : ""}`,
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
      },
      payload: {
        aps: {
          sound: "sos_alert.caf",
          "interruption-level": "critical",
          "relevance-score": 1.0,
          alert: {
            title: "紧急求助",
            body: `${protectedPersonName}正在求助`,
          },
        },
      },
    },
    data: {
      action: "sos_alert",
      sos_id: sosEventId,
      protected_person_name: protectedPersonName,
    },
  };

  try {
    const response = await admin.messaging().sendEachForMulticast(message);
    console.log(
      `[FCM] SOS alert sent to ${guardianId}: ${response.successCount} success, ${response.failureCount} failure`
    );
  } catch (error) {
    console.error(`[FCM] Failed to send SOS alert to ${guardianId}:`, error);
  }
}

/**
 * Send check-in reminder push to a guardian.
 */
export async function sendCheckinReminder(
  guardianId: string,
  protectedPersonName: string
): Promise<void> {
  if (!(await isNotifEnabled(guardianId, "checkinOverdue"))) return;

  const tokens = await getTokensForUser(guardianId);
  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: "报平安提醒",
      body: `${protectedPersonName}今天还没有报平安`,
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
          category: "CHECKIN_REMINDER",
        },
      },
    },
    data: {
      action: "checkin_reminder",
    },
  };

  try {
    await admin.messaging().sendEachForMulticast(message);
  } catch (error) {
    console.error(`[FCM] Failed to send checkin reminder:`, error);
  }
}

/**
 * Send heartbeat missing warning to a guardian.
 */
export async function sendHeartbeatMissingAlert(
  guardianId: string,
  protectedPersonName: string,
  lastSeenMinutes: number
): Promise<void> {
  if (!(await isNotifEnabled(guardianId, "checkinOverdue"))) return;

  const tokens = await getTokensForUser(guardianId);
  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: "设备离线提醒",
      body: `${protectedPersonName}的手机已 ${lastSeenMinutes} 分钟未上报信号`,
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
    data: {
      action: "heartbeat_missing",
    },
  };

  try {
    await admin.messaging().sendEachForMulticast(message);
  } catch (error) {
    console.error(`[FCM] Failed to send heartbeat alert:`, error);
  }
}

/**
 * Send silent push to wake the iOS app for heartbeat.
 */
export async function sendSilentPush(userId: string): Promise<void> {
  const tokens = await getTokensForUser(userId);
  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    apns: {
      headers: {
        "apns-priority": "5",
        "apns-push-type": "background",
      },
      payload: {
        aps: {
          "content-available": 1,
        },
      },
    },
    data: {
      action: "heartbeat_wake",
    },
  };

  try {
    await admin.messaging().sendEachForMulticast(message);
  } catch (error) {
    console.error(`[FCM] Failed to send silent push:`, error);
  }
}

/**
 * Send SOS resolution notification to the protected person.
 */
export async function sendSOSResolvedNotification(
  protectedPersonId: string,
  resolvedByName: string
): Promise<void> {
  const tokens = await getTokensForUser(protectedPersonId);
  if (tokens.length === 0) return;

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: "守护者已接手",
      body: `${resolvedByName}已确认并接手处理`,
    },
    data: {
      action: "sos_resolved",
    },
  };

  try {
    await admin.messaging().sendEachForMulticast(message);
  } catch (error) {
    console.error(`[FCM] Failed to send SOS resolved notification:`, error);
  }
}
