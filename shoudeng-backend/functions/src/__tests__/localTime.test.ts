import { localTime, onDutyAt, slotCoversHour, hhmm, isValidTimeZone } from "../services/localTime";

describe("localTime", () => {
  it("uses the given zone, not the server's", () => {
    const d = new Date("2026-10-30T03:00:00Z");
    expect(localTime(d, "Asia/Shanghai")).toMatchObject({ hour: 11, minute: 0, isoWeekday: 5, date: "2026-10-30" });
    expect(localTime(d, "America/Toronto")).toMatchObject({ hour: 23, isoWeekday: 4, date: "2026-10-29" });
    expect(hhmm(new Date("2026-10-30T10:58:00Z"), "Asia/Shanghai")).toBe("18:58");
  });

  it("falls back to UTC for invalid zones", () => {
    expect(isValidTimeZone("Mars/Olympus")).toBe(false);
    expect(localTime(new Date("2026-10-30T03:00:00Z"), "Mars/Olympus").hour).toBe(3);
  });
});

describe("duty slots", () => {
  it("supports 23:00-24:00", () => {
    expect(slotCoversHour({ startHour: 23, endHour: 24 }, 23)).toBe(true);
    expect(slotCoversHour({ startHour: 23, endHour: 24 }, 0)).toBe(false);
  });

  it("overnight 22→6 stored on Monday covers Mon 23:00 and Tue 05:00, not Tue 22:00", () => {
    const slots = [{ dayOfWeek: 1, startHour: 22, endHour: 6 }];
    expect(onDutyAt(slots, { isoWeekday: 1, hour: 23 })).toBe(true);
    expect(onDutyAt(slots, { isoWeekday: 2, hour: 5 })).toBe(true);
    expect(onDutyAt(slots, { isoWeekday: 2, hour: 6 })).toBe(false);
    expect(onDutyAt(slots, { isoWeekday: 1, hour: 5 })).toBe(false);
    expect(onDutyAt(slots, { isoWeekday: 2, hour: 22 })).toBe(false);
  });

  it("Sunday overnight wraps into Monday", () => {
    expect(onDutyAt([{ dayOfWeek: 7, startHour: 20, endHour: 2 }], { isoWeekday: 1, hour: 1 })).toBe(true);
  });
});
