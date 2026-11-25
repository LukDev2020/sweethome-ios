/**
 * List endpoints read in a few round trips, not one more query per item (N+1):
 *  - the family feed reads comments from the post's copy, not one query per post;
 *    older posts without the copy still show theirs; an erased account's comments
 *    leave the feed;
 *  - the family circle, the org report and the batch helpers stay correct past the
 *    30-value limit of an `in` filter.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import request from "supertest";
import { resetFakeAdmin, seed, readDoc, tokenFor, ts, queryLog } from "./helpers/fakeAdmin";

const { app } = require("../app");
const { getFamilyGroup } = require("../routes/family");
const { eraseAccount } = require("../services/accountData");
const { getDocsById, docsWhereIn, chunk } = require("../services/batchRead");
const admin = require("firebase-admin");

const auth = (uid: string) => ({ Authorization: `Bearer ${tokenFor(uid)}` });
const get = (uid: string, path: string) => request(app).get(path).set(auth(uid));
const post = (uid: string, path: string, body: object) => request(app).post(path).set(auth(uid)).send(body);

function link(guardianId: string, protectedPersonId: string) {
  seed(`guardian_links/${guardianId}_${protectedPersonId}`, { guardianId, protectedPersonId, status: "active" });
}

const commentQueries = () => queryLog.filter((p) => p.endsWith("/comments")).length;

beforeEach(() => {
  resetFakeAdmin();
  for (const u of ["mom", "sarah", "kevin"]) {
    seed(`users/${u}`, { displayName: u.charAt(0).toUpperCase() + u.slice(1), avatarInitial: u.charAt(0).toUpperCase() });
  }
  link("sarah", "mom");
  link("kevin", "mom");
});

describe("family feed comments", () => {
  async function newPost(author: string, text: string): Promise<string> {
    const res = await post(author, "/v1/family/posts", { text });
    expect(res.status).toBe(201);
    return res.body.postId;
  }

  it("new posts carry their newest comments, so the feed runs no query per post", async () => {
    const ids = [await newPost("mom", "one"), await newPost("sarah", "two"), await newPost("kevin", "three")];
    for (let i = 1; i <= 12; i++) {
      expect((await post(i % 2 ? "sarah" : "kevin", `/v1/family/posts/${ids[0]}/comments`, { text: `c${i}` })).status).toBe(201);
    }
    await post("mom", `/v1/family/posts/${ids[1]}/comments`, { text: "hello" });

    queryLog.length = 0;
    const res = await get("mom", "/v1/family/posts");
    expect(res.status).toBe(200);
    expect(commentQueries()).toBe(0);

    const first = res.body.find((p: any) => p.id === ids[0]);
    // The newest 10, oldest first, and the count of all of them
    expect(first.comments.map((c: any) => c.text)).toEqual(Array.from({ length: 10 }, (_, k) => `c${k + 3}`));
    expect(first.commentCount).toBe(12);
    expect(res.body.find((p: any) => p.id === ids[1]).comments).toMatchObject([{ authorId: "mom", text: "hello", authorName: "Mom" }]);
    expect(res.body.find((p: any) => p.id === ids[2]).comments).toEqual([]);
    // The stored copy is capped
    expect((readDoc(`family_posts/${ids[0]}`)!.recentComments as unknown[]).length).toBe(10);
  });

  it("a post from before the copy existed still shows its comments", async () => {
    seed("family_posts/old", { authorId: "mom", text: "old", commentCount: 1, createdAt: ts(Date.now() - 60_000) });
    seed("family_posts/old/comments/c1", { authorId: "sarah", authorName: "Sarah", text: "from before", createdAt: ts(Date.now() - 30_000) });
    const res = await get("kevin", "/v1/family/posts");
    expect(res.body[0].comments.map((c: any) => c.text)).toEqual(["from before"]);
    // Commenting on it leaves it on the subcollection path (no partial copy)
    await post("kevin", "/v1/family/posts/old/comments", { text: "new one" });
    expect(readDoc("family_posts/old")!.recentComments).toBeUndefined();
    const again = await get("kevin", "/v1/family/posts");
    expect(again.body[0].comments.map((c: any) => c.text)).toEqual(["from before", "new one"]);
    expect(again.body[0].commentCount).toBe(2);
  });

  it("an erased account's comments leave the feed", async () => {
    const id = await newPost("mom", "hi");
    await post("sarah", `/v1/family/posts/${id}/comments`, { text: "sarah's" });
    await post("kevin", `/v1/family/posts/${id}/comments`, { text: "kevin's" });
    await eraseAccount("sarah");
    const res = await get("kevin", "/v1/family/posts");
    const p = res.body.find((x: any) => x.id === id);
    expect(p.comments.map((c: any) => c.text)).toEqual(["kevin's"]);
    expect(JSON.stringify(readDoc(`family_posts/${id}`))).not.toContain("sarah's");
  });

  it("a comment on a deleted post is refused", async () => {
    expect((await post("sarah", "/v1/family/posts/gone/comments", { text: "x" })).status).toBe(404);
  });
});

describe("past the 30-value `in` limit", () => {
  it("the family circle of someone looking after 35 people includes every co-guardian", async () => {
    seed("users/carer", { displayName: "Carer" });
    for (let i = 0; i < 35; i++) {
      link("carer", `p${i}`);
      link(`g${i}`, `p${i}`);
    }
    queryLog.length = 0;
    const circle: string[] = await getFamilyGroup("carer");
    expect(circle).toHaveLength(1 + 35 + 35);
    for (let i = 0; i < 35; i++) expect(circle).toEqual(expect.arrayContaining([`p${i}`, `g${i}`]));
    // 2 lookups of my own links + 2 groups of anchors, not 35
    expect(queryLog.filter((p) => p === "guardian_links").length).toBe(4);
  });

  it("the org report counts check-ins and SOS of all 35 members", async () => {
    seed("users/boss", { displayName: "Boss" });
    seed("organizations/acme", { name: "Acme", adminIds: ["boss"] });
    const now = Date.now();
    for (let i = 0; i < 35; i++) {
      seed(`org_members/m${i}`, { orgId: "acme", userId: `u${i}` });
      seed(`checkins/c${i}`, { userId: `u${i}`, timestamp: ts(now - 3600_000) });
      if (i % 5 === 0) seed(`sos_events/s${i}`, { protectedPersonId: `u${i}`, triggeredAt: ts(now - 7200_000) });
    }
    seed("checkins/outsider", { userId: "stranger", timestamp: ts(now - 3600_000) });
    const res = await get("boss", "/v1/org/reports?orgId=acme");
    expect(res.status).toBe(200);
    expect(res.body.summary).toMatchObject({ totalMembers: 35, totalCheckIns: 35, totalSOSEvents: 7 });
  });

  it("getDocsById reads many ids, skipping missing, duplicate and empty ones", async () => {
    for (let i = 0; i < 150; i++) seed(`users/x${i}`, { n: i });
    const found = await getDocsById("users", [...Array.from({ length: 150 }, (_, i) => `x${i}`), "x1", "", "nobody"]);
    expect(found.size).toBe(150);
    expect(found.get("x149")).toEqual({ n: 149 });
    expect(found.has("nobody")).toBe(false);
    expect((await getDocsById("users", [])).size).toBe(0);
  });

  it("docsWhereIn runs one query per 30 values", async () => {
    for (let i = 0; i < 61; i++) seed(`checkins/k${i}`, { userId: `u${i}` });
    queryLog.length = 0;
    const docs = await docsWhereIn(Array.from({ length: 61 }, (_, i) => `u${i}`),
      (part: string[]) => admin.firestore().collection("checkins").where("userId", "in", part));
    expect(docs).toHaveLength(61);
    expect(queryLog).toHaveLength(3);
    expect(chunk([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });
});
