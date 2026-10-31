jest.mock("firebase-admin", () => ({
  firestore: Object.assign(() => ({ collection: jest.fn(), recursiveDelete: jest.fn() }), { FieldValue: {}, Timestamp: {} }),
  initializeApp: jest.fn(),
  storage: jest.fn(),
}));
jest.mock("firebase-functions", () => ({ config: () => ({}) }));
jest.mock("@google-cloud/bigquery", () => ({ BigQuery: jest.fn(() => ({})) }));
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { retentionPlan } = require("../services/accountData");

describe("per-plan retention", () => {
  const paid = new Map([
    ["guardianA", { heartbeat: 90, location: 90, checkin: -1 }],   // single plan
    ["momOfA", { heartbeat: 90, location: 90, checkin: -1 }],      // covered by A's plan
    ["familyB", { heartbeat: 365, location: 365, checkin: -1 }],
  ]);
  const plans = retentionPlan(paid);
  const find = (table: string, days: number) => plans.find((p: { table: string; days: number }) => p.table === table && p.days === days);

  it("free users: 7 days of location and heartbeats, 30 days of check-ins", () => {
    for (const [table, days] of [["location_reports", 7], ["heartbeat_signals", 7], ["checkins", 30]] as const) {
      const p = find(table, days);
      expect(p).toBeDefined();
      expect(p.exceptUsers.sort()).toEqual(["familyB", "guardianA", "momOfA"]);
    }
  });

  it("paid users and the people they protect keep their plan's history", () => {
    expect(find("location_reports", 90).onlyUsers.sort()).toEqual(["guardianA", "momOfA"]);
    expect(find("location_reports", 365).onlyUsers).toEqual(["familyB"]);
  });

  it("paid check-ins are never deleted", () => {
    expect(plans.filter((p: { table: string }) => p.table === "checkins")).toHaveLength(1);
  });

  it("with no paid users, the free rule applies to everyone", () => {
    const free = retentionPlan(new Map());
    expect(free).toHaveLength(3);
    free.forEach((p: { exceptUsers: string[] }) => expect(p.exceptUsers).toEqual([]));
  });
});
