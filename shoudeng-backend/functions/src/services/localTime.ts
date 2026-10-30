/**
 * Wall-clock time in a given IANA time zone. Cloud Functions run in UTC, so
 * `Date#getHours()` is the server's hour, not the protected person's — which
 * decided who was "on duty" for an SOS.
 */
export function isValidTimeZone(tz: unknown): tz is string {
  if (typeof tz !== "string" || tz.length === 0 || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

export interface LocalTime {
  hour: number;      // 0-23
  minute: number;    // 0-59
  /** ISO weekday: 1 = Monday … 7 = Sunday */
  isoWeekday: number;
  /** YYYY-MM-DD in that zone */
  date: string;
}

const WEEKDAYS: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };

export function localTime(date: Date, timeZone: string | null | undefined): LocalTime {
  const tz = isValidTimeZone(timeZone) ? timeZone : "UTC";
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, hourCycle: "h23", weekday: "short",
    year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit",
  }).formatToParts(date);
  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? "";
  return {
    hour: Number(get("hour")) % 24,
    minute: Number(get("minute")),
    isoWeekday: WEEKDAYS[get("weekday")] ?? 1,
    date: `${get("year")}-${get("month")}-${get("day")}`,
  };
}

/** "18:58" in the given zone. */
export function hhmm(date: Date, timeZone: string | null | undefined): string {
  const t = localTime(date, timeZone);
  return `${String(t.hour).padStart(2, "0")}:${String(t.minute).padStart(2, "0")}`;
}

export interface DutySlot {
  startHour: number;  // 0-23
  endHour: number;    // 1-24; endHour < startHour means the slot runs past midnight
}

/**
 * Is `hour` (local, 0-23) inside the slot? Supports 23:00–24:00 (end = 24) and
 * overnight shifts such as 22→6.
 */
export function slotCoversHour(slot: DutySlot, hour: number): boolean {
  const { startHour: s, endHour: e } = slot;
  if (s === e) return false;
  if (s < e) return hour >= s && hour < e;
  return hour >= s || hour < e; // wraps midnight
}

/**
 * Duty slots are stored per ISO weekday. An overnight slot stored on Monday
 * (22→6) also covers Tuesday 00:00–06:00.
 */
export function onDutyAt(
  slots: (DutySlot & { dayOfWeek: number })[],
  t: Pick<LocalTime, "hour" | "isoWeekday">
): boolean {
  const yesterday = t.isoWeekday === 1 ? 7 : t.isoWeekday - 1;
  return slots.some((slot) => {
    const wraps = slot.endHour < slot.startHour;
    if (slot.dayOfWeek === t.isoWeekday) {
      return wraps ? t.hour >= slot.startHour : slotCoversHour(slot, t.hour);
    }
    if (wraps && slot.dayOfWeek === yesterday) return t.hour < slot.endHour;
    return false;
  });
}
