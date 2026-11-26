import * as admin from "firebase-admin";
import { dutySlotsByGuardian } from "./escalation";
import { getDocsById } from "./batchRead";
import { localTime, onDutyAt } from "./localTime";
import { toIso } from "./time";

/**
 * What a new guardian may see until the person changes it. One source for the
 * permission screen and the status a guardian gets (guardian.ts reads a missing
 * value the same way: location/battery on, phone activity and health off).
 */
export const DEFAULT_LINK_PERMISSIONS = {
  canSeeLocation: true,
  canSeeBattery: true,
  canSeeHealth: false,
  canSeePhoneActivity: false,
  canHearEmergencyAudio: false,
};

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
  const guardianIds = linksSnapshot.docs.map((d) => d.data().guardianId as string);
  // Everyone's profile in one read, and every duty slot in one query
  const [users, slotsOf] = await Promise.all([
    getDocsById("users", [personId, ...guardianIds]),
    dutySlotsByGuardian(personId),
  ]);
  const personTimeZone = users.get(personId)?.timeZone;
  const t = localTime(new Date(), personTimeZone);

  for (const linkDoc of linksSnapshot.docs) {
    const link = linkDoc.data();
    const guardianId = link.guardianId;

    const user = users.get(guardianId);
    if (!user) continue;

    // Duty hours are the protected person's local hours (the server runs in UTC).
    // No schedule = always on duty (as onDutyGuardians).
    const dutySlots = slotsOf.get(guardianId) ?? [];
    const isOnDuty = dutySlots.length === 0 || onDutyAt(dutySlots, t);

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
        // Last time they used the app ("who's online" on the person's home)
        lastActiveAt: toIso(user.lastActiveAt),
      },
      permissions: link.permissions || DEFAULT_LINK_PERMISSIONS,
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
