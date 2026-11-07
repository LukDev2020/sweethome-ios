import { normalizeLocale } from "./locale";
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
  sosSafeTitle: (name: string) => string;
  sosSafeBody: string;
  routeTitle: (name: string) => string;
  routeBody: (place: string, mode: string) => string;
  crewSosTitle: (name: string) => string;
  crewSosBody: (distance: string | null) => string;
  crewGoingTitle: (name: string) => string;
  crewCantTitle: (name: string) => string;
  crewResponseBody: (distance: string | null) => string;
  shiftOverdueTitle: (name: string) => string;
  shiftOverdueBody: (minutes: number) => string;
  watchRequestTitle: (name: string) => string;
  watchRequestBody: string;
  watchBackTitle: (name: string) => string;
  watchBackBody: string;
  familyWatchRequestTitle: (name: string) => string;
  familyWatchRequestBody: string;
  familyWatchStartedTitle: (name: string) => string;
  familyWatchStartedBody: string;
  /** A guardian made a police report about this person (transparency) */
  incidentReportTitle: (name: string) => string;
  incidentReportBody: string;
  /** A fall was detected and they tapped "I'm OK" (to guardians) */
  fallDismissedTitle: (name: string) => string;
  fallDismissedBody: string;
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
    sosSafeTitle: (name) => `${name}已安全`,
    sosSafeBody: "她自己结束了求助。",
    routeTitle: (name) => `${name}正在前往`,
    routeBody: (place, mode) => `${place}（${mode === "driving" ? "开车" : mode === "transit" ? "公共交通" : "步行"}）· 打开守灯查看路线和实时位置`,
    crewSosTitle: (name) => `${name}需要帮助`,
    crewSosBody: (d) => `${d ? "距你 " + d + "，" : ""}先拨打急救电话，安全的话再过去帮忙`,
    crewGoingTitle: (name) => `${name}正在赶来`,
    crewCantTitle: (name) => `${name}无法过来`,
    crewResponseBody: (d) => d ? `距你 ${d}` : "车队成员已回应",
    shiftOverdueTitle: (name) => `${name}还没结束班次`,
    shiftOverdueBody: (m) => `计划下班已过 ${m} 分钟，还没有报平安。打个电话确认一下。`,
    watchRequestTitle: (name) => `${name}请你照看这次班次`,
    watchRequestBody: "如果班次超时未结束或发出求助，你会收到提醒。",
    watchBackTitle: (name) => `${name}也开始照看你的班次`,
    watchBackBody: "你们现在互相照看。",
    familyWatchRequestTitle: (name) => `${name}也想照看你`,
    familyWatchRequestBody: "同意后，你求助时 TA 也会收到提醒，并能看到你的位置。不额外收费。",
    familyWatchStartedTitle: (name) => `你现在也能照看${name}了`,
    familyWatchStartedBody: "TA 求助时你会收到提醒。",
    incidentReportTitle: (name) => `${name}生成了一份报警材料`,
    incidentReportBody: "其中包含你在所选时段的位置记录。可在「记录」中查看。",
    fallDismissedTitle: (name) => `${name}的手机检测到一次跌倒`,
    fallDismissedBody: "TA 已确认自己没事。",
  },
  "zh-Hant": {
    sosTitle: "緊急求助",
    sosBody: (name, loc) => `${name}正在求助${loc ? "，位於" + loc : ""}`,
    sosBattery: (pct) => `電量 ${pct}%`,
    checkinTitle: "報平安提醒",
    checkinBody: (name) => `${name}今天還沒有報平安`,
    heartbeatTitle: "裝置離線提醒",
    heartbeatBody: (name, mins) => `${name}的手機已 ${mins} 分鐘未上報訊號`,
    resolvedTitle: "守護者已接手",
    resolvedBody: (name) => `${name}已確認並接手處理`,
    homeSafeTitle: (name) => `${name}已平安到家`,
    homeSafeBody: (city, time, note) => [city, time].filter(Boolean).join(" · ") + (note ? `\n${note}` : ""),
    ackOthersTitle: "已有人接手",
    ackOthersBody: (g, p) => `${g}正在處理${p}的求助，自動呼叫已停止`,
    ackProtectedTitle: "家人已收到",
    ackProtectedBody: (g) => `${g}已收到你的求助，正在處理`,
    sosSafeTitle: (name) => `${name}已安全`,
    sosSafeBody: "她自己結束了求助。",
    routeTitle: (name) => `${name}正在前往`,
    routeBody: (place, mode) => `${place}（${mode === "driving" ? "開車" : mode === "transit" ? "大眾運輸" : "步行"}）· 打開守燈查看路線和即時位置`,
    crewSosTitle: (name) => `${name}需要幫助`,
    crewSosBody: (d) => `${d ? "距你 " + d + "，" : ""}先撥打緊急電話，安全的話再過去幫忙`,
    crewGoingTitle: (name) => `${name}正在趕來`,
    crewCantTitle: (name) => `${name}無法過來`,
    crewResponseBody: (d) => d ? `距你 ${d}` : "車隊成員已回應",
    shiftOverdueTitle: (name) => `${name}還沒結束班次`,
    shiftOverdueBody: (m) => `計畫下班已過 ${m} 分鐘，還沒有報平安。打個電話確認一下。`,
    watchRequestTitle: (name) => `${name}請你照看這次班次`,
    watchRequestBody: "如果班次超時未結束或發出求助，你會收到提醒。",
    watchBackTitle: (name) => `${name}也開始照看你的班次`,
    watchBackBody: "你們現在互相照看。",
    familyWatchRequestTitle: (name) => `${name}也想照看你`,
    familyWatchRequestBody: "同意後，你求助時對方也會收到提醒，並能看到你的位置。不額外收費。",
    familyWatchStartedTitle: (name) => `你現在也能照看${name}了`,
    familyWatchStartedBody: "對方求助時你會收到提醒。",
    incidentReportTitle: (name) => `${name}產生了一份報警資料`,
    incidentReportBody: "其中包含你在所選時段的位置紀錄。可在「紀錄」中查看。",
    fallDismissedTitle: (name) => `${name}的手機偵測到一次跌倒`,
    fallDismissedBody: "對方已確認自己沒事。",
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
    sosSafeTitle: (name) => `${name} is safe`,
    sosSafeBody: "They ended the SOS themselves.",
    routeTitle: (name) => `${name} is heading to`,
    routeBody: (place, mode) => `${place} (${mode === "driving" ? "driving" : mode === "transit" ? "public transport" : "on foot"}) · open Lantern Care for the route and live location`,
    crewSosTitle: (name) => `${name} needs help`,
    crewSosBody: (d) => `${d ? d + " away · " : ""}Call emergency services first, then go only if it's safe`,
    crewGoingTitle: (name) => `${name} is on the way`,
    crewCantTitle: (name) => `${name} can't come`,
    crewResponseBody: (d) => d ? `${d} away` : "Your crew answered",
    shiftOverdueTitle: (name) => `${name} hasn't ended their shift`,
    shiftOverdueBody: (m) => `${m} min past the planned end with no check-in. Give them a call.`,
    watchRequestTitle: (name) => `${name} asked you to watch their shift`,
    watchRequestBody: "You'll be alerted if they call SOS or the shift runs late.",
    watchBackTitle: (name) => `${name} is watching your shifts too`,
    watchBackBody: "You now look out for each other.",
    familyWatchRequestTitle: (name) => `${name} would like to watch over you too`,
    familyWatchRequestBody: "If you agree, they're alerted when you call SOS and can see your location. No extra charge.",
    familyWatchStartedTitle: (name) => `You can now watch over ${name} too`,
    familyWatchStartedBody: "You'll be alerted if they call SOS.",
    incidentReportTitle: (name) => `${name} created a police report about you`,
    incidentReportBody: "It includes your location history for the chosen period. See Records.",
    fallDismissedTitle: (name) => `${name}'s phone detected a fall`,
    fallDismissedBody: "They confirmed they're OK.",
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
    sosSafeTitle: (name) => `${name} est en sécurité`,
    sosSafeBody: "La personne a mis fin au SOS elle-même.",
    routeTitle: (name) => `${name} se rend à`,
    routeBody: (place, mode) => `${place} (${mode === "driving" ? "en voiture" : mode === "transit" ? "en transports" : "à pied"}) · ouvrez Lantern Care pour l'itinéraire et la position en direct`,
    crewSosTitle: (name) => `${name} a besoin d'aide`,
    crewSosBody: (d) => `${d ? "À " + d + " · " : ""}Appelez d'abord les secours, puis allez-y seulement si c'est sûr`,
    crewGoingTitle: (name) => `${name} arrive`,
    crewCantTitle: (name) => `${name} ne peut pas venir`,
    crewResponseBody: (d) => d ? `À ${d}` : "Votre équipe a répondu",
    shiftOverdueTitle: (name) => `${name} n'a pas terminé son service`,
    shiftOverdueBody: (m) => `${m} min après la fin prévue, sans signe de vie. Appelez pour vérifier.`,
    watchRequestTitle: (name) => `${name} vous demande de veiller sur son service`,
    watchRequestBody: "Vous serez prévenu en cas de SOS ou si le service se prolonge.",
    watchBackTitle: (name) => `${name} veille aussi sur vos services`,
    watchBackBody: "Vous veillez désormais l'un sur l'autre.",
    familyWatchRequestTitle: (name) => `${name} aimerait aussi veiller sur vous`,
    familyWatchRequestBody: "Si vous acceptez, cette personne est prévenue en cas de SOS et voit votre position. Sans frais en plus.",
    familyWatchStartedTitle: (name) => `Vous pouvez aussi veiller sur ${name}`,
    familyWatchStartedBody: "Vous serez prévenu en cas de SOS.",
    incidentReportTitle: (name) => `${name} a créé un rapport pour la police vous concernant`,
    incidentReportBody: "Il contient votre historique de position pour la période choisie. Voir Historique.",
    fallDismissedTitle: (name) => `Le téléphone de ${name} a détecté une chute`,
    fallDismissedBody: "Cette personne a confirmé qu'elle va bien.",
  },
  ja: {
    sosTitle: "緊急SOS",
    sosBody: (name, loc) => `${name}さんが助けを求めています${loc ? "（" + loc + "付近）" : ""}`,
    sosBattery: (pct) => `バッテリー残量 ${pct}%`,
    checkinTitle: "無事報告のお知らせ",
    checkinBody: (name) => `${name}さんから今日の無事報告がまだありません`,
    heartbeatTitle: "端末がオフラインです",
    heartbeatBody: (name, mins) => `${name}さんのスマートフォンが${mins}分間オフラインです`,
    resolvedTitle: "見守る人が対応しました",
    resolvedBody: (name) => `${name}さんが確認し、対応を引き継ぎました`,
    homeSafeTitle: (name) => `${name}さんが無事に帰宅しました`,
    homeSafeBody: (city, time, note) => [city, time].filter(Boolean).join(" · ") + (note ? `\n${note}` : ""),
    ackOthersTitle: "対応中の人がいます",
    ackOthersBody: (g, p) => `${g}さんが${p}さんのSOSに対応しています。自動発信は停止しました`,
    ackProtectedTitle: "家族に届きました",
    ackProtectedBody: (g) => `${g}さんがあなたのSOSを受け取り、対応しています`,
    sosSafeTitle: (name) => `${name}さんは無事です`,
    sosSafeBody: "本人がSOSを終了しました。",
    routeTitle: (name) => `${name}さんが向かっています`,
    routeBody: (place, mode) => `${place}（${mode === "driving" ? "車" : mode === "transit" ? "公共交通" : "徒歩"}）· Lantern Care でルートと現在地を確認できます`,
    crewSosTitle: (name) => `${name}さんが助けを求めています`,
    crewSosBody: (d) => `${d ? d + "先 · " : ""}まず緊急番号に電話し、安全な場合のみ向かってください`,
    crewGoingTitle: (name) => `${name}さんが向かっています`,
    crewCantTitle: (name) => `${name}さんは行けません`,
    crewResponseBody: (d) => d ? `${d}先` : "クルーが応答しました",
    shiftOverdueTitle: (name) => `${name}さんのシフトが終わっていません`,
    shiftOverdueBody: (m) => `予定の終了から${m}分過ぎても安否報告がありません。電話で確認してください。`,
    watchRequestTitle: (name) => `${name}さんがシフトの見守りを頼んでいます`,
    watchRequestBody: "SOS やシフトの延長があれば通知します。",
    watchBackTitle: (name) => `${name}さんもあなたのシフトを見守ります`,
    watchBackBody: "お互いに見守る関係になりました。",
    familyWatchRequestTitle: (name) => `${name}さんもあなたを見守りたいそうです`,
    familyWatchRequestBody: "同意すると、SOS のときに通知が届き、位置も見えるようになります。追加料金はありません。",
    familyWatchStartedTitle: (name) => `${name}さんのことも見守れるようになりました`,
    familyWatchStartedBody: "SOS があれば通知が届きます。",
    incidentReportTitle: (name) => `${name}さんが警察向けの報告書を作成しました`,
    incidentReportBody: "選んだ期間のあなたの位置記録が含まれます。「記録」で確認できます。",
    fallDismissedTitle: (name) => `${name}さんのスマホが転倒を検知しました`,
    fallDismissedBody: "ご本人が大丈夫だと確認しました。",
  },
};

function getStrings(locale: string) {
  // normalizeLocale keeps "zh-Hant" (Hong Kong, Macao, Taiwan) apart from "zh".
  const lang = normalizeLocale(locale) ?? "zh";
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

/** "Mom is safe — she ended the SOS herself" to each guardian. */
export async function sendSOSEndedByPersonNotification(
  guardianId: string, personName: string, sosEventId: string, protectedPersonId: string
): Promise<void> {
  const s = getStrings(await getUserLocale(guardianId));
  await sendSimple(guardianId, s.sosSafeTitle(personName), s.sosSafeBody, {
    action: "sos_resolved_by_person", sos_id: sosEventId, person_id: protectedPersonId,
  }, { sound: "default", "interruption-level": "time-sensitive" });
}

/** "Mom is heading to the hospital (on foot)" to each guardian during an SOS. */
export async function sendSOSRouteNotification(
  guardianId: string, personName: string, place: string, mode: string, sosEventId: string, protectedPersonId: string
): Promise<void> {
  const s = getStrings(await getUserLocale(guardianId));
  await sendSimple(guardianId, s.routeTitle(personName), s.routeBody(place, mode), {
    action: "sos_route", sos_id: sosEventId, person_id: protectedPersonId,
  }, { sound: "default", "interruption-level": "time-sensitive" });
}

/** "1.2 km" / "350 m" */
export function formatDistance(meters: number | null): string | null {
  if (meters === null || !Number.isFinite(meters)) return null;
  return meters >= 1000 ? `${(meters / 1000).toFixed(1)} km` : `${Math.max(10, Math.round(meters / 10) * 10)} m`;
}

/** A crew mate called SOS: Critical (when allowed) like a guardian's SOS alert. */
export async function sendCrewSOSAlert(
  memberId: string, riderName: string, distanceM: number | null,
  info: { sosEventId: string; riderId: string; latitude?: number; longitude?: number }
): Promise<PushResult> {
  const s = getStrings(await getUserLocale(memberId));
  const title = s.crewSosTitle(riderName);
  const body = s.crewSosBody(formatDistance(distanceM));
  const critical = await isNotifEnabled(memberId, "sosCriticalAlerts");
  return sendSimple(memberId, title, body, {
    action: "crew_sos", sos_id: info.sosEventId, rider_id: info.riderId, rider_name: riderName,
    ...(typeof info.latitude === "number" && typeof info.longitude === "number" && {
      lat: String(info.latitude), lng: String(info.longitude),
    }),
  }, sosApsPayload(title, body, critical));
}

/** "Wei is on the way · 220 m away" to the rider who called SOS. */
export async function sendCrewResponseNotification(
  riderId: string, memberName: string, response: "going" | "cant_help", distanceM: number | null, sosEventId: string
): Promise<void> {
  const s = getStrings(await getUserLocale(riderId));
  const title = response === "going" ? s.crewGoingTitle(memberName) : s.crewCantTitle(memberName);
  await sendSimple(riderId, title, s.crewResponseBody(formatDistance(distanceM)), {
    action: "crew_response", sos_id: sosEventId,
  }, { sound: "default", "interruption-level": "time-sensitive" });
}

/** A shift ran past its planned end with no check-in. */
export async function sendShiftOverdueNotification(toId: string, riderName: string, minutes: number, riderId: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.shiftOverdueTitle(riderName), s.shiftOverdueBody(minutes), {
    action: "shift_overdue", rider_id: riderId,
  }, { sound: "default", "interruption-level": "time-sensitive" });
}

/** A rider chose you to watch their shift. */
export async function sendShiftWatchRequest(toId: string, riderName: string, riderId: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.watchRequestTitle(riderName), s.watchRequestBody, { action: "shift_watch", rider_id: riderId });
}

/** A crew mate now watches your shifts too. */
export async function sendWatchBackNotification(toId: string, name: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.watchBackTitle(name), s.watchBackBody, { action: "watch_back" });
}

/** The person you look after would like to watch over you too (accept in the app). */
export async function sendFamilyWatchRequest(toId: string, name: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.familyWatchRequestTitle(name), s.familyWatchRequestBody, { action: "watch_back_request" });
}

/** You can now watch over your guardian too. */
export async function sendFamilyWatchStarted(toId: string, name: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.familyWatchStartedTitle(name), s.familyWatchStartedBody, { action: "watch_back_started" });
}

/** Transparency: the person is told whenever someone makes a police report about them. */
export async function sendIncidentReportCreated(toId: string, reporterName: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.incidentReportTitle(reporterName), s.incidentReportBody, { action: "incident_report_created" });
}

/** A detected fall that the person dismissed: guardians still hear about it, quietly. */
export async function sendFallDismissed(toId: string, personName: string): Promise<void> {
  const s = getStrings(await getUserLocale(toId));
  await sendSimple(toId, s.fallDismissedTitle(personName), s.fallDismissedBody, { action: "fall_dismissed" });
}
