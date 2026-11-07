import * as admin from "firebase-admin";
import { sendFamilyWatchRequest, sendFamilyWatchStarted } from "./fcm";

// ---------------------------------------------------------------------------
// Watch back (family)
// ---------------------------------------------------------------------------
//
// A guardian looks after a person (guardian_links/{guardian}_{person}). With watch back
// the person also looks after that guardian: a link the other way,
// guardian_links/{person}_{guardian} with watchBack: true. The existing machinery then
// works both ways — the guardian's SOS reaches the person, the person sees the guardian
// on their home screen.
//
//  - Only within the family: the guardian must already look after the person.
//  - The guardian is the one sharing, so they agree: the person *asks* (pending until
//    the guardian accepts), or the guardian *offers* (active at once).
//  - Billing: the carer's plan covers it. Watch-back links never take a household seat
//    (household.ts skips them) and never change anyone's plan.
//  - Either side can stop it; it also ends when the guardian stops looking after the
//    person (protected.ts DELETE /guardians/:id).

const db = () => admin.firestore();

export class WatchBackError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

export type WatchBackState = "none" | "pending" | "active";

const forwardRef = (guardianId: string, personId: string) => db().collection("guardian_links").doc(`${guardianId}_${personId}`);
/** The watch-back link: the person (as "guardian") looks after the guardian */
const backRef = (guardianId: string, personId: string) => db().collection("guardian_links").doc(`${personId}_${guardianId}`);

async function cares(guardianId: string, personId: string): Promise<boolean> {
  const link = (await forwardRef(guardianId, personId).get()).data();
  return link?.status === "active" && link.watchBack !== true;
}

async function nameOf(uid: string): Promise<string> {
  return ((await db().collection("users").doc(uid).get()).data()?.displayName as string) ?? "";
}

async function stateOf(guardianId: string, personId: string): Promise<WatchBackState> {
  const link = (await backRef(guardianId, personId).get()).data();
  if (!link) return "none";
  // They already look after each other through a normal link: never overwrite it
  if (link.watchBack !== true) return link.status === "active" ? "active" : "none";
  return link.status === "active" ? "active" : link.status === "pending" ? "pending" : "none";
}

async function writeBackLink(guardianId: string, personId: string, status: "pending" | "active", requestedBy: string) {
  const now = admin.firestore.Timestamp.now();
  await backRef(guardianId, personId).set({
    guardianId: personId,
    protectedPersonId: guardianId,
    status,
    watchBack: true,
    // The carer's plan covers it (no seat, no charge to the person being cared for)
    billedTo: guardianId,
    requestedBy,
    createdAt: now,
    ...(status === "active" && { activatedAt: now }),
  });
}

/** The person being cared for asks to watch back one of their guardians. */
export async function requestWatchBack(personId: string, guardianId: unknown): Promise<WatchBackState> {
  if (typeof guardianId !== "string" || !guardianId || guardianId === personId) throw new WatchBackError(400, "guardianId is required");
  if (!(await cares(guardianId, personId))) throw new WatchBackError(403, "only a guardian who looks after you");
  const state = await stateOf(guardianId, personId);
  if (state !== "none") return state;
  await writeBackLink(guardianId, personId, "pending", personId);
  await sendFamilyWatchRequest(guardianId, await nameOf(personId)).catch(() => undefined);
  return "pending";
}

/** The guardian lets the person watch over them too (no request needed). */
export async function offerWatchBack(guardianId: string, personId: unknown): Promise<WatchBackState> {
  if (typeof personId !== "string" || !personId || personId === guardianId) throw new WatchBackError(400, "personId is required");
  if (!(await cares(guardianId, personId))) throw new WatchBackError(403, "only someone you look after");
  if ((await stateOf(guardianId, personId)) === "active") return "active";
  await writeBackLink(guardianId, personId, "active", guardianId);
  await sendFamilyWatchStarted(personId, await nameOf(guardianId)).catch(() => undefined);
  return "active";
}

/** The guardian answers a request. */
export async function respondWatchBack(guardianId: string, personId: unknown, accept: unknown): Promise<WatchBackState> {
  if (typeof personId !== "string" || !personId) throw new WatchBackError(400, "personId is required");
  const ref = backRef(guardianId, personId);
  const link = (await ref.get()).data();
  if (!link || link.watchBack !== true || link.status !== "pending") throw new WatchBackError(404, "no request from them");
  if (accept !== true) {
    await ref.delete();
    return "none";
  }
  await ref.update({ status: "active", activatedAt: admin.firestore.Timestamp.now() });
  await sendFamilyWatchStarted(personId, await nameOf(guardianId)).catch(() => undefined);
  return "active";
}

/** Either side stops it. */
export async function stopWatchBack(uid: string, otherId: unknown): Promise<void> {
  if (typeof otherId !== "string" || !otherId) throw new WatchBackError(400, "otherId is required");
  for (const ref of [backRef(uid, otherId), backRef(otherId, uid)]) {
    const link = (await ref.get()).data();
    if (link?.watchBack === true) await ref.delete();
  }
}

/** When a guardian stops looking after the person, the watch back goes too. */
export async function endWatchBackWith(guardianId: string, personId: string): Promise<void> {
  const ref = backRef(guardianId, personId);
  if ((await ref.get()).data()?.watchBack === true) await ref.delete();
}

export interface WatchBackEntry { id: string; name: string; state: WatchBackState }

/**
 * For the person being cared for: each guardian and whether they're watched back.
 * For a guardian: requests waiting, and who already watches back.
 */
export async function watchBackOverview(uid: string) {
  const [myGuardians, iCareFor] = await Promise.all([
    db().collection("guardian_links").where("protectedPersonId", "==", uid).where("status", "==", "active").get(),
    db().collection("guardian_links").where("guardianId", "==", uid).where("status", "==", "active").get(),
  ]);
  const guardians = myGuardians.docs.filter((d) => d.data().watchBack !== true).map((d) => d.data().guardianId as string);
  const people = iCareFor.docs.filter((d) => d.data().watchBack !== true).map((d) => d.data().protectedPersonId as string);
  const entry = async (id: string, state: WatchBackState): Promise<WatchBackEntry> => ({ id, name: await nameOf(id), state });
  return {
    /** My guardians and whether I watch them back */
    guardians: await Promise.all(guardians.map(async (g) => entry(g, await stateOf(g, uid)))),
    /** People I look after and whether they watch me back */
    people: await Promise.all(people.map(async (p) => entry(p, await stateOf(uid, p)))),
  };
}
