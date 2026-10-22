import * as admin from "firebase-admin";

const db = admin.firestore();

// Per-locale notification strings
const fcmStrings: Record<string, {
  sosTitle: string;
  sosBody: (name: string, loc?: string) => string;
  checkinTitle: string;
  checkinBody: (name: string) => string;
  heartbeatTitle: string;
  heartbeatBody: (name: string, mins: number) => string;
  resolvedTitle: string;
  resolvedBody: (name: string) => string;
}> = {
  zh: {
    sosTitle: "紧急求助",
    sosBody: (name, loc) => `${name}正在求助${loc ? "，位于" + loc : ""}`,
    checkinTitle: "报平安提醒",
    checkinBody: (name) => `${name}今天还没有报平安`,
    heartbeatTitle: "设备离线提醒",
    heartbeatBody: (name, mins) => `${name}的手机已 ${mins} 分钟未上报信号`,
    resolvedTitle: "守护者已接手",
    resolvedBody: (name) => `${name}已确认并接手处理`,
  },
  en: {
    sosTitle: "Emergency SOS",
    sosBody: (name, loc) => `${name} is calling for help${loc ? " near " + loc : ""}`,
    checkinTitle: "Check-in Reminder",
    checkinBody: (name) => `${name} hasn't checked in today`,
    heartbeatTitle: "Device Offline",
    heartbeatBody: (name, mins) => `${name}'s phone has been offline for ${mins} minutes`,
    resolvedTitle: "Guardian Responded",
    resolvedBody: (name) => `${name} has acknowledged and taken over`,
  },
  fr: {
    sosTitle: "SOS Urgence",
    sosBody: (name, loc) => `${name} demande de l'aide${loc ? " près de " + loc : ""}`,
    checkinTitle: "Rappel de signal",
    checkinBody: (name) => `${name} n'a pas donné signe de vie aujourd'hui`,
    heartbeatTitle: "Appareil hors ligne",
    heartbeatBody: (name, mins) => `Le téléphone de ${name} est hors ligne depuis ${mins} minutes`,
    resolvedTitle: "Gardien a répondu",
    resolvedBody: (name) => `${name} a confirmé et pris en charge`,
  },
};

function getStrings(locale: string) {
  const lang = (locale || "zh").substring(0, 2);
  return fcmStrings[lang] || fcmStrings.zh;
}

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
 * Get user's preferred locale (defaults to "zh").
 */
async function getUserLocale(userId: string): Promise<string> {
  const userDoc = await db.collection("users").doc(userId).get();
  return userDoc.exists ? userDoc.data()?.locale || "zh" : "zh";
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
/**
 * Result of a push send attempt. Used by callers to decide whether
 * to fall back to SMS.
 */
export interface PushResult {
  successCount: number;
  failureCount: number;
  allFailed: boolean;
}

export async function sendSOSAlert(
  guardianId: string,
  protectedPersonName: string,
  sosEventId: string,
  locationDescription?: string
): Promise<PushResult> {
  const tokens = await getTokensForUser(guardianId);
  if (tokens.length === 0) {
    console.warn(`[FCM] No tokens for guardian ${guardianId}`);
    return { successCount: 0, failureCount: 0, allFailed: true };
  }

  const locale = await getUserLocale(guardianId);
  const s = getStrings(locale);

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: s.sosTitle,
      body: s.sosBody(protectedPersonName, locationDescription),
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
            title: s.sosTitle,
            body: s.sosBody(protectedPersonName),
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

    // Clean up invalid tokens (unregistered, invalid argument)
    const invalidTokenErrors = ["messaging/registration-token-not-registered", "messaging/invalid-argument"];
    const tokensToRemove: string[] = [];
    response.responses.forEach((resp, idx) => {
      if (resp.error && invalidTokenErrors.includes(resp.error.code)) {
        tokensToRemove.push(tokens[idx]);
      }
    });
    if (tokensToRemove.length > 0) {
      const batch = db.batch();
      for (const badToken of tokensToRemove) {
        const snap = await db.collection("device_tokens")
          .where("token", "==", badToken)
          .limit(1)
          .get();
        snap.docs.forEach((doc) => batch.delete(doc.ref));
      }
      await batch.commit();
      console.log(`[FCM] Cleaned up ${tokensToRemove.length} invalid tokens for ${guardianId}`);
    }

    return {
      successCount: response.successCount,
      failureCount: response.failureCount,
      allFailed: response.successCount === 0,
    };
  } catch (error) {
    console.error(`[FCM] Failed to send SOS alert to ${guardianId}:`, error);
    return { successCount: 0, failureCount: tokens.length, allFailed: true };
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

  const locale = await getUserLocale(guardianId);
  const s = getStrings(locale);

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: s.checkinTitle,
      body: s.checkinBody(protectedPersonName),
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

  const locale = await getUserLocale(guardianId);
  const s = getStrings(locale);

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: s.heartbeatTitle,
      body: s.heartbeatBody(protectedPersonName, lastSeenMinutes),
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

  const locale = await getUserLocale(protectedPersonId);
  const s = getStrings(locale);

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: s.resolvedTitle,
      body: s.resolvedBody(resolvedByName),
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
