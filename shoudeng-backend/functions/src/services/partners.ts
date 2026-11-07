import * as admin from "firebase-admin";
import * as crypto from "crypto";

// ---------------------------------------------------------------------------
// Partner organisations for riders (docs/rider-onboarding-plan.md, phases 2–3)
// ---------------------------------------------------------------------------
//
// A delivery platform, union or rider community gets a partner code. Its link
// (https://shoudeng.app/start?for=rider&org=CODE) opens sign-up with Rider chosen.
// A rider who joins through it decides whether the organisation may count them;
// the organisation then sees totals only — riders, active, on shift now, SOS in the
// last 30 days — never names, positions or individual events.

export class PartnerError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const db = () => admin.firestore();

export const normalizePartnerCode = (raw: unknown): string | null => {
  const code = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  return /^[A-Z2-9]{6}$/.test(code) ? code : null;
};

async function adminOrg(uid: string) {
  const snap = await db().collection("organizations").where("adminIds", "array-contains", uid).limit(1).get();
  if (snap.empty) throw new PartnerError(404, "No organization found");
  return snap.docs[0];
}

/** The org admin's partner code (created on first ask, the same afterwards). */
export async function partnerCodeFor(uid: string): Promise<{ code: string; name: string }> {
  const org = await adminOrg(uid);
  const existing = org.data().partnerCode as string | undefined;
  if (existing) return { code: existing, name: org.data().name };
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = Array.from(crypto.randomBytes(6), (b) => CODE_ALPHABET[b % CODE_ALPHABET.length]).join("");
    const ref = db().collection("partner_codes").doc(code);
    const created = await db().runTransaction(async (tx) => {
      if ((await tx.get(ref)).exists) return false;
      tx.set(ref, { orgId: org.id, createdAt: admin.firestore.Timestamp.now() });
      tx.update(org.ref, { partnerCode: code });
      return true;
    });
    if (created) return { code, name: org.data().name };
  }
  throw new PartnerError(500, "Could not create a partner code");
}

/** Name shown during sign-up ("Joining through Riders Union"). */
export async function previewPartner(rawCode: unknown): Promise<{ name: string }> {
  const code = normalizePartnerCode(rawCode);
  if (!code) throw new PartnerError(400, "invalid partner code");
  const link = (await db().collection("partner_codes").doc(code).get()).data();
  const org = link ? (await db().collection("organizations").doc(link.orgId).get()).data() : undefined;
  if (!org) throw new PartnerError(404, "no partner with that code");
  return { name: org.name as string };
}

/**
 * The rider links to the partner; `shareStats` is their choice to be counted.
 * Linking again only updates the choice.
 */
export async function joinPartner(uid: string, rawCode: unknown, shareStats: unknown): Promise<{ name: string; shareStats: boolean }> {
  const code = normalizePartnerCode(rawCode);
  if (!code) throw new PartnerError(400, "invalid partner code");
  const link = (await db().collection("partner_codes").doc(code).get()).data();
  if (!link) throw new PartnerError(404, "no partner with that code");
  const orgRef = db().collection("organizations").doc(link.orgId);
  const share = shareStats === true;
  const memberRef = db().collection("org_members").doc(`${link.orgId}_${uid}`);
  const name = await db().runTransaction(async (tx) => {
    const org = await tx.get(orgRef);
    if (!org.exists) throw new PartnerError(404, "no partner with that code");
    const member = await tx.get(memberRef);
    if (member.exists) {
      tx.update(memberRef, { shareStats: share });
    } else {
      tx.set(memberRef, {
        orgId: link.orgId, userId: uid, role: "rider", joinedVia: "partner_link",
        shareStats: share, addedAt: admin.firestore.Timestamp.now(),
      });
      tx.update(orgRef, { memberCount: admin.firestore.FieldValue.increment(1) });
    }
    tx.update(db().collection("users").doc(uid), {
      "riderProfile.partnerOrgId": link.orgId,
      "riderProfile.partnerOrgName": org.data()!.name,
    });
    return org.data()!.name as string;
  });
  return { name, shareStats: share };
}

/** Totals for the org admin, over riders who agreed to be counted. */
export async function riderStats(uid: string, at: Date = new Date()) {
  const org = await adminOrg(uid);
  const members = await db().collection("org_members")
    .where("orgId", "==", org.id).where("role", "==", "rider").get();
  const counted = members.docs.filter((d) => d.data().shareStats === true);
  const weekAgo = at.getTime() - 7 * 24 * 3600_000;
  const monthAgo = admin.firestore.Timestamp.fromMillis(at.getTime() - 30 * 24 * 3600_000);
  let activeLast7d = 0, onShiftNow = 0, sosLast30d = 0;
  for (const m of counted) {
    const riderId = m.data().userId as string;
    const user = (await db().collection("users").doc(riderId).get()).data() ?? {};
    const last = user.riderProfile?.lastShiftAt?.toMillis?.() ?? 0;
    if (last >= weekAgo) activeLast7d++;
    if (user.riderOnShift === true) onShiftNow++;
    sosLast30d += (await db().collection("sos_events")
      .where("protectedPersonId", "==", riderId).where("triggeredAt", ">=", monthAgo).get()).size;
  }
  return {
    orgName: org.data().name as string,
    partnerCode: (org.data().partnerCode as string) ?? null,
    riders: counted.length,
    notCounted: members.size - counted.length,
    activeLast7d,
    onShiftNow,
    sosLast30d,
  };
}
