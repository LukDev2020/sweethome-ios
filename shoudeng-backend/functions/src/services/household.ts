import * as admin from "firebase-admin";
import { PLANS, PLAN_RANK, PlanId, paidPlanOf } from "./payment";

// ---------------------------------------------------------------------------
// Households — one plan, shared by the family (docs/pricing/PRICING.md)
// ---------------------------------------------------------------------------
//
// There is no "household" document: it follows from the guardian links.
//  - A payer is a guardian with their own paid plan (subscription or lifetime).
//  - A payer's household = the people they guard directly (its protected members)
//    + the payer + every other guardian of those people (its guardians).
//  - Everyone in a household gets its plan: Kevin (free) guarding Mom, whom Sarah
//    (Family) also guards, uses Family. A person in several households gets the best.
//  - Limits are checked when a link is made (invite accepted), never retroactively:
//      payer's protected members ≤ plan.maxProtected,
//      household guardians      ≤ plan.maxGuardians,
//    and people nobody pays for stay within the free plan (1 + 1).
//
// The rules are pure functions over a LinkGraph (unit-tested); loadGraph() reads the
// part of Firestore a decision needs.

export interface Link { guardianId: string; protectedPersonId: string }

export interface LinkGraph {
  links: Link[];
  /** Paid plans only; anyone missing is on the free plan */
  paid: Map<string, PlanId>;
}

export interface Household {
  payerId: string;
  planId: PlanId;
  protectedIds: Set<string>;
  guardianIds: Set<string>;
}

export type LimitViolation = {
  /** Which seat ran out */
  limit: "protected" | "guardians";
  max: number;
  planId: PlanId;
  /** The household whose limit it is (null: nobody pays — the free plan) */
  payerId: string | null;
};

const better = (a: PlanId | null, b: PlanId | null): PlanId | null => {
  if (!a) return b;
  if (!b) return a;
  return PLAN_RANK[b] > PLAN_RANK[a] ? b : a;
};

const guardiansOf = (g: LinkGraph, protectedId: string) =>
  g.links.filter((l) => l.protectedPersonId === protectedId).map((l) => l.guardianId);
const protectedOf = (g: LinkGraph, guardianId: string) =>
  g.links.filter((l) => l.guardianId === guardianId).map((l) => l.protectedPersonId);
const within = (count: number, max: number) => max < 0 || count <= max;

/** The household a payer's plan covers. */
export function householdIn(g: LinkGraph, payerId: string): Household | null {
  const planId = g.paid.get(payerId);
  if (!planId) return null;
  const protectedIds = new Set(protectedOf(g, payerId));
  const guardianIds = new Set<string>([payerId]);
  for (const p of protectedIds) guardiansOf(g, p).forEach((id) => guardianIds.add(id));
  return { payerId, planId, protectedIds, guardianIds };
}

/** Payers whose household includes this protected person. */
export function payersCovering(g: LinkGraph, protectedId: string): string[] {
  return guardiansOf(g, protectedId).filter((id) => g.paid.has(id));
}

/**
 * The plan a person uses: their own, or the best household they belong to — as a
 * guardian of someone a payer guards, or as someone a payer guards.
 */
export function effectivePlanIn(g: LinkGraph, uid: string): { planId: PlanId; payerId: string | null } {
  const own = g.paid.get(uid) ?? null;
  let best: PlanId | null = own;
  let payerId: string | null = own ? uid : null;
  const consider = (payer: string) => {
    const plan = g.paid.get(payer)!;
    const next = better(best, plan);
    if (next !== best) { best = next; payerId = payer; }
  };
  for (const p of protectedOf(g, uid)) payersCovering(g, p).forEach(consider);
  payersCovering(g, uid).forEach(consider);
  return { planId: best ?? "free", payerId };
}

/**
 * Can guardian G start guarding protected person P? null = yes. Re-linking an
 * existing pair is always allowed (the caller drops it from the graph first).
 */
export function checkNewLink(g: LinkGraph, guardianId: string, protectedId: string): LimitViolation | null {
  const graph: LinkGraph = {
    paid: g.paid,
    links: g.links.filter((l) => !(l.guardianId === guardianId && l.protectedPersonId === protectedId)),
  };
  const guardianPlan = graph.paid.get(guardianId) ?? null;
  const existingPayers = payersCovering(graph, protectedId);

  // Protected seats
  if (guardianPlan) {
    const max = PLANS[guardianPlan].maxProtected;
    if (!within(protectedOf(graph, guardianId).length + 1, max)) {
      return { limit: "protected", max, planId: guardianPlan, payerId: guardianId };
    }
  } else if (existingPayers.length === 0) {
    // Nobody pays for P: it takes one of G's free seats (people others pay for don't)
    const uncovered = protectedOf(graph, guardianId).filter((p) => payersCovering(graph, p).length === 0);
    if (!within(uncovered.length + 1, PLANS.free.maxProtected)) {
      return { limit: "protected", max: PLANS.free.maxProtected, planId: "free", payerId: null };
    }
  }

  // Guardian seats: at least one household covering P must have room for G
  const payersAfter = guardianPlan ? [...new Set([...existingPayers, guardianId])] : existingPayers;
  if (payersAfter.length === 0) {
    const max = PLANS.free.maxGuardians;
    if (!within(guardiansOf(graph, protectedId).length + 1, max)) {
      return { limit: "guardians", max, planId: "free", payerId: null };
    }
    return null;
  }
  const after: LinkGraph = { paid: graph.paid, links: [...graph.links, { guardianId, protectedPersonId: protectedId }] };
  let tightest: LimitViolation | null = null;
  for (const payer of payersAfter) {
    const h = householdIn(after, payer)!;
    const max = PLANS[h.planId].maxGuardians;
    if (within(h.guardianIds.size, max)) return null;
    if (!tightest || PLAN_RANK[h.planId] > PLAN_RANK[tightest.planId]) {
      tightest = { limit: "guardians", max, planId: h.planId, payerId: payer };
    }
  }
  return tightest;
}

// ---------------------------------------------------------------------------
// Firestore
// ---------------------------------------------------------------------------

const db = () => admin.firestore();

async function activeLinks(field: "guardianId" | "protectedPersonId", id: string): Promise<Link[]> {
  const snap = await db().collection("guardian_links").where(field, "==", id).where("status", "==", "active").get();
  return snap.docs.map((d) => ({ guardianId: d.data().guardianId, protectedPersonId: d.data().protectedPersonId }));
}

async function paidPlans(uids: Iterable<string>): Promise<Map<string, PlanId>> {
  const paid = new Map<string, PlanId>();
  await Promise.all([...new Set(uids)].map(async (uid) => {
    const doc = await db().collection("subscriptions").doc(uid).get();
    const plan = paidPlanOf(doc.exists ? doc.data() : undefined);
    if (plan) paid.set(uid, plan.planId);
  }));
  return paid;
}

/**
 * The part of the link graph around these people: their links, the other guardians of
 * the people they guard, and — for every payer found — that payer's whole household.
 */
export async function loadGraph(uids: string[]): Promise<LinkGraph> {
  const seen = new Set<string>();
  const links: Link[] = [];
  const add = (ls: Link[]) => ls.forEach((l) => {
    const key = `${l.guardianId}_${l.protectedPersonId}`;
    if (!seen.has(key)) { seen.add(key); links.push(l); }
  });
  const loadedAsGuardian = new Set<string>();
  const loadedAsProtected = new Set<string>();
  const asGuardian = async (id: string) => { if (!loadedAsGuardian.has(id)) { loadedAsGuardian.add(id); add(await activeLinks("guardianId", id)); } };
  const asProtected = async (id: string) => { if (!loadedAsProtected.has(id)) { loadedAsProtected.add(id); add(await activeLinks("protectedPersonId", id)); } };

  await Promise.all(uids.flatMap((u) => [asGuardian(u), asProtected(u)]));
  // Other guardians of the people these users guard (who may pay for them)
  await Promise.all(links.filter((l) => uids.includes(l.guardianId)).map((l) => asProtected(l.protectedPersonId)));

  const paid = await paidPlans([...uids, ...links.map((l) => l.guardianId)]);
  // Each payer's whole household (for guardian-seat counts)
  for (const payer of [...paid.keys()]) {
    await asGuardian(payer);
    await Promise.all(links.filter((l) => l.guardianId === payer).map((l) => asProtected(l.protectedPersonId)));
  }
  const more = await paidPlans(links.map((l) => l.guardianId).filter((id) => !paid.has(id)));
  more.forEach((v, k) => paid.set(k, v));
  return { links, paid };
}

export interface HouseholdSummary {
  /** Plan in effect (own or a household's) */
  planId: PlanId;
  /** Who pays for it; equals the user when it is their own plan, null on the free plan */
  payerId: string | null;
  payerName: string | null;
  guardians: number;
  maxGuardians: number;
  protected: number;
  maxProtected: number;
}

/** Plan in effect for a user and the seats used in that household. */
export async function householdSummary(uid: string): Promise<HouseholdSummary> {
  const graph = await loadGraph([uid]);
  const { planId, payerId } = effectivePlanIn(graph, uid);
  const plan = PLANS[planId];
  if (!payerId) {
    return {
      planId, payerId: null, payerName: null,
      guardians: 1, maxGuardians: plan.maxGuardians,
      protected: protectedOf(graph, uid).length, maxProtected: plan.maxProtected,
    };
  }
  const h = householdIn(graph, payerId)!;
  let payerName: string | null = null;
  if (payerId !== uid) {
    const user = await db().collection("users").doc(payerId).get();
    payerName = (user.exists ? user.data()?.displayName : null) ?? null;
  }
  return {
    planId, payerId, payerName,
    guardians: h.guardianIds.size, maxGuardians: plan.maxGuardians,
    protected: h.protectedIds.size, maxProtected: plan.maxProtected,
  };
}

/** Plan in effect for feature checks (own plan, else the best household). */
export async function effectivePlanId(uid: string): Promise<PlanId> {
  return effectivePlanIn(await loadGraph([uid]), uid).planId;
}

/** Limit check for a new link, reading what it needs. */
export async function checkNewLinkFor(guardianId: string, protectedId: string): Promise<LimitViolation | null> {
  return checkNewLink(await loadGraph([guardianId, protectedId]), guardianId, protectedId);
}
