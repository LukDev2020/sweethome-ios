import * as fs from "fs";
import * as path from "path";
import { normalizeLocale } from "../services/locale";

jest.mock("firebase-admin", () => ({
  firestore: Object.assign(() => ({ collection: jest.fn() }), { FieldValue: {}, Timestamp: {} }),
  initializeApp: jest.fn(),
}));
jest.mock("firebase-functions", () => ({ config: () => ({}) }));
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { getTwimlLanguage } = require("../services/twilio");

const src = (f: string) => fs.readFileSync(path.join(__dirname, "../services", f), "utf8");

describe("Traditional Chinese (Hong Kong, Macao, Taiwan)", () => {
  it.each([
    ["zh-Hant", "zh-Hant"], ["zh-Hant-HK", "zh-Hant"], ["zh_TW", "zh-Hant"], ["zh-HK", "zh-Hant"],
    ["zh-MO", "zh-Hant"], ["zh-Hans", "zh"], ["zh_CN", "zh"], ["zh", "zh"], ["en-SG", "en"], ["fr-CA", "fr"],
  ])("normalizeLocale(%s) → %s", (input, expected) => {
    expect(normalizeLocale(input)).toBe(expected);
  });

  it("voice calls use Mandarin (Taiwan) for zh-Hant", () => {
    expect(getTwimlLanguage("zh-Hant")).toBe("cmn-TW");
  });

  it.each(["fcm.ts", "sms.ts", "twilio.ts"])("%s has Traditional copy and keeps zh-Hant apart", (file) => {
    const s = src(file);
    const block = s.slice(s.indexOf('"zh-Hant": {'), s.indexOf('"zh-Hant": {') + 600);
    expect(s).toContain('"zh-Hant": {');
    // Traditional-only characters, and none of their Simplified forms
    expect(block).toMatch(/[請緊護裝話時]/);
    expect(block).not.toMatch(/[请紧护装话时]/);
  });

  it("push and SMS copy selection does not truncate zh-Hant to zh", () => {
    expect(src("fcm.ts")).toContain('normalizeLocale(locale) ?? "zh"');
    expect(src("sms.ts")).toContain('normalizeLocale(locale) ?? "zh"');
  });
});
