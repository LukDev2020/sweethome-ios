import * as admin from "firebase-admin";

/**
 * "Who's online" on the protected person's home: when each guardian last used the
 * app. Every authenticated request counts, but a user is written at most once per
 * THROTTLE_MS per server instance, and never in a way that can fail the request.
 */
export const THROTTLE_MS = 5 * 60 * 1000;
const lastWrite = new Map<string, number>();

export function shouldTouch(uid: string, now = Date.now()): boolean {
  const prev = lastWrite.get(uid);
  if (prev !== undefined && now - prev < THROTTLE_MS) return false;
  if (lastWrite.size > 50000) lastWrite.clear();
  lastWrite.set(uid, now);
  return true;
}

export function touchLastActive(uid: string): void {
  if (!uid || !shouldTouch(uid)) return;
  try {
    admin.firestore().collection("users").doc(uid)
      .update({ lastActiveAt: admin.firestore.FieldValue.serverTimestamp() })
      .catch(() => { /* a missing user doc or a blip: not worth failing anything */ });
  } catch {
    // Admin not initialised (unit tests): nothing to record
  }
}
