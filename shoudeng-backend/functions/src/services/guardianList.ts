import * as admin from "firebase-admin";
import { onDutyGuardians } from "./escalation";
import { toIso } from "./time";

const db = admin.firestore();

export function isoToCalendarWeekday(iso: number): number {
  return (iso % 7) + 1; // Mon 1 → 2 … Sat 6 → 7, Sun 7 → 1
}

/**
 * Everyone who actively guards `personId`, with their duty schedule, in the shape
 * of the iOS `Guardian` model. Used by the person (GET /v1/protected/guardians) and
 * by their guardians (GET /v1/guardian/circle: who else looks after her, and when).
 * No phone numbers.
 */
export async function guardiansOf(personId: string): Promise<Record<string, unknown>[]> {
  const linksSnapshot = await db
    .collection("guardian_links")
    .where("protectedPersonId", "==", personId)
    .where("status", "==", "active")
    .get();
  if (linksSnapshot.empty) return [];

  const guardians: Record<string, unknown>[] = [];
  const personTimeZone = (await db.collection("users").doc(personId).get()).data()?.timeZone;

  for (const linkDoc of linksSnapshot.docs) {
    const link = linkDoc.data();
    const guardianId = link.guardianId;

    const userDoc = await db.collection("users").doc(guardianId).get();
    if (!userDoc.exists) continue;
    const user = userDoc.data()!;

    // Duty hours are the protected person's local hours (the server runs in UTC)
    const isOnDuty = (await onDutyGuardians(personId, [guardianId], personTimeZone, new Date())).length > 0;

    const scheduleSnapshot = await db
      .collection("duty_schedules")
      .where("guardianId", "==", guardianId)
      .where("protectedPersonId", "==", personId)
      .where("isActive", "==", true)
      .get();
    const dutySlots = scheduleSnapshot.docs.map((d) => d.data());

    guardians.push({
      id: guardianId,
      user: {
        id: guardianId,
        displayName: user.displayName,
        role: "guardian",
        avatarInitial: user.avatarInitial ?? String(user.displayName ?? "").charAt(0),
        timeZone: user.timeZone ?? null,
        countryCode: user.countryCode ?? "",
        cityName: user.cityName ?? "",
        createdAt: toIso(user.createdAt),
      },
      permissions: link.permissions || {
        canSeeLocation: true,
        canSeeBattery: true,
        canSeeHealth: false,
        canSeePhoneActivity: false,
        canHearEmergencyAudio: true,
      },
      isOnDuty,
      dutySchedule: dutySlots.length > 0
        ? {
            guardianId,
            slots: dutySlots.map((s) => ({
              startHour: s.startHour,
              endHour: s.endHour,
              // Stored as ISO weekday (1 = Mon … 7 = Sun); iOS DutySlot uses
              // Calendar weekdays (1 = Sun … 7 = Sat)
              dayOfWeek: [isoToCalendarWeekday(s.dayOfWeek)],
              isConfirmed: true,
            })),
          }
        : null,
      averageResponseTime: 120, // Default 2 minutes, would be computed from history
      linkedSince: toIso(link.createdAt) ?? new Date(0).toISOString(),
    });
  }
  return guardians;
}
