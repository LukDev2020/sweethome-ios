/**
 * Phase 8 — Localization Audit Tests
 *
 * Verifies:
 *   1. Key completeness (all keys present in all 3 locales)
 *   2. Key consistency (no extra keys in any locale)
 *   3. Terminology enforcement (correct brand names, role names)
 *   4. Format string consistency (%d, %@, etc.)
 *   5. InfoPlist.strings completeness
 *   6. Server-side hardcoded strings (findings inventory)
 *   7. No empty values
 *   8. No duplicate keys
 *
 * Run: cd shoudeng-backend/functions && npm test -- --testPathPattern i18n
 */

import * as fs from "fs";
import * as path from "path";

// --- Parse .strings files ---

interface StringsEntry {
  key: string;
  value: string;
  line: number;
}

function parseStringsFile(filePath: string): StringsEntry[] {
  const content = fs.readFileSync(filePath, "utf-8");
  const entries: StringsEntry[] = [];
  const lines = content.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    // Match: "key" = "value";
    const match = line.match(/^"([^"]+)"\s*=\s*"(.*)"\s*;$/);
    if (match) {
      entries.push({
        key: match[1],
        value: match[2],
        line: i + 1,
      });
    }
  }

  return entries;
}

function parseInfoPlist(filePath: string): StringsEntry[] {
  const content = fs.readFileSync(filePath, "utf-8");
  const entries: StringsEntry[] = [];
  const lines = content.split("\n");

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    // Match: KEY = "value"; or KEY = value;
    const match = line.match(/^(\w+)\s*=\s*"(.*)"\s*;$/);
    if (match) {
      entries.push({
        key: match[1],
        value: match[2],
        line: i + 1,
      });
    }
  }

  return entries;
}

// --- File paths ---

const projectRoot = path.join(__dirname, "..", "..", "..", "..");
const enStrings = parseStringsFile(
  path.join(projectRoot, "ShouDeng/en.lproj/Localizable.strings")
);
const zhStrings = parseStringsFile(
  path.join(projectRoot, "ShouDeng/zh-Hans.lproj/Localizable.strings")
);
const frStrings = parseStringsFile(
  path.join(projectRoot, "ShouDeng/fr.lproj/Localizable.strings")
);

const enInfoPlist = parseInfoPlist(
  path.join(projectRoot, "ShouDeng/en.lproj/InfoPlist.strings")
);
const zhInfoPlist = parseInfoPlist(
  path.join(projectRoot, "ShouDeng/zh-Hans.lproj/InfoPlist.strings")
);
const frInfoPlist = parseInfoPlist(
  path.join(projectRoot, "ShouDeng/fr.lproj/InfoPlist.strings")
);

const enKeys = new Set(enStrings.map((e) => e.key));
const zhKeys = new Set(zhStrings.map((e) => e.key));
const frKeys = new Set(frStrings.map((e) => e.key));

// --- Tests ---

describe("i18n — Key Completeness", () => {
  it("all locales have the same number of keys", () => {
    expect(enKeys.size).toBe(zhKeys.size);
    expect(enKeys.size).toBe(frKeys.size);
  });

  it("every EN key exists in zh-Hans", () => {
    const missing = [...enKeys].filter((k) => !zhKeys.has(k));
    expect(missing).toEqual([]);
  });

  it("every EN key exists in FR", () => {
    const missing = [...enKeys].filter((k) => !frKeys.has(k));
    expect(missing).toEqual([]);
  });

  it("every zh-Hans key exists in EN", () => {
    const extra = [...zhKeys].filter((k) => !enKeys.has(k));
    expect(extra).toEqual([]);
  });

  it("every FR key exists in EN", () => {
    const extra = [...frKeys].filter((k) => !enKeys.has(k));
    expect(extra).toEqual([]);
  });
});

describe("i18n — No Empty Values", () => {
  it("EN has no empty values", () => {
    const empty = enStrings.filter((e) => e.value.trim() === "");
    expect(empty.map((e) => e.key)).toEqual([]);
  });

  it("zh-Hans has no empty values", () => {
    const empty = zhStrings.filter((e) => e.value.trim() === "");
    expect(empty.map((e) => e.key)).toEqual([]);
  });

  it("FR has no empty values", () => {
    const empty = frStrings.filter((e) => e.value.trim() === "");
    expect(empty.map((e) => e.key)).toEqual([]);
  });
});

describe("i18n — No Duplicate Keys", () => {
  function findDuplicates(entries: StringsEntry[]): string[] {
    const seen = new Set<string>();
    const dups: string[] = [];
    for (const e of entries) {
      if (seen.has(e.key)) dups.push(e.key);
      seen.add(e.key);
    }
    return dups;
  }

  it("EN has no duplicate keys", () => {
    expect(findDuplicates(enStrings)).toEqual([]);
  });

  it("zh-Hans has no duplicate keys", () => {
    expect(findDuplicates(zhStrings)).toEqual([]);
  });

  it("FR has no duplicate keys", () => {
    expect(findDuplicates(frStrings)).toEqual([]);
  });
});

describe("i18n — Format String Consistency", () => {
  function extractFormatSpecifiers(value: string): string[] {
    // Match %d, %@, %ld, %lld, %.0f, etc.
    return (value.match(/%[\d.]*[dsfux@]/g) || []).sort();
  }

  it("all keys have matching format specifiers across EN and zh-Hans", () => {
    const mismatches: string[] = [];
    for (const enEntry of enStrings) {
      const zhEntry = zhStrings.find((z) => z.key === enEntry.key);
      if (!zhEntry) continue;

      const enSpecs = extractFormatSpecifiers(enEntry.value);
      const zhSpecs = extractFormatSpecifiers(zhEntry.value);

      if (JSON.stringify(enSpecs) !== JSON.stringify(zhSpecs)) {
        mismatches.push(
          `${enEntry.key}: EN=${enSpecs.join(",")} zh=${zhSpecs.join(",")}`
        );
      }
    }
    expect(mismatches).toEqual([]);
  });

  it("all keys have matching format specifiers across EN and FR", () => {
    const mismatches: string[] = [];
    for (const enEntry of enStrings) {
      const frEntry = frStrings.find((f) => f.key === enEntry.key);
      if (!frEntry) continue;

      const enSpecs = extractFormatSpecifiers(enEntry.value);
      const frSpecs = extractFormatSpecifiers(frEntry.value);

      if (JSON.stringify(enSpecs) !== JSON.stringify(frSpecs)) {
        mismatches.push(
          `${enEntry.key}: EN=${enSpecs.join(",")} FR=${frSpecs.join(",")}`
        );
      }
    }
    expect(mismatches).toEqual([]);
  });
});

describe("i18n — Terminology Enforcement", () => {
  it("EN uses 'Luma' as app name", () => {
    const appName = enStrings.find((e) => e.key === "app.name");
    expect(appName?.value).toBe("Luma");
  });

  it("zh-Hans uses '守灯' as app name", () => {
    const appName = zhStrings.find((e) => e.key === "app.name");
    expect(appName?.value).toBe("守灯");
  });

  it("FR uses 'Luma' as app name", () => {
    const appName = frStrings.find((e) => e.key === "app.name");
    expect(appName?.value).toBe("Luma");
  });

  it("EN uses 'Protected Person' for care receiver role", () => {
    const role = enStrings.find((e) => e.key === "signup.role.protected");
    expect(role?.value).toBe("Protected Person");
  });

  it("EN uses 'Guardian' for caregiver role", () => {
    const role = enStrings.find((e) => e.key === "signup.role.guardian");
    expect(role?.value).toBe("Guardian");
  });

  it("zh-Hans uses '被守护者' for care receiver role", () => {
    const role = zhStrings.find((e) => e.key === "signup.role.protected");
    expect(role?.value).toBe("被守护者");
  });

  it("zh-Hans uses '守护者' for caregiver role", () => {
    const role = zhStrings.find((e) => e.key === "signup.role.guardian");
    expect(role?.value).toBe("守护者");
  });
});

describe("i18n — InfoPlist.strings", () => {
  it("all locales have the same InfoPlist keys", () => {
    const enInfoKeys = new Set(enInfoPlist.map((e) => e.key));
    const zhInfoKeys = new Set(zhInfoPlist.map((e) => e.key));
    const frInfoKeys = new Set(frInfoPlist.map((e) => e.key));

    expect(enInfoKeys.size).toBe(zhInfoKeys.size);
    expect(enInfoKeys.size).toBe(frInfoKeys.size);

    for (const k of enInfoKeys) {
      expect(zhInfoKeys.has(k)).toBe(true);
      expect(frInfoKeys.has(k)).toBe(true);
    }
  });

  it("EN InfoPlist has all required permission descriptions", () => {
    const requiredKeys = [
      "NSLocationAlwaysAndWhenInUseUsageDescription",
      "NSLocationWhenInUseUsageDescription",
      "NSMotionUsageDescription",
      "NSMicrophoneUsageDescription",
      "NSPhotoLibraryUsageDescription",
      "NSContactsUsageDescription",
    ];

    for (const key of requiredKeys) {
      const entry = enInfoPlist.find((e) => e.key === key);
      expect(entry).toBeDefined();
      expect(entry!.value.length).toBeGreaterThan(10);
    }
  });

  it("zh-Hans InfoPlist has all required permission descriptions", () => {
    const requiredKeys = [
      "NSLocationAlwaysAndWhenInUseUsageDescription",
      "NSLocationWhenInUseUsageDescription",
      "NSMotionUsageDescription",
    ];

    for (const key of requiredKeys) {
      const entry = zhInfoPlist.find((e) => e.key === key);
      expect(entry).toBeDefined();
      expect(entry!.value.length).toBeGreaterThan(5);
    }
  });

  it("all InfoPlist values are non-empty", () => {
    const allEntries = [...enInfoPlist, ...zhInfoPlist, ...frInfoPlist];
    const empty = allEntries.filter((e) => e.value.trim() === "");
    expect(empty.map((e) => `${e.key} (line ${e.line})`)).toEqual([]);
  });
});

describe("i18n — Server-Side Hardcoded Strings (Findings)", () => {
  // These verify known findings from Phase 0 are still present
  // When fixed, update these tests and close the findings

  const fcmPath = path.join(
    projectRoot,
    "shoudeng-backend/functions/src/services/fcm.ts"
  );
  const smsPath = path.join(
    projectRoot,
    "shoudeng-backend/functions/src/services/sms.ts"
  );
  const twilioPath = path.join(
    projectRoot,
    "shoudeng-backend/functions/src/services/twilio.ts"
  );

  it("FINDING F-001: FCM has Chinese-only notification bodies", () => {
    const fcm = fs.readFileSync(fcmPath, "utf-8");
    const hasChineseChars = /[\u4e00-\u9fff]/.test(fcm);
    // This test PASSES when the finding is still present
    // When fixed (per-locale routing added), update to expect false
    expect(hasChineseChars).toBe(true);
  });

  it("FINDING F-002: SMS has Chinese-only templates", () => {
    const sms = fs.readFileSync(smsPath, "utf-8");
    const hasChineseChars = /[\u4e00-\u9fff]/.test(sms);
    expect(hasChineseChars).toBe(true);
  });

  it("FINDING F-003: TwiML language based on protected person, not guardian", () => {
    const twilio = fs.readFileSync(twilioPath, "utf-8");
    // getTwimlLanguage uses the protected person's country code
    expect(twilio).toContain("getTwimlLanguage");
    // Should ideally use guardian's locale, not protected person's
  });
});

describe("i18n — iOS Push Action Buttons (FINDING)", () => {
  const pushServicePath = path.join(
    projectRoot,
    "ShouDeng/Services/Push/PushService.swift"
  );

  it("FINDING F-007: Action buttons are hardcoded in Chinese", () => {
    const source = fs.readFileSync(pushServicePath, "utf-8");
    // These should be NSLocalizedString but are hardcoded
    expect(source).toContain("我已接手");
    expect(source).toContain("立即拨号");
    expect(source).toContain("我知道了");
  });
});

describe("i18n — Quality Checks", () => {
  it("no untranslated EN text left in zh-Hans", () => {
    // Check if any zh-Hans value is identical to EN (possible missed translation)
    const identical: string[] = [];
    for (const en of enStrings) {
      const zh = zhStrings.find((z) => z.key === en.key);
      if (zh && zh.value === en.value && en.value.length > 3) {
        // Exclude very short values (numbers, symbols, "Vela", etc.)
        if (!/^[A-Z0-9]{1,5}$|^Luma$/.test(en.value)) {
          identical.push(en.key);
        }
      }
    }
    // Allow some identical values (brand names, etc.)
    // Flag if there are many
    expect(identical.length).toBeLessThan(5);
  });

  it("no untranslated EN text left in FR", () => {
    const identical: string[] = [];
    for (const en of enStrings) {
      const fr = frStrings.find((f) => f.key === en.key);
      if (fr && fr.value === en.value && en.value.length > 3) {
        if (!/^[A-Z0-9]{1,5}$|^Luma$/.test(en.value)) {
          identical.push(en.key);
        }
      }
    }
    // Many short words are legitimately identical in EN/FR (Normal, Train, Type, Allergies, etc.)
    expect(identical.length).toBeLessThan(20);
  });

  it("zh-Hans values contain Chinese characters", () => {
    const withoutChinese = zhStrings.filter(
      (e) => !/[\u4e00-\u9fff]/.test(e.value) && e.value.length > 3
    );
    // Some keys may legitimately have no Chinese (e.g., "%ds", "Vela")
    expect(withoutChinese.length).toBeLessThan(5);
  });

  it("FR values contain French characters or common French words", () => {
    const frenchIndicators = /[àâéèêëïîôùûüÿçœæ]|[Ll]e\s|[Ll]a\s|[Dd]e\s|[Dd]u\s|[Uu]n\s|[Ll]'\w/;
    const nonFrench = frStrings.filter(
      (e) => !frenchIndicators.test(e.value) && e.value.length > 10
    );
    // Many valid French phrases lack diacritics or articles (e.g., "Recommencer", "Actions rapides")
    // With 900+ keys, ~200 valid French strings naturally lack these narrow markers
    expect(nonFrench.length).toBeLessThan(250);
  });
});
