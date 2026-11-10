/**
 * Push notifications to a user's devices, straight through APNs (services/apns.ts).
 *
 * Messages keep the shape the code used with FCM (notification + aps + data), and
 * are turned into the payload FCM used to send to Apple: `aps.alert` from the
 * notification, data keys at the top level, `sound.critical` as 1.
 */
import * as admin from "firebase-admin";
import { sendApns, apnsEnvironment, ApnsEnvironment, ApnsNotification, ApnsResult, APNS_MAX_PAYLOAD_BYTES } from "./apns";

/**
 * Result of a push send attempt. Used by callers to decide whether
 * to fall back to SMS.
 */
export interface PushResult {
  successCount: number;
  failureCount: number;
  allFailed: boolean;
}

export interface PushMessage {
  /** Shown as `aps.alert` unless `aps.alert` is set */
  notification?: { title: string; body: string };
  aps?: Record<string, unknown>;
  /** Custom keys, at the top level of the payload (as FCM sent them) */
  data?: Record<string, string>;
  /** Default: "background" for a content-available-only push, else "alert" */
  pushType?: "alert" | "background";
  /** Default: 5 for background pushes (Apple requires it), else 10 */
  priority?: 10 | 5;
}

/** Alerts wait up to a day for a phone that's off; a background wake is stale after an hour. */
const ALERT_TTL_SECONDS = 24 * 60 * 60;
const BACKGROUND_TTL_SECONDS = 60 * 60;

export function buildApnsNotification(msg: PushMessage, nowSeconds = Math.floor(Date.now() / 1000)): ApnsNotification {
  const aps: Record<string, unknown> = { ...(msg.aps ?? {}) };
  if (msg.notification && aps.alert === undefined) {
    aps.alert = { title: msg.notification.title, body: msg.notification.body };
  }
  // APNs wants `critical: 1`; firebase-admin used to convert `true` for us.
  if (aps.sound && typeof aps.sound === "object") {
    const sound = { ...(aps.sound as Record<string, unknown>) };
    if (typeof sound.critical === "boolean") sound.critical = sound.critical ? 1 : 0;
    aps.sound = sound;
  }
  const backgroundOnly = aps.alert === undefined && aps["content-available"] === 1;
  const pushType = msg.pushType ?? (backgroundOnly ? "background" : "alert");
  const priority = msg.priority ?? (pushType === "background" ? 5 : 10);
  const payload: Record<string, unknown> = { ...(msg.data ?? {}), aps };
  fitPayload(payload);
  return {
    payload,
    pushType,
    priority,
    expiration: nowSeconds + (pushType === "background" ? BACKGROUND_TTL_SECONDS : ALERT_TTL_SECONDS),
  };
}

/** Shortens the alert body (free text, e.g. route notes) so the payload fits Apple's 4 KB. */
function fitPayload(payload: Record<string, unknown>): void {
  const size = () => Buffer.byteLength(JSON.stringify(payload), "utf8");
  const alert = (payload.aps as Record<string, unknown>).alert as { body?: string } | undefined;
  if (size() <= APNS_MAX_PAYLOAD_BYTES || !alert || typeof alert.body !== "string") return;
  let chars = [...alert.body];
  while (chars.length > 0 && size() > APNS_MAX_PAYLOAD_BYTES) {
    chars = chars.slice(0, Math.max(0, chars.length - Math.max(16, Math.ceil(chars.length / 10))));
    alert.body = chars.join("") + "…";
  }
}

interface Device {
  ref: admin.firestore.DocumentReference;
  token: string;
  environment: ApnsEnvironment;
}

async function devicesForUser(userId: string): Promise<Device[]> {
  const snapshot = await admin.firestore()
    .collection("device_tokens")
    .where("userId", "==", userId)
    .get();
  return snapshot.docs
    .map((doc) => ({ ref: doc.ref, token: doc.data().token, environment: apnsEnvironment(doc.data().environment) }))
    .filter((d) => typeof d.token === "string" && d.token.length > 0);
}

/** Delete a dead token, unless the phone registered a new one in the meantime. */
async function removeDeadToken(device: Device): Promise<void> {
  const current = await device.ref.get();
  if (current.exists && current.data()?.token === device.token) await device.ref.delete();
}

async function afterSend(userId: string, label: string, device: Device, r: ApnsResult): Promise<void> {
  try {
    if (r.ok && r.environment !== device.environment) {
      await device.ref.update({ environment: r.environment === "sandbox" ? "development" : "production" });
    } else if (r.unregistered) {
      await removeDeadToken(device);
      console.log(`[Push] removed ${label} token of ${userId} (${r.status || "-"} ${r.reason ?? ""})`.trim());
    }
  } catch (error) {
    console.warn(`[Push] token bookkeeping for ${userId} failed:`, error);
  }
}

/**
 * Send to every registered device of a user. Never throws.
 * `allFailed` is true when nothing was delivered (including "no device").
 */
export async function sendPushToUser(userId: string, msg: PushMessage, label = "push"): Promise<PushResult> {
  let devices: Device[];
  try {
    devices = await devicesForUser(userId);
  } catch (error) {
    console.error(`[Push] could not read device tokens of ${userId}:`, error);
    return { successCount: 0, failureCount: 0, allFailed: true };
  }
  if (devices.length === 0) return { successCount: 0, failureCount: 0, allFailed: true };

  const notification = buildApnsNotification(msg);
  const results = await Promise.all(devices.map((d) => sendApns(d.token, d.environment, notification)));
  await Promise.all(devices.map((d, i) => afterSend(userId, label, d, results[i])));

  const successCount = results.filter((r) => r.ok).length;
  const failures = results.filter((r) => !r.ok);
  if (failures.length > 0 && failures.some((r) => r.reason !== "NotConfigured")) {
    console.warn(`[Push] ${label} to ${userId}: ${successCount} delivered, ${failures.length} failed (` +
      failures.map((r) => `${r.status || "-"} ${r.reason ?? ""}`.trim()).join("; ") + ")");
  }
  return { successCount, failureCount: failures.length, allFailed: successCount === 0 };
}
