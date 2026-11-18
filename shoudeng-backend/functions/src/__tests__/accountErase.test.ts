/**
 * Account deletion (App Store 5.1.1(v)): nothing that identifies the person is
 * left behind, and nothing keeps alerting others about a deleted account.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("firebase-functions", () => ({ config: () => ({}) }));
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn(() => ({ createQueryJob: async () => [{ getQueryResults: async () => [[]] }] })),
}));

import { resetFakeAdmin, seed, readDoc, listDocs } from "./helpers/fakeAdmin";
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { eraseAccount } = require("../services/accountData");

describe("eraseAccount", () => {
  beforeEach(() => resetFakeAdmin());

  it("removes shifts, crew membership, watchers, safety events, reports and comments", async () => {
    seed("users/kai", { displayName: "Kai", crewId: "c1", riderWatchers: ["lee"] });
    seed("users/lee", { displayName: "Lee", crewId: "c1", riderWatchers: ["kai"] });
    seed("crews/c1", { name: "Night riders", ownerId: "kai", memberIds: ["kai", "lee"] });
    seed("rider_shifts/kai", { active: true, watcherIds: ["lee"] });
    seed("user_preferences/kai", { lang: "en" });
    seed("safety_events/kai_e1", { userId: "kai", type: "fall", latitude: 1, longitude: 2 });
    seed("incident_reports/r1", { personId: "kai", createdBy: "lee" });
    seed("incident_reports/r2", { personId: "mom", createdBy: "kai" });
    seed("org_members/o1_kai", { orgId: "o1", userId: "kai", role: "rider" });
    seed("family_posts/p1", { authorId: "lee", text: "hi" });
    seed("family_posts/p1/comments/c1", { authorId: "kai", authorName: "Kai", text: "at the hospital" });
    seed("family_posts/p1/comments/c2", { authorId: "lee", authorName: "Lee", text: "ok" });

    await eraseAccount("kai");

    expect(readDoc("users/kai")).toBeUndefined();
    expect(readDoc("rider_shifts/kai")).toBeUndefined();
    expect(readDoc("user_preferences/kai")).toBeUndefined();
    expect(readDoc("safety_events/kai_e1")).toBeUndefined();
    expect(readDoc("incident_reports/r1")).toBeUndefined();
    expect(readDoc("incident_reports/r2")).toBeUndefined();
    expect(readDoc("org_members/o1_kai")).toBeUndefined();
    expect(readDoc("family_posts/p1/comments/c1")).toBeUndefined();
    expect(readDoc("family_posts/p1/comments/c2")).toBeDefined();
    expect(readDoc("crews/c1")).toMatchObject({ memberIds: ["lee"], ownerId: "lee" });
    expect(readDoc("users/lee")?.riderWatchers).toEqual([]);
    expect(listDocs("users").map((d: { id: string }) => d.id)).toEqual(["lee"]);
  });
});
