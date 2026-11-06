import * as admin from "firebase-admin";
import { activeSOSDoc } from "./escalation";

// ---------------------------------------------------------------------------
// Live location during an SOS
// ---------------------------------------------------------------------------
//
// The SOS used to keep only the trigger-time position, so the guardian's map stayed
// where the SOS started. While an SOS is open, every location report now moves the
// SOS position and adds to its trail (thinned: a point every 15 s or 15 m, at most
// 300 — about an hour of walking at full detail).

export const TRAIL_MAX_POINTS = 300;
export const TRAIL_MIN_GAP_MS = 15_000;
export const TRAIL_MIN_MOVE_M = 15;

export interface TrailPoint { latitude: number; longitude: number; at: string }

const db = () => admin.firestore();

/** Metres between two coordinates (haversine). */
export function distanceMeters(a: { latitude: number; longitude: number }, b: { latitude: number; longitude: number }): number {
  const r = 6_371_000;
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLng = rad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

/** Whether a new point is worth keeping in the trail. */
export function shouldAppend(last: TrailPoint | undefined, next: TrailPoint): boolean {
  if (!last) return true;
  const gap = Date.parse(next.at) - Date.parse(last.at);
  return gap >= TRAIL_MIN_GAP_MS || distanceMeters(last, next) >= TRAIL_MIN_MOVE_M;
}

const isCoordinate = (lat: unknown, lng: unknown): lat is number =>
  typeof lat === "number" && typeof lng === "number" && Number.isFinite(lat) && Number.isFinite(lng) &&
  Math.abs(lat) <= 90 && Math.abs(lng as number) <= 180;

/**
 * Move the person's open SOS (if any) to this position. Returns whether an SOS was
 * updated. Never throws into the location report.
 */
export async function recordSOSLocation(
  userId: string, latitude: unknown, longitude: unknown, at: Date = new Date()
): Promise<boolean> {
  if (!isCoordinate(latitude, longitude)) return false;
  try {
    const doc = await activeSOSDoc(userId);
    if (!doc) return false;
    const trail: TrailPoint[] = Array.isArray(doc.data()?.trail) ? doc.data()!.trail : [];
    const point: TrailPoint = { latitude, longitude: longitude as number, at: at.toISOString() };
    const update: Record<string, unknown> = {
      latitude,
      longitude,
      locationUpdatedAt: admin.firestore.Timestamp.fromDate(at),
    };
    if (shouldAppend(trail[trail.length - 1], point)) {
      update.trail = [...trail, point].slice(-TRAIL_MAX_POINTS);
    }
    await doc.ref.update(update);
    return true;
  } catch (error) {
    console.warn("[SOS] live location update failed:", error);
    return false;
  }
}

// ---------------------------------------------------------------------------
// A route the person shared during the SOS ("going to the hospital")
// ---------------------------------------------------------------------------

export const ROUTE_MODES = ["walking", "driving", "transit"] as const;
export type RouteMode = typeof ROUTE_MODES[number];

export interface SharedRoute {
  name: string;
  latitude: number;
  longitude: number;
  mode: RouteMode;
  sharedAt: string;
}

/** Validates the body of POST /v1/sos/route; null when invalid. */
export function parseRoute(body: Record<string, unknown>, now: Date = new Date()): SharedRoute | null {
  const name = typeof body.name === "string" ? body.name.trim().slice(0, 120) : "";
  const mode = (ROUTE_MODES as readonly string[]).includes(body.mode as string) ? body.mode as RouteMode : "walking";
  if (!name || !isCoordinate(body.latitude, body.longitude)) return null;
  return { name, latitude: body.latitude as number, longitude: body.longitude as number, mode, sharedAt: now.toISOString() };
}

/** Active guardians of a person (for SOS route / "safe" notices). */
export async function activeGuardianIds(personId: string): Promise<string[]> {
  const snap = await db().collection("guardian_links")
    .where("protectedPersonId", "==", personId).where("status", "==", "active").get();
  return snap.docs.map((d) => d.data().guardianId as string);
}
