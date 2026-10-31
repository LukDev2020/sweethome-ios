import * as admin from "firebase-admin";

const db = admin.firestore();

// Per-locale notification strings
const fcmStrings: Record<string, {
  sosTitle: string;
  sosBody: (name: string, loc?: string) => string;
  sosBattery: (pct: number) => string;
  checkinTitle: string;
  checkinBody: (name: string) => string;
  heartbeatTitle: string;
  heartbeatBody: (name: string, mins: number) => string;
  resolvedTitle: string;
  resolvedBody: (name: string) => string;
  homeSafeTitle: (name: string) => string;
  homeSafeBody: (city: string, time: string, note?: string) => string;
  ackOthersTitle: string;
  ackOthersBody: (guardian: string, person: string) => string;
  ackProtectedTitle: string;
  ackProtectedBody: (guardian: string) => string;
}> = {
  zh: {
    sosTitle: "紧急求助",
    sosBody: (name, loc) => `${name}正在求助${loc ? "，位于" + loc : ""}`,
    sosBattery: (pct) => `电量 ${pct}%`,
    checkinTitle: "报平安提醒",
    checkinBody: (name) => `${name}今天还没有报平安`,
    heartbeatTitle: "设备离线提醒",
    heartbeatBody: (name, mins) => `${name}的手机已 ${mins} 分钟未上报信号`,
    resolvedTitle: "守护者已接手",
    resolvedBody: (name) => `${name}已确认并接手处理`,
    homeSafeTitle: (name) => `${name}已平安到家`,
    homeSafeBody: (city, time, note) => [city, time].filter(Boolean).join(" · ") + (note ? `\n${note}` : ""),
    ackOthersTitle: "已有人接手",
    ackOthersBody: (g, p) => `${g}正在处理${p}的求助，自动呼叫已停止`,
    ackProtectedTitle: "家人已收到",
    ackProtectedBody: (g) => `${g}已收到你的求助，正在处理`,
  },
  en: {
    sosTitle: "Emergency SOS",
    sosBody: (name, loc) => `${name} is calling for help${loc ? " near " + loc : ""}`,
    sosBattery: (pct) => `battery ${pct}%`,
    checkinTitle: "Check-in Reminder",
    checkinBody: (name) => `${name} hasn't checked in today`,
    heartbeatTitle: "Device Offline",
    heartbeatBody: (name, mins) => `${name}'s phone has been offline for ${mins} minutes`,
    resolvedTitle: "Guardian Responded",
    resolvedBody: (name) => `${name} has acknowledged and taken over`,
    homeSafeTitle: (name) => `${name} is home safe`,
    homeSafeBody: (city, time, note) => [city, time].filter(Boolean).join(" · ") + (note ? `\n${note}` : ""),
    ackOthersTitle: "Someone is on it",
    ackOthersBody: (g, p) => `${g} is handling ${p}'s SOS — automatic calls stopped`,
    ackProtectedTitle: "Your family has it",
    ackProtectedBody: (g) => `${g} got your SOS and is responding`,
  },
  fr: {
    sosTitle: "SOS Urgence",
    sosBody: (name, loc) => `${name} demande de l'aide${loc ? " près de " + loc : ""}`,
    sosBattery: (pct) => `batterie ${pct} %`,
    checkinTitle: "Rappel de signal",
    checkinBody: (name) => `${name} n'a pas donné signe de vie aujourd'hui`,
    heartbeatTitle: "Appareil hors ligne",
    heartbeatBody: (name, mins) => `Le téléphone de ${name} est hors ligne depuis ${mins} minutes`,
    resolvedTitle: "Gardien a répondu",
    resolvedBody: (name) => `${name} a confirmé et pris en charge`,
    homeSafeTitle: (name) => `${name} est bien rentré(e)`,
    homeSafeBody: (city, time, note) => [city, time].filter(Boolean).join(" · ") + (note ? `\n${note}` : ""),
    ackOthersTitle: "Quelqu'un s'en occupe",
    ackOthersBody: (g, p) => `${g} gère le SOS de ${p} — appels automatiques arrêtés`,
    ackProtectedTitle: "Votre famille est là",
    ackProtectedBody: (g) => `${g} a reçu votre SOS et intervient`,
  },
};

function getStrings(locale: string) {
  const lang = (locale || "zh").substring(0, 2);
  return fcmStrings[lang] || fcmStrings.zh;
}

/**
 * Critical alerts need Apple's com.apple.developer.usernotifications.critical-alerts
 * entitlement. Until Apple grants it, SOS pushes use the time-sensitive
 * interruption level (entitlement shipped in the app). Flip with the
 * CRITICAL_ALERTS_ENABLED env var once the entitlement is approved.
 */
export function criticalAlertsEnabled(): boolean {
  return process.env.CRITICAL_ALERTS_ENABLED === "true";
}

/**
 * SOS APNs payload. Critical only when Apple has granted the entitlement
 * (CRITICAL_ALERTS_ENABLED) AND the guardian opted in to SOS critical alerts;
 * otherwise Time Sensitive.
 */
export function sosApsPayload(title: string, body: string, guardianOptedIn = true): Record<string, unknown> {
  const critical = criticalAlertsEnabled() && guardianOptedIn;
  return {
    // A critical alert needs the sound dictionary (critical: 1 in the APNs payload;
    // firebase-admin converts `true` to 1).
    sound: critical ? { critical: true, name: "sos_alert.caf", volume: 1.0 } : "sos_alert.caf",
    "interruption-level": critical ? "critical" : "time-sensitive",
    "relevance-score": 1.0,
    category: "SOS_ALERT",
    alert: { title, body },
  };
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

export interface SOSAlertDetails {
  protectedPersonId?: string;
  locationDescription?: string | null;
  batteryLevel?: number | null;
  latitude?: number | null;
  longitude?: number | null;
}

export async function sendSOSAlert(
  guardianId: string,
  protectedPersonName: string,
  sosEventId: string,
  detailsOrLocation?: SOSAlertDetails | string
): Promise<PushResult> {
  const details: SOSAlertDetails =
    typeof detailsOrLocation === "string"
      ? { locationDescription: detailsOrLocation }
      : detailsOrLocation ?? {};
  // SOS alerts ignore the sosAlerts preference on purpose: a guardian cannot
  // opt out of being told that someone they protect is calling for help.
  const tokens = await getTokensForUser(guardianId);
  if (tokens.length === 0) {
    console.warn(`[FCM] No tokens for guardian ${guardianId}`);
    return { successCount: 0, failureCount: 0, allFailed: true };
  }

  const locale = await getUserLocale(guardianId);
  const s = getStrings(locale);
  const battery = typeof details.batteryLevel === "number" && details.batteryLevel >= 0
    ? s.sosBattery(Math.round(details.batteryLevel * 100))
    : null;
  const body = [s.sosBody(protectedPersonName, details.locationDescription ?? undefined), battery]
    .filter(Boolean).join(" · ");
  // Guardians opt in to Critical Alerts when they join a circle and can turn
  // them off in the app; without consent the SOS is sent as Time Sensitive.
  const critical = await isNotifEnabled(guardianId, "sosCriticalAlerts");

  const message: admin.messaging.MulticastMessage = {
    tokens,
    notification: { title: s.sosTitle, body },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-push-type": "alert",
      },
      payload: { aps: sosApsPayload(s.sosTitle, body, critical) as admin.messaging.Aps },
    },
    data: {
      action: "sos_alert",
      sos_id: sosEventId,
      person_id: details.protectedPersonId ?? "",
      protected_person_name: protectedPersonName,
      ...(typeof details.batteryLevel === "number" && { battery: String(details.batteryLevel) }),
      ...(typeof details.latitude === "number" && typeof details.longitude === "number" && {
        lat: String(details.latitude),
        lng: String(details.longitude),
      }),
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

async function sendSimple(
  userId: string,
  title: string,
  body: string,
  data: Record<string, string>,
  aps: Record<string, unknown> = { sound: "default" }
): Promise<PushResult> {
  const tokens = await getTokensForUser(userId);
  if (tokens.length === 0) return { successCount: 0, failureCount: 0, allFailed: true };
  try {
    const r = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      apns: { payload: { aps: { ...aps, alert: { title, body } } as admin.messaging.Aps } },
      data,
    });
    return { successCount: r.successCount, failureCount: r.failureCount, allFailed: r.successCount === 0 };
  } catch (error) {
    console.error(`[FCM] push to ${userId} failed:`, error);
    return { successCount: 0, failureCount: tokens.length, allFailed: true };
  }
}

/**
 * "Mom is home safe · Chengdu 18:58" to a guardian (Home Safe / check-in).
 * Respects the guardian's checkinReminder (check-in notifications) preference.
 */
export async function sendHomeSafeNotification(
  guardianId: string,
  protectedPersonId: string,
  personName: string,
  city: string,
  localTime: string,
  note?: string
): Promise<boolean> {
  if (!(await isNotifEnabled(guardianId, "checkinReminder"))) return false;
  const s = getStrings(await getUserLocale(guardianId));
  const r = await sendSimple(guardianId, s.homeSafeTitle(personName), s.homeSafeBody(city, localTime, note), {
    action: "checkin_safe",
    person_id: protectedPersonId,
  });
  return !r.allFailed;
}

/** "Sarah is handling Mom's SOS — automatic calls stopped" to the other guardians. */
export async function sendSOSAcknowledgedToGuardian(
  guardianId: string,
  ackGuardianName: string,
  personName: string,
  sosEventId: string,
  protectedPersonId: string
): Promise<void> {
  const s = getStrings(await getUserLocale(guardianId));
  await sendSimple(guardianId, s.ackOthersTitle, s.ackOthersBody(ackGuardianName, personName), {
    action: "sos_acknowledged",
    sos_id: sosEventId,
    person_id: protectedPersonId,
  }, { sound: "default", "interruption-level": "time-sensitive" });
}

/** "Sarah got your SOS and is responding" to the person who raised it. */
export async function sendSOSAcknowledgedToProtected(
  protectedPersonId: string,
  ackGuardianName: string,
  sosEventId: string
): Promise<void> {
  const s = getStrings(await getUserLocale(protectedPersonId));
  await sendSimple(protectedPersonId, s.ackProtectedTitle, s.ackProtectedBody(ackGuardianName), {
    action: "sos_acknowledged",
    sos_id: sosEventId,
  }, { sound: "default", "interruption-level": "time-sensitive" });
}
