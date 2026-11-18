/**
 * Push text for the alerts sent from routes and scheduled jobs (arrival, home
 * timer, silent alarm, Bluetooth tag), in the recipient's language. The larger
 * table for SOS and check-ins lives in services/fcm.ts.
 */
import * as admin from "firebase-admin";
import { Lang, userLang } from "./locale";

export interface AlertCopy {
  /** Stands in for a missing display name */
  someone: string;
  arrivalTitle: string;
  arrivalBody: (name: string, place?: string) => string;
  homeTimerOverdueTitle: string;
  homeTimerOverdueBody: (name: string, label?: string) => string;
  destinationLine: (place: string) => string;
  routeLine: (route: string) => string;
  homeTimerDismissedTitle: string;
  homeTimerDismissedBody: (name: string) => string;
  silentAlarmTitle: string;
  silentAlarmBody: (name: string) => string;
  silentAlarmTimeline: string;
  bleSeparationTitle: string;
  bleSeparationBody: (tag: string) => string;
}

const COPY: Record<Lang, AlertCopy> = {
  zh: {
    someone: "你的家人",
    arrivalTitle: "到达报告",
    arrivalBody: (n, p) => `${n}已安全到达${p ? "「" + p + "」" : ""}`,
    homeTimerOverdueTitle: "回家计时器超时",
    homeTimerOverdueBody: (n, l) => l ? `${n}设置的「${l}」计时已到期，但还没有关闭` : `${n}的回家计时器已超时`,
    destinationLine: (p) => `目的地：${p}`,
    routeLine: (r) => `路线：${r}`,
    homeTimerDismissedTitle: "已安全到达",
    homeTimerDismissedBody: (n) => `${n}已关闭回家计时器`,
    silentAlarmTitle: "沉默报警触发",
    silentAlarmBody: (n) => `${n}连续多次未确认安全签到，请立即确认其状况。`,
    silentAlarmTimeline: "沉默报警已升级，已通知所有守护者",
    bleSeparationTitle: "分离提醒",
    bleSeparationBody: (t) => `蓝牙标签「${t}」已超出范围`,
  },
  "zh-Hant": {
    someone: "你的家人",
    arrivalTitle: "到達報告",
    arrivalBody: (n, p) => `${n}已安全到達${p ? "「" + p + "」" : ""}`,
    homeTimerOverdueTitle: "回家計時器逾時",
    homeTimerOverdueBody: (n, l) => l ? `${n}設定的「${l}」計時已到期，但還沒有關閉` : `${n}的回家計時器已逾時`,
    destinationLine: (p) => `目的地：${p}`,
    routeLine: (r) => `路線：${r}`,
    homeTimerDismissedTitle: "已安全到達",
    homeTimerDismissedBody: (n) => `${n}已關閉回家計時器`,
    silentAlarmTitle: "靜默警報觸發",
    silentAlarmBody: (n) => `${n}連續多次未確認安全簽到，請立即確認其狀況。`,
    silentAlarmTimeline: "靜默警報已升級，已通知所有守護者",
    bleSeparationTitle: "分離提醒",
    bleSeparationBody: (t) => `藍牙標籤「${t}」已超出範圍`,
  },
  en: {
    someone: "Your family member",
    arrivalTitle: "Arrived",
    arrivalBody: (n, p) => `${n} arrived safely${p ? " at " + p : ""}`,
    homeTimerOverdueTitle: "Home timer overdue",
    homeTimerOverdueBody: (n, l) => l ? `${n}'s "${l}" timer ran out and hasn't been turned off` : `${n}'s home timer ran out`,
    destinationLine: (p) => `Destination: ${p}`,
    routeLine: (r) => `Route: ${r}`,
    homeTimerDismissedTitle: "Arrived safely",
    homeTimerDismissedBody: (n) => `${n} turned off the home timer`,
    silentAlarmTitle: "Silent alarm",
    silentAlarmBody: (n) => `${n} missed several safety check-ins in a row. Please check on them now.`,
    silentAlarmTimeline: "Silent alarm escalated; all guardians notified",
    bleSeparationTitle: "Tag left behind",
    bleSeparationBody: (t) => `Bluetooth tag "${t}" is out of range`,
  },
  fr: {
    someone: "Votre proche",
    arrivalTitle: "Bien arrivé",
    arrivalBody: (n, p) => `${n} est bien arrivé·e${p ? " à " + p : ""}`,
    homeTimerOverdueTitle: "Minuteur de retour dépassé",
    homeTimerOverdueBody: (n, l) => l ? `Le minuteur « ${l} » de ${n} est écoulé et n'a pas été arrêté` : `Le minuteur de retour de ${n} est écoulé`,
    destinationLine: (p) => `Destination : ${p}`,
    routeLine: (r) => `Itinéraire : ${r}`,
    homeTimerDismissedTitle: "Bien arrivé",
    homeTimerDismissedBody: (n) => `${n} a arrêté le minuteur de retour`,
    silentAlarmTitle: "Alarme silencieuse",
    silentAlarmBody: (n) => `${n} n'a pas confirmé plusieurs pointages de sécurité d'affilée. Vérifiez sans attendre.`,
    silentAlarmTimeline: "Alarme silencieuse déclenchée ; tous les gardiens ont été prévenus",
    bleSeparationTitle: "Balise oubliée",
    bleSeparationBody: (t) => `La balise Bluetooth « ${t} » est hors de portée`,
  },
  ja: {
    someone: "ご家族",
    arrivalTitle: "到着報告",
    arrivalBody: (n, p) => `${n}さんが${p ? "「" + p + "」に" : ""}無事到着しました`,
    homeTimerOverdueTitle: "帰宅タイマー超過",
    homeTimerOverdueBody: (n, l) => l ? `${n}さんの「${l}」タイマーが終了しましたが、まだ止められていません` : `${n}さんの帰宅タイマーが終了しました`,
    destinationLine: (p) => `目的地：${p}`,
    routeLine: (r) => `ルート：${r}`,
    homeTimerDismissedTitle: "無事到着",
    homeTimerDismissedBody: (n) => `${n}さんが帰宅タイマーを止めました`,
    silentAlarmTitle: "サイレントアラーム",
    silentAlarmBody: (n) => `${n}さんが安全確認に続けて応答していません。今すぐ様子を確認してください。`,
    silentAlarmTimeline: "サイレントアラームを発動し、すべての見守り役に通知しました",
    bleSeparationTitle: "置き忘れ通知",
    bleSeparationBody: (t) => `Bluetoothタグ「${t}」が範囲外になりました`,
  },
};

export function alertCopy(lang: Lang): AlertCopy {
  return COPY[lang] ?? COPY.zh;
}

/** The copy in this user's language (their stored locale) */
export async function alertCopyFor(userId: string): Promise<AlertCopy> {
  const doc = await admin.firestore().collection("users").doc(userId).get();
  return alertCopy(userLang(doc.data()));
}

/** The person's name, or "your family member" in the recipient's language */
export function nameOr(name: unknown, copy: AlertCopy): string {
  return typeof name === "string" && name.trim() ? name.trim() : copy.someone;
}
