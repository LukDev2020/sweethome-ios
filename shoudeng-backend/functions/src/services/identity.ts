/**
 * Sign-in methods linked to an account. One person = one account (users/{uid});
 * phone, Apple and Alipay are ways into it.
 *
 * auth_identities/{provider}_{hash(subject)} = { uid, provider, subject, … }
 *  - apple:  subject = Apple's stable user id (`sub`)
 *  - alipay: subject = Alipay open_id (or user_id for older apps)
 *  - phone:  subject = the Firebase Auth uid of a phone number added to an
 *            Apple / Alipay account. Accounts created by phone keep that uid as
 *            their own id (users/{firebaseUid}) and need no entry here.
 * Server-only (firestore.rules deny every client read and write).
 */
import * as admin from "firebase-admin";
import { createHash } from "crypto";
import { Timestamp } from "firebase-admin/firestore";

export const IDENTITIES = "auth_identities";
export type LinkedProvider = "apple" | "alipay" | "phone";

const db = () => admin.firestore();

export function identityDocId(provider: LinkedProvider, subject: string): string {
  return `${provider}_${createHash("sha256").update(subject).digest("hex").slice(0, 40)}`;
}

export async function userForIdentity(provider: LinkedProvider, subject: string): Promise<string | null> {
  const snap = await db().collection(IDENTITIES).doc(identityDocId(provider, subject)).get();
  const uid = snap.exists ? snap.data()?.uid : null;
  return typeof uid === "string" && uid ? uid : null;
}

export type LinkResult = "linked" | "alreadyLinked" | "linkedElsewhere";

/** Link once: an identity already on another account stays there. */
export async function linkIdentity(
  uid: string, provider: LinkedProvider, subject: string, extra: Record<string, unknown> = {},
): Promise<LinkResult> {
  const ref = db().collection(IDENTITIES).doc(identityDocId(provider, subject));
  return db().runTransaction(async (t) => {
    const snap = await t.get(ref);
    if (snap.exists) return snap.data()?.uid === uid ? "alreadyLinked" : "linkedElsewhere";
    t.set(ref, { uid, provider, subject, ...extra, linkedAt: Timestamp.now() });
    return "linked";
  });
}

export async function identitiesOf(uid: string): Promise<{ id: string; provider: LinkedProvider; subject: string }[]> {
  const snap = await db().collection(IDENTITIES).where("uid", "==", uid).get();
  return snap.docs.map((d) => ({ id: d.id, provider: d.data().provider, subject: d.data().subject }));
}

/**
 * The account a phone sign-in belongs to: an account created by phone (its own
 * id), or an Apple / Alipay account the number was added to.
 */
export async function userForPhoneSignIn(firebaseUid: string): Promise<string | null> {
  const own = await db().collection("users").doc(firebaseUid).get();
  if (own.exists) return firebaseUid;
  const linked = await userForIdentity("phone", firebaseUid);
  if (!linked) return null;
  const user = await db().collection("users").doc(linked).get();
  return user.exists ? linked : null;
}
