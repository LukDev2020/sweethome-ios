import * as fs from "fs";
import * as path from "path";
import { localeFromPhone, normalizeLocale } from "../services/locale";

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(() => ({ collection: jest.fn() }), { FieldValue: {}, Timestamp: {} }),
  initializeApp: jest.fn(),
}));
jest.mock("firebase-functions", () => ({ config: () => ({}) }));
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { getTwimlLanguage } = require("../services/twilio");

const src = (f: string) => fs.readFileSync(path.join(__dirname, "../services", f), "utf8");

describe("Japanese", () => {
  it.each([["ja", "ja"], ["ja-JP", "ja"], ["ja_JP", "ja"], ["jp", null]])("normalizeLocale(%s) → %s", (input, expected) => {
    expect(normalizeLocale(input)).toBe(expected);
  });

  it("voice calls use ja-JP", () => {
    expect(getTwimlLanguage("ja")).toBe("ja-JP");
  });

  it.each(["fcm.ts", "sms.ts", "twilio.ts"])("%s has a Japanese block", (file) => {
    const s = src(file);
    const i = s.indexOf("\n  ja: {");
    expect(i).toBeGreaterThan(0);
    expect(s.slice(i, i + 400)).toMatch(/[぀-ヿ]/); // kana
  });
});

describe("localeFromPhone (verification SMS before sign-up)", () => {
  it.each([
    ["+8613800138000", "zh"],
    ["+85291234567", "zh-Hant"], ["+85362123456", "zh-Hant"], ["+886912345678", "zh-Hant"],
    ["+819012345678", "ja"],
    ["+33612345678", "fr"],
    ["+14155551234", "en"], ["+6591234567", "en"], ["+61412345678", "en"], ["+64211234567", "en"],
    ["+60123456789", "en"], ["+66812345678", "en"], ["+639171234567", "en"],
    ["+1 (416) 555-0123", "en"],
  ])("%s → %s", (phone, expected) => {
    expect(localeFromPhone(phone)).toBe(expected);
  });
});
