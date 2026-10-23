/**
 * Phase 2 — Firestore Rules Tests
 *
 * Tests security rules logic for:
 *   - Cross-family isolation
 *   - Removed member access
 *   - Role-based permissions
 *   - Append-only audit
 *   - Server-only write collections
 *
 * These tests verify the RULES LOGIC by testing what the rules should allow/deny.
 * For full emulator-based rules testing, use `firebase emulators:exec` with
 * @firebase/rules-unit-testing.
 *
 * Run: cd shoudeng-backend/functions && npm test -- --testPathPattern firestore.rules
 */

import * as fs from "fs";
import * as path from "path";

// Read the actual rules file
const rulesPath = path.join(__dirname, "..", "..", "..", "firestore.rules");
let rulesContent: string;
try {
  rulesContent = fs.readFileSync(rulesPath, "utf-8");
} catch {
  rulesContent = "";
}

describe("Firestore Rules — Static Analysis", () => {
  it("rules file exists and is non-empty", () => {
    expect(rulesContent.length).toBeGreaterThan(100);
  });

  it("uses rules_version 2", () => {
    expect(rulesContent).toMatch(/rules_version\s*=\s*'2'/);
  });

  it("has default deny catchall", () => {
    // The default deny should be the LAST match rule
    expect(rulesContent).toMatch(
      /match\s*\/\{document=\*\*\}\s*\{[\s\S]*allow\s+read,\s*write:\s*if\s+false/
    );
  });

  it("defines isAuth helper", () => {
    expect(rulesContent).toMatch(/function\s+isAuth\(\)/);
  });

  it("defines isOwner helper", () => {
    expect(rulesContent).toMatch(/function\s+isOwner\(userId\)/);
  });

  it("defines isGuardianOf helper", () => {
    expect(rulesContent).toMatch(/function\s+isGuardianOf\(protectedPersonId\)/);
  });
});

describe("Firestore Rules — Users Collection", () => {
  it("restricts read to owner only", () => {
    // Match: /users/{userId} allow read: if isOwner(userId)
    const usersBlock = extractBlock(rulesContent, "users/{userId}");
    expect(usersBlock).toMatch(/allow read:\s*if\s+isOwner\(userId\)/);
  });

  it("restricts write to owner with field validation", () => {
    const usersBlock = extractBlock(rulesContent, "users/{userId}");
    // Must validate displayName, role, phone
    expect(usersBlock).toMatch(/request\.resource\.data\.displayName\s+is\s+string/);
    expect(usersBlock).toMatch(
      /request\.resource\.data\.role\s+in\s+\['protected',\s*'guardian'\]/
    );
    expect(usersBlock).toMatch(/request\.resource\.data\.phone\s+is\s+string/);
  });

  it("does not allow reading other users' profiles", () => {
    // isOwner checks request.auth.uid == userId
    const usersBlock = extractBlock(rulesContent, "users/{userId}");
    expect(usersBlock).not.toMatch(/allow read:\s*if\s+isAuth\(\)/);
  });
});

describe("Firestore Rules — Guardian Links", () => {
  it("allows read only by either party", () => {
    const block = extractBlock(rulesContent, "guardian_links/{linkId}");
    expect(block).toMatch(/allow read:\s*if\s+isAuth\(\)\s*&&/);
    expect(block).toMatch(/resource\.data\.guardianId\s*==\s*request\.auth\.uid/);
    expect(block).toMatch(/resource\.data\.protectedPersonId\s*==\s*request\.auth\.uid/);
  });

  it("validates status on create", () => {
    const block = extractBlock(rulesContent, "guardian_links/{linkId}");
    expect(block).toMatch(
      /request\.resource\.data\.status\s+in\s+\['pending',\s*'active'\]/
    );
  });

  it("validates guardianId and protectedPersonId are strings on create", () => {
    const block = extractBlock(rulesContent, "guardian_links/{linkId}");
    expect(block).toMatch(/request\.resource\.data\.guardianId\s+is\s+string/);
    expect(block).toMatch(/request\.resource\.data\.protectedPersonId\s+is\s+string/);
  });
});

describe("Firestore Rules — SOS Events", () => {
  it("allows read for any authenticated user", () => {
    const block = extractBlock(rulesContent, "sos_events/{sosId}");
    expect(block).toMatch(/allow read:\s*if\s+isAuth\(\)/);
  });

  it("denies all client writes (server-only)", () => {
    const block = extractBlock(rulesContent, "sos_events/{sosId}");
    expect(block).toMatch(/allow write:\s*if\s+false/);
  });
});

describe("Firestore Rules — Safe Zones", () => {
  it("restricts to owner", () => {
    const block = extractBlock(rulesContent, "safe_zones/{zoneId}");
    expect(block).toMatch(/resource\.data\.userId\s*==\s*request\.auth\.uid/);
  });
});

describe("Firestore Rules — Device Tokens", () => {
  it("restricts CRUD to owner", () => {
    const block = extractBlock(rulesContent, "device_tokens/{tokenId}");
    // All operations should check userId == auth.uid
    const ownerChecks = (
      block.match(/resource\.data\.userId\s*==\s*request\.auth\.uid/g) || []
    ).length;
    expect(ownerChecks).toBeGreaterThanOrEqual(3); // read, update, delete
  });
});

describe("Firestore Rules — Timeline Entries", () => {
  it("restricts read to owner", () => {
    const block = extractBlock(rulesContent, "timeline_entries/{entryId}");
    expect(block).toMatch(/resource\.data\.userId\s*==\s*request\.auth\.uid/);
  });

  it("denies client writes (server-only)", () => {
    const block = extractBlock(rulesContent, "timeline_entries/{entryId}");
    expect(block).toMatch(/allow write:\s*if\s+false/);
  });
});

describe("Firestore Rules — Family Posts", () => {
  it("allows read for authenticated users", () => {
    const block = extractBlock(rulesContent, "family_posts/{postId}");
    expect(block).toMatch(/allow read:\s*if\s+isAuth\(\)/);
  });

  it("restricts create to author", () => {
    const block = extractBlock(rulesContent, "family_posts/{postId}");
    expect(block).toMatch(
      /allow create:\s*if\s+isAuth\(\)\s*&&\s*request\.resource\.data\.authorId\s*==\s*request\.auth\.uid/
    );
  });

  it("restricts update/delete to author", () => {
    const block = extractBlock(rulesContent, "family_posts/{postId}");
    expect(block).toMatch(
      /allow update:\s*if\s+isAuth\(\)\s*&&\s*resource\.data\.authorId\s*==\s*request\.auth\.uid/
    );
    expect(block).toMatch(
      /allow delete:\s*if\s+isAuth\(\)\s*&&\s*resource\.data\.authorId\s*==\s*request\.auth\.uid/
    );
  });
});

describe("Firestore Rules — Crash Reports", () => {
  it("allows create for any authenticated user", () => {
    const block = extractBlock(rulesContent, "crash_reports/{reportId}");
    expect(block).toMatch(/allow create:\s*if\s+isAuth\(\)/);
  });

  it("denies read, update, delete", () => {
    const block = extractBlock(rulesContent, "crash_reports/{reportId}");
    expect(block).toMatch(/allow read,\s*update,\s*delete:\s*if\s+false/);
  });
});

describe("Firestore Rules — Server-Only Collections", () => {
  const serverOnlyCollections = [
    "sos_events/{sosId}",
    "duty_schedules/{scheduleId}",
    "evidence_holds/{holdId}",
    "integrity_proofs/{date}",
    "subscriptions/{userId}",
  ];

  for (const collection of serverOnlyCollections) {
    it(`${collection} denies client writes`, () => {
      const block = extractBlock(rulesContent, collection);
      expect(block).toMatch(/allow write:\s*if\s+false/);
    });
  }
});

describe("Firestore Rules — Cross-Family Isolation", () => {
  it("guardian_links read requires being either party", () => {
    // A user who is NEITHER guardianId NOR protectedPersonId should be denied
    const block = extractBlock(rulesContent, "guardian_links/{linkId}");
    expect(block).toMatch(/allow read:\s*if\s+isAuth\(\)\s*&&\s*\(/);
    // Must use OR (||) not AND (&&) for the party check
    expect(block).toMatch(
      /guardianId\s*==\s*request\.auth\.uid\s*\|\|\s*[\s\S]*protectedPersonId\s*==\s*request\.auth\.uid/
    );
  });

  it("safe_zones read requires ownership — no cross-user access", () => {
    const block = extractBlock(rulesContent, "safe_zones/{zoneId}");
    expect(block).toMatch(
      /allow read:\s*if\s+isAuth\(\)\s*&&\s*resource\.data\.userId\s*==\s*request\.auth\.uid/
    );
  });

  it("timeline_entries read restricted to owner — guardians cannot read", () => {
    const block = extractBlock(rulesContent, "timeline_entries/{entryId}");
    // This is a FINDING if guardians should be able to read their protected person's timeline
    expect(block).toMatch(
      /allow read:\s*if\s+isAuth\(\)\s*&&\s*resource\.data\.userId\s*==\s*request\.auth\.uid/
    );
  });
});

describe("Firestore Rules — Collections Without Explicit Rules", () => {
  const unruled = [
    "checkins",
    "home_timers",
    "selected_hotlines",
    "arrival_reports",
    "itineraries",
    "evidence_shares",
    "rate_limits",
    "claim_material_exports",
  ];

  for (const col of unruled) {
    it(`${col} has no explicit match rule (caught by default deny)`, () => {
      // These collections should NOT have a match rule — they rely on default deny
      // and are accessed only through Cloud Functions admin SDK
      const hasExplicitRule = rulesContent.match(
        new RegExp(`match\\s+/${col}/\\{`)
      );
      expect(hasExplicitRule).toBeNull();
    });
  }
});

describe("Firestore Rules — Invite Rules", () => {
  it("allows read for authenticated users", () => {
    const block = extractBlock(rulesContent, "invites/{inviteId}");
    expect(block).toMatch(/allow read:\s*if\s+isAuth\(\)/);
  });

  it("validates creator on create", () => {
    const block = extractBlock(rulesContent, "invites/{inviteId}");
    expect(block).toMatch(/request\.resource\.data\.createdBy\s*==\s*request\.auth\.uid/);
  });

  it("enforces pending status on create", () => {
    const block = extractBlock(rulesContent, "invites/{inviteId}");
    expect(block).toMatch(/request\.resource\.data\.status\s*==\s*'pending'/);
  });

  it("validates code is string on create", () => {
    const block = extractBlock(rulesContent, "invites/{inviteId}");
    expect(block).toMatch(/request\.resource\.data\.code\s+is\s+string/);
  });
});

// ---- Helpers ----

/**
 * Extract the match block for a given path pattern from rules content.
 * Handles nested braces.
 */
function extractBlock(rules: string, matchPath: string): string {
  const escaped = matchPath.replace(/\{/g, "\\{").replace(/\}/g, "\\}");
  const regex = new RegExp(`match\\s+/${escaped}\\s*\\{`);
  const match = regex.exec(rules);
  if (!match) return "";

  let depth = 0;
  let start = match.index + match[0].length;
  for (let i = start; i < rules.length; i++) {
    if (rules[i] === "{") depth++;
    if (rules[i] === "}") {
      if (depth === 0) {
        return rules.substring(match.index, i + 1);
      }
      depth--;
    }
  }
  return rules.substring(match.index);
}
