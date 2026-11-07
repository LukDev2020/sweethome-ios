import * as admin from "firebase-admin";

// ---------------------------------------------------------------------------
// Rider profile (docs/rider-onboarding-plan.md)
// ---------------------------------------------------------------------------
//
// A rider is a protected person who rides for work: no third role. The user doc
// keeps why they use the app (`useCase`), which home they see (`homeStyle`, so it
// survives a new phone), and a small `riderProfile`: city, platforms, the partner
// organisation that brought them, and setup milestones (crew joined, first shift,
// lock-screen card on, setup finished). Milestones drive the "finish setting up"
// checklist and the onboarding funnel; they hold dates only, no location.

export const USE_CASES = ["personal", "rider", "guardian"] as const;
export const HOME_STYLES = ["standard", "simple", "rider"] as const;
export const PLATFORMS = [
  "ubereats", "doordash", "deliveroo", "menulog", "meituan", "eleme", "uber", "didi",
  "grab", "foodpanda", "glovo", "lyft", "other",
] as const;
/** Milestones the phone may report; the rest are set by the server when they happen */
export const CLIENT_MILESTONES = ["lockCard", "setupDone"] as const;
export type Milestone = "crew" | "firstShift" | "lockCard" | "setupDone";

/** A rider counts as active with a shift in the last 30 days (or set up in the last 30). */
export const ACTIVE_RIDER_MS = 30 * 24 * 3600_000;

const db = () => admin.firestore();
const now = () => admin.firestore.Timestamp.now();

export class ProfileFieldError extends Error {}

/**
 * Validates the rider fields of PUT /v1/user/me. Returns Firestore field-path
 * updates (so a partial update never wipes the rest of the profile).
 */
export function riderProfileUpdates(body: Record<string, unknown>): Record<string, unknown> {
  const updates: Record<string, unknown> = {};
  const { useCase, homeStyle, riderProfile } = body;
  if (useCase !== undefined) {
    if (!(USE_CASES as readonly unknown[]).includes(useCase)) throw new ProfileFieldError("useCase must be personal, rider or guardian");
    updates.useCase = useCase;
  }
  if (homeStyle !== undefined) {
    if (!(HOME_STYLES as readonly unknown[]).includes(homeStyle)) throw new ProfileFieldError("homeStyle must be standard, simple or rider");
    updates.homeStyle = homeStyle;
  }
  if (riderProfile !== undefined) {
    if (!riderProfile || typeof riderProfile !== "object" || Array.isArray(riderProfile)) {
      throw new ProfileFieldError("riderProfile must be an object");
    }
    const p = riderProfile as Record<string, unknown>;
    if (p.city !== undefined) {
      if (typeof p.city !== "string" || p.city.length > 100) throw new ProfileFieldError("riderProfile.city must be ≤ 100 characters");
      updates["riderProfile.city"] = p.city.trim();
    }
    if (p.platforms !== undefined) {
      if (!Array.isArray(p.platforms) || p.platforms.length > PLATFORMS.length
          || !p.platforms.every((x) => (PLATFORMS as readonly unknown[]).includes(x))) {
        throw new ProfileFieldError(`riderProfile.platforms must be from: ${PLATFORMS.join(", ")}`);
      }
      updates["riderProfile.platforms"] = [...new Set(p.platforms as string[])];
    }
    if (p.milestones !== undefined) {
      if (!p.milestones || typeof p.milestones !== "object") throw new ProfileFieldError("riderProfile.milestones must be an object");
      for (const [k, v] of Object.entries(p.milestones as Record<string, unknown>)) {
        if (!(CLIENT_MILESTONES as readonly string[]).includes(k) || v !== true) {
          throw new ProfileFieldError(`riderProfile.milestones accepts only ${CLIENT_MILESTONES.join(", ")}: true`);
        }
        updates[`riderProfile.milestones.${k}At`] = now();
      }
    }
  }
  if (updates.useCase === "rider" || updates.homeStyle === "rider") {
    updates["riderProfile.onboardedAt"] = now();
  }
  return updates;
}

/** Set a milestone the first time it happens (later ones keep the first date). */
export async function markMilestone(uid: string, milestone: Milestone): Promise<void> {
  try {
    const ref = db().collection("users").doc(uid);
    const current = (await ref.get()).data()?.riderProfile?.milestones?.[`${milestone}At`];
    if (current) return;
    // Field path: never touches the rest of the profile
    await ref.update({ [`riderProfile.milestones.${milestone}At`]: now() });
  } catch (error) {
    console.warn(`[RiderProfile] milestone ${milestone} not saved:`, error);
  }
}

/** A shift started: first shift (once) and the last one (for "active rider"). */
export async function noteShiftStarted(uid: string): Promise<void> {
  await markMilestone(uid, "firstShift");
  await db().collection("users").doc(uid)
    .update({ "riderProfile.lastShiftAt": now() })
    .catch((e) => console.warn("[RiderProfile] lastShiftAt not saved:", e));
}

const toIso = (v: unknown): string | null =>
  v && typeof (v as { toDate?: () => Date }).toDate === "function" ? (v as { toDate: () => Date }).toDate().toISOString() : null;

/** What the phone gets back in GET /v1/user/me. */
export function riderProfileView(data: FirebaseFirestore.DocumentData, at: Date = new Date()) {
  const p = (data.riderProfile ?? {}) as Record<string, unknown>;
  const m = (p.milestones ?? {}) as Record<string, unknown>;
  const isRider = data.useCase === "rider" || data.homeStyle === "rider";
  const last = toIso(p.lastShiftAt) ?? toIso(p.onboardedAt);
  return {
    useCase: (data.useCase as string) ?? null,
    homeStyle: (data.homeStyle as string) ?? null,
    riderProfile: isRider || p.onboardedAt || p.partnerOrgName ? {
      city: (p.city as string) ?? null,
      platforms: Array.isArray(p.platforms) ? p.platforms : [],
      partnerOrg: (p.partnerOrgName as string) ?? null,
      onboardedAt: toIso(p.onboardedAt),
      milestones: {
        crewAt: toIso(m.crewAt),
        firstShiftAt: toIso(m.firstShiftAt),
        lockCardAt: toIso(m.lockCardAt),
        setupDoneAt: toIso(m.setupDoneAt),
      },
      // Rider features (crew, shifts, crew SOS, rider lock-screen card) are free on
      // every plan; "active" is shown to riders and used for partner reporting.
      riderFree: {
        included: ["crew", "shifts", "crew_sos", "rider_lock_card", "basic_sos", "1_guardian"],
        active: !!last && at.getTime() - Date.parse(last) < ACTIVE_RIDER_MS,
      },
    } : null,
  };
}

/**
 * Onboarding funnel over riders who started in [since, until): how many reached each
 * step. Counts only — run by an operator (scripts/rider-funnel.js).
 */
export async function riderFunnel(since: Date, until: Date = new Date()) {
  const snap = await db().collection("users")
    .where("riderProfile.onboardedAt", ">=", admin.firestore.Timestamp.fromDate(since))
    .where("riderProfile.onboardedAt", "<", admin.firestore.Timestamp.fromDate(until))
    .get();
  const counts = { started: 0, crew: 0, watcher: 0, lockCard: 0, setupDone: 0, firstShift: 0, firstShiftWithin7dFullyWatched: 0 };
  for (const doc of snap.docs) {
    const d = doc.data();
    const m = d.riderProfile?.milestones ?? {};
    counts.started++;
    if (m.crewAt) counts.crew++;
    if (m.lockCardAt) counts.lockCard++;
    if (m.setupDoneAt) counts.setupDone++;
    const hasWatcher = !(await db().collection("guardian_links")
      .where("protectedPersonId", "==", doc.id).where("status", "==", "active").limit(1).get()).empty;
    if (hasWatcher) counts.watcher++;
    if (m.firstShiftAt) {
      counts.firstShift++;
      const onboarded = d.riderProfile.onboardedAt.toMillis();
      if (m.crewAt && hasWatcher && m.firstShiftAt.toMillis() - onboarded < 7 * 24 * 3600_000) {
        counts.firstShiftWithin7dFullyWatched++;
      }
    }
  }
  return counts;
}
