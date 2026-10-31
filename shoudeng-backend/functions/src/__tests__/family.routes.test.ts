/**
 * Family circle (家庭圈) phase 1:
 *  - the circle includes co-guardians of the same protected person, not strangers;
 *  - comments: the newest 10 in chronological order, commentCount from the post;
 *  - a post's location round-trips; local file:// links never reach the feed;
 *  - a retried send with the same clientPostId does not duplicate the post;
 *  - photo uploads of a real size get through the full app's JSON parsing.
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
import { resetFakeAdmin, seed, readDoc, listDocs, savedFiles, tokenFor, ts } from "./helpers/fakeAdmin";

const { app } = require("../app");
const { getFamilyGroup, MAX_UPLOAD_BYTES } = require("../routes/family");

const auth = (uid: string) => ({ Authorization: `Bearer ${tokenFor(uid)}` });
const get = (uid: string, path: string) => request(app).get(path).set(auth(uid));
const post = (uid: string, path: string, body: object) => request(app).post(path).set(auth(uid)).send(body);

function link(guardianId: string, protectedPersonId: string, status = "active") {
  seed(`guardian_links/${guardianId}_${protectedPersonId}`, { guardianId, protectedPersonId, status });
}

function seedPost(id: string, authorId: string, minutesAgo: number, extra: Record<string, unknown> = {}) {
  seed(`family_posts/${id}`, {
    authorId, authorName: authorId, authorInitial: authorId.charAt(0).toUpperCase(),
    text: `${authorId} says hi`, mediaURLs: [], commentCount: 0,
    createdAt: ts(Date.now() - minutesAgo * 60_000), ...extra,
  });
}

const feedIds = async (uid: string) => {
  const res = await get(uid, "/v1/family/posts");
  expect(res.status).toBe(200);
  return (res.body as { id: string }[]).map((p) => p.id).sort();
};

beforeEach(() => {
  resetFakeAdmin();
  // The Chen family: Sarah, Kevin and Lucy look out for Mom; Sarah also for Dad.
  // Hank is a carer who looks out for Dad and for Gina, who is not family.
  for (const u of ["mom", "dad", "sarah", "kevin", "lucy", "hank", "gina", "mallory"]) {
    seed(`users/${u}`, { displayName: u.charAt(0).toUpperCase() + u.slice(1), avatarInitial: u.charAt(0).toUpperCase() });
  }
  link("sarah", "mom");
  link("kevin", "mom");
  link("lucy", "mom");
  link("sarah", "dad");
  link("hank", "dad");
  link("hank", "gina");
  link("mallory", "mom", "revoked");
});

describe("family circle", () => {
  it("co-guardians of the same person are in each other's circle", async () => {
    expect((await getFamilyGroup("kevin")).sort()).toEqual(["kevin", "lucy", "mom", "sarah"]);
    expect((await getFamilyGroup("sarah")).sort()).toEqual(["dad", "hank", "kevin", "lucy", "mom", "sarah"]);
  });

  it("a protected person sees their guardians but not the other people their guardian looks out for", async () => {
    expect((await getFamilyGroup("mom")).sort()).toEqual(["kevin", "lucy", "mom", "sarah"]);
    expect(await getFamilyGroup("gina")).not.toContain("dad");
    expect(await getFamilyGroup("dad")).not.toContain("gina");
  });

  it("is symmetric", async () => {
    const users = ["mom", "dad", "sarah", "kevin", "lucy", "hank", "gina", "mallory"];
    const circles = Object.fromEntries(await Promise.all(users.map(async (u) => [u, await getFamilyGroup(u)])));
    for (const a of users) for (const b of circles[a]) expect(circles[b]).toContain(a);
  });

  it("siblings see each other's posts; strangers and revoked guardians see nothing of the family", async () => {
    seedPost("p-kevin", "kevin", 5);
    seedPost("p-lucy", "lucy", 4);
    seedPost("p-mom", "mom", 3);
    seedPost("p-gina", "gina", 2);
    seedPost("p-mallory", "mallory", 1);

    expect(await feedIds("lucy")).toEqual(["p-kevin", "p-lucy", "p-mom"]);
    expect(await feedIds("kevin")).toEqual(["p-kevin", "p-lucy", "p-mom"]);
    expect(await feedIds("mallory")).toEqual(["p-mallory"]);
    expect(await feedIds("dad")).toEqual([]); // Hank's other person (Gina) stays out
  });

  it("siblings may comment on each other's posts; strangers may not", async () => {
    seedPost("p-kevin", "kevin", 5);
    expect((await post("lucy", "/v1/family/posts/p-kevin/comments", { text: "Nice" })).status).toBe(201);
    expect((await post("gina", "/v1/family/posts/p-kevin/comments", { text: "Hi" })).status).toBe(403);
    expect((await post("mallory", "/v1/family/posts/p-kevin/comments", { text: "Hi" })).status).toBe(403);
    expect(readDoc("family_posts/p-kevin")!.commentCount).toBe(1);
  });
});

describe("GET /v1/family/posts comments", () => {
  it("returns the newest 10 comments in chronological order and the full count", async () => {
    seedPost("p1", "mom", 60, { commentCount: 12 });
    for (let i = 1; i <= 12; i++) {
      seed(`family_posts/p1/comments/c${String(i).padStart(2, "0")}`, {
        authorId: "sarah", authorName: "Sarah", authorInitial: "S", text: `comment ${i}`,
        createdAt: ts(Date.now() - (60 - i) * 60_000),
      });
    }
    const res = await get("sarah", "/v1/family/posts");
    const p1 = res.body.find((p: any) => p.id === "p1");
    expect(p1.comments.map((c: any) => c.text)).toEqual(
      Array.from({ length: 10 }, (_, k) => `comment ${k + 3}`));
    expect(p1.commentCount).toBe(12);
  });

  it("fills in missing optional fields instead of failing", async () => {
    seed("family_posts/bare", { authorId: "mom", createdAt: ts(Date.now()) });
    const res = await get("sarah", "/v1/family/posts");
    expect(res.body[0]).toMatchObject({
      id: "bare", authorName: "", authorInitial: "?", text: "", mediaURLs: [], comments: [], commentCount: 0,
      latitude: null, longitude: null, locationName: null,
    });
  });
});

describe("POST /v1/family/posts", () => {
  it("stores the location and returns it in the feed", async () => {
    const res = await post("mom", "/v1/family/posts", {
      text: "At the park", mediaURLs: [], latitude: 30.6586, longitude: 104.0647, locationName: "Chengdu",
    });
    expect(res.status).toBe(201);
    const feed = await get("kevin", "/v1/family/posts");
    expect(feed.body[0]).toMatchObject({ id: res.body.postId, text: "At the park", latitude: 30.6586, longitude: 104.0647, locationName: "Chengdu" });
  });

  it("drops invalid coordinates and never stores a phone's file:// links", async () => {
    const res = await post("mom", "/v1/family/posts", {
      text: "Photo", latitude: 123, longitude: 9,
      mediaURLs: ["file:///private/var/mobile/tmp/chat_1.jpg", "https://storage.googleapis.com/b/family/mom/1.jpg"],
    });
    expect(res.status).toBe(201);
    const stored = readDoc(`family_posts/${res.body.postId}`)!;
    expect(stored.mediaURLs).toEqual(["https://storage.googleapis.com/b/family/mom/1.jpg"]);
    expect(stored.latitude).toBeUndefined();

    const onlyLocal = await post("mom", "/v1/family/posts", { text: "", mediaURLs: ["file:///tmp/x.jpg"] });
    expect(onlyLocal.status).toBe(400);
  });

  it("a retried send with the same clientPostId does not duplicate the post", async () => {
    const body = { text: "Home safe", mediaURLs: [], clientPostId: "3F2504E0-4F89-11D3-9A0C-0305E82C3301" };
    const first = await post("mom", "/v1/family/posts", body);
    const again = await post("mom", "/v1/family/posts", body);
    expect(first.status).toBe(201);
    expect(again.status).toBe(200);
    expect(again.body.postId).toBe(first.body.postId);
    expect(first.body.postId).toBe(body.clientPostId);
    expect(listDocs("family_posts")).toHaveLength(1);

    const hijack = await post("kevin", "/v1/family/posts", body);
    expect(hijack.status).toBe(409);
    expect(readDoc(`family_posts/${body.clientPostId}`)!.authorId).toBe("mom");

    expect((await post("mom", "/v1/family/posts", { text: "x", clientPostId: "../users/mom" })).status).toBe(400);
  });
});

describe("POST /v1/family/upload", () => {
  it("accepts a photo far above the global 100 kB JSON limit", async () => {
    const jpeg = Buffer.alloc(900 * 1024, 7); // a typical 1600 px photo
    const res = await post("mom", "/v1/family/upload", { data: jpeg.toString("base64"), mimeType: "image/jpeg" });
    expect(res.status).toBe(200);
    expect(res.body.url).toMatch(/^https:\/\/storage\.googleapis\.com\/test-bucket\/family\/mom\/\d+\.jpg$/);
    expect([...savedFiles.values()][0].length).toBe(jpeg.length);
  });

  it("other routes keep the 100 kB limit", async () => {
    const res = await post("mom", "/v1/family/posts", { text: "x".repeat(150 * 1024) });
    expect(res.status).toBe(413);
  });

  it("rejects an oversized photo with a code the app can show", async () => {
    const big = Buffer.alloc(MAX_UPLOAD_BYTES + 1, 1);
    const res = await post("mom", "/v1/family/upload", { data: big.toString("base64"), mimeType: "image/jpeg" });
    expect(res.status).toBe(413);
    expect(res.body.code).toBe("UPLOAD_TOO_LARGE");
    expect(savedFiles.size).toBe(0);
  });

  it("a body over the route's JSON limit gets the same code", async () => {
    const huge = Buffer.alloc(7 * 1024 * 1024, 1);
    const res = await post("mom", "/v1/family/upload", { data: huge.toString("base64"), mimeType: "image/jpeg" });
    expect(res.status).toBe(413);
    expect(res.body.code).toBe("UPLOAD_TOO_LARGE");
  });

  it("requires data", async () => {
    expect((await post("mom", "/v1/family/upload", { mimeType: "image/jpeg" })).status).toBe(400);
  });
});
