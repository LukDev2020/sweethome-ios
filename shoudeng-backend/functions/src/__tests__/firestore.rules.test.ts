/**
 * Firestore security rules, evaluated by the real rules engine (Firestore
 * emulator + @firebase/rules-unit-testing). The old version of this file
 * regex-matched the rules text and would have passed with the logic inverted.
 *
 * Run:  npm run test:rules
 *   (= firebase emulators:exec --only firestore "jest firestore.rules")
 * Without FIRESTORE_EMULATOR_HOST the suite is skipped and says so.
 */
import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc, getDoc, setDoc, updateDoc, getDocs, collection, deleteDoc, Timestamp, query, where,
} from "firebase/firestore";

const RULES = fs.readFileSync(path.resolve(__dirname, "../../../firestore.rules"), "utf8");
const emulator = process.env.FIRESTORE_EMULATOR_HOST;
const d = emulator ? describe : describe.skip;

if (!emulator) {
  // eslint-disable-next-line no-console
  console.warn("[rules] FIRESTORE_EMULATOR_HOST not set — run `npm run test:rules` to evaluate firestore.rules");
}

let env: RulesTestEnvironment;

const future = () => Timestamp.fromMillis(Date.now() + 3600_000);
const past = () => Timestamp.fromMillis(Date.now() - 3600_000);

d("firestore.rules (emulator)", () => {
  beforeAll(async () => {
    const [host, port] = emulator!.split(":");
    env = await initializeTestEnvironment({
      projectId: "demo-shoudeng-rules",
      firestore: { rules: RULES, host, port: Number(port) },
    });
  });
  afterAll(async () => env?.cleanup());

  beforeEach(async () => {
    await env.clearFirestore();
    await env.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "users/mom"), { displayName: "Mom", role: "protected", phone: "+861", locale: "zh" });
      await setDoc(doc(db, "users/sarah"), { displayName: "Sarah", role: "guardian", phone: "+141" });
      await setDoc(doc(db, "guardian_links/sarah_mom"), {
        guardianId: "sarah", protectedPersonId: "mom", status: "active",
        permissions: { canSeeLocation: true, canSeeBattery: true },
      });
      await setDoc(doc(db, "guardian_links/kevin_mom"), {
        guardianId: "kevin", protectedPersonId: "mom", status: "revoked",
        permissions: { canSeeLocation: false },
      });
      await setDoc(doc(db, "medical_card_shares/tok-valid"), { userId: "mom", expiresAt: future() });
      await setDoc(doc(db, "medical_card_shares/tok-expired"), { userId: "mom", expiresAt: past() });
      await setDoc(doc(db, "family_posts/p1"), { authorId: "mom", text: "hi" });
    });
  });

  const as = (uid: string) => env.authenticatedContext(uid).firestore();
  const anon = () => env.unauthenticatedContext().firestore();

  describe("medical_card_shares", () => {
    it("anyone with the token can get a valid share", async () => {
      await assertSucceeds(getDoc(doc(anon(), "medical_card_shares/tok-valid")));
    });
    it("an expired share cannot be read", async () => {
      await assertFails(getDoc(doc(anon(), "medical_card_shares/tok-expired")));
    });
    it("shares cannot be listed (that would leak every token)", async () => {
      await assertFails(getDocs(collection(anon(), "medical_card_shares")));
      await assertFails(getDocs(collection(as("sarah"), "medical_card_shares")));
    });
    it("you can only create a share for your own card", async () => {
      await assertFails(setDoc(doc(as("sarah"), "medical_card_shares/x"), { userId: "mom", expiresAt: future() }));
      await assertSucceeds(setDoc(doc(as("mom"), "medical_card_shares/y"), { userId: "mom", expiresAt: future() }));
    });
  });

  describe("guardian_links transitions", () => {
    it("a revoked guardian cannot re-activate their link", async () => {
      await assertFails(updateDoc(doc(as("kevin"), "guardian_links/kevin_mom"), { status: "active" }));
    });
    it("a guardian cannot grant themselves permissions", async () => {
      await assertFails(updateDoc(doc(as("sarah"), "guardian_links/sarah_mom"), { "permissions.canSeeLocation": true, status: "active" }));
      await assertFails(updateDoc(doc(as("kevin"), "guardian_links/kevin_mom"), { "permissions.canSeeLocation": true }));
    });
    it("a guardian may step down", async () => {
      await assertSucceeds(updateDoc(doc(as("sarah"), "guardian_links/sarah_mom"), { status: "revoked" }));
    });
    it("the protected person may change permissions or revoke, not re-activate", async () => {
      await assertSucceeds(updateDoc(doc(as("mom"), "guardian_links/sarah_mom"), { "permissions.canSeeBattery": false }));
      await assertSucceeds(updateDoc(doc(as("mom"), "guardian_links/sarah_mom"), { status: "revoked" }));
      await assertFails(updateDoc(doc(as("mom"), "guardian_links/kevin_mom"), { status: "active" }));
    });
    it("nobody can re-point a link at someone else", async () => {
      await assertFails(updateDoc(doc(as("mom"), "guardian_links/sarah_mom"), { guardianId: "mallory" }));
      await assertFails(updateDoc(doc(as("sarah"), "guardian_links/sarah_mom"), { protectedPersonId: "dad", status: "revoked" }));
    });
    it("clients cannot create links", async () => {
      await assertFails(setDoc(doc(as("mallory"), "guardian_links/mallory_mom"), { guardianId: "mallory", protectedPersonId: "mom", status: "active" }));
    });
    it("strangers cannot read links", async () => {
      await assertFails(getDoc(doc(as("mallory"), "guardian_links/sarah_mom")));
      await assertSucceeds(getDoc(doc(as("sarah"), "guardian_links/sarah_mom")));
    });
  });

  describe("users", () => {
    it("own profile fields are editable", async () => {
      await assertSucceeds(updateDoc(doc(as("mom"), "users/mom"), { displayName: "Mama", locale: "en" }));
    });
    it("phone and role are server-managed", async () => {
      await assertFails(updateDoc(doc(as("mom"), "users/mom"), { phone: "+10000000000" }));
      await assertFails(updateDoc(doc(as("mom"), "users/mom"), { role: "guardian" }));
    });
    it("nobody edits someone else's profile, and accounts are created by the server", async () => {
      await assertFails(updateDoc(doc(as("sarah"), "users/mom"), { displayName: "x" }));
      await assertFails(setDoc(doc(as("new"), "users/new"), { displayName: "N", role: "guardian", phone: "+1" }));
    });
  });

  describe("family post comments", () => {
    it("linked family may comment, strangers may not", async () => {
      await assertSucceeds(setDoc(doc(as("sarah"), "family_posts/p1/comments/c1"), { authorId: "sarah", text: "❤️" }));
      await assertFails(setDoc(doc(as("mallory"), "family_posts/p1/comments/c2"), { authorId: "mallory", text: "spam" }));
      await assertFails(setDoc(doc(as("kevin"), "family_posts/p1/comments/c3"), { authorId: "kevin", text: "revoked" }));
    });
    it("cannot comment as someone else", async () => {
      await assertFails(setDoc(doc(as("sarah"), "family_posts/p1/comments/c4"), { authorId: "mom", text: "x" }));
    });
  });

  describe("server-only collections", () => {
    it("SOS events and timeline cannot be written by clients", async () => {
      await assertFails(setDoc(doc(as("mom"), "sos_events/s1"), { protectedPersonId: "mom" }));
      await assertFails(setDoc(doc(as("mom"), "timeline_entries/t1"), { userId: "mom" }));
    });
    it("guardians can read the person's SOS, strangers cannot", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "sos_events/s1"), { protectedPersonId: "mom", resolvedAt: null });
      });
      await assertSucceeds(getDoc(doc(as("sarah"), "sos_events/s1")));
      await assertFails(getDoc(doc(as("kevin"), "sos_events/s1"))); // revoked
      await assertFails(getDoc(doc(as("mallory"), "sos_events/s1")));
    });
    it("unknown collections are denied", async () => {
      await assertFails(getDoc(doc(as("mom"), "anything/else")));
      await assertFails(deleteDoc(doc(as("mom"), "voice_calls/CA1")));
    });
  });

  describe("invites", () => {
    it("a pending invite cannot be rewritten by someone else", async () => {
      await env.withSecurityRulesDisabled(async (ctx) => {
        await setDoc(doc(ctx.firestore(), "invites/i1"), { createdBy: "mom", status: "pending", code: "123456" });
      });
      await assertFails(updateDoc(doc(as("mallory"), "invites/i1"), { status: "accepted" }));
      await assertFails(getDocs(query(collection(as("mallory"), "invites"), where("code", "==", "123456"))));
    });
  });
});
