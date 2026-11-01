import * as admin from "firebase-admin";
import { BigQuery } from "@google-cloud/bigquery";
import { PLANS, PlanId, hasPaidAccess, SUBSCRIPTION_OWNERS } from "./payment";

// Account data rights: export, erasure, and per-plan retention.
// The in-app privacy policy (iOS LegalView.swift) describes exactly what this does —
// change both together.

const db = admin.firestore();
const bigquery = new BigQuery();
const DATASET = "shoudeng";


/** BigQuery tables holding personal history, keyed by user_id. consent_audit is kept on purpose. */
export const BIGQUERY_PERSONAL_TABLES = ["location_reports", "heartbeat_signals", "checkins"] as const;
type PersonalTable = typeof BIGQUERY_PERSONAL_TABLES[number];

/** `shoudeng.table` — table names come from the fixed list above, never from input. */
const tableRef = (table: PersonalTable) => "`" + DATASET + "." + table + "`";

type Retention = { heartbeat: number; location: number; checkin: number };

// MARK: - Retention

// Same rule as feature access: refunded, expired or transferred subscriptions don't count
function isPaidActive(data: FirebaseFirestore.DocumentData | undefined): data is { planId: PlanId } {
  return hasPaidAccess(data);
}

function longer(a: Retention, b: Retention): Retention {
  const pick = (x: number, y: number) => (x === -1 || y === -1 ? -1 : Math.max(x, y));
  return { heartbeat: pick(a.heartbeat, b.heartbeat), location: pick(a.location, b.location), checkin: pick(a.checkin, b.checkin) };
}

/**
 * Retention for everyone covered by a paid plan: the subscriber, and the people they
 * protect (the guardian pays for the family). Anyone not in the map is on the free plan.
 */
export async function paidRetentionByUser(): Promise<Map<string, Retention>> {
  const result = new Map<string, Retention>();
  const subs = await db.collection("subscriptions").where("planId", "!=", "free").get();
  const paid: { uid: string; ttl: Retention }[] = [];
  for (const doc of subs.docs) {
    const data = doc.data();
    if (isPaidActive(data)) paid.push({ uid: doc.id, ttl: PLANS[data.planId].ttlDays });
  }
  const add = (uid: string, ttl: Retention) => result.set(uid, result.has(uid) ? longer(result.get(uid)!, ttl) : ttl);
  for (const { uid, ttl } of paid) {
    add(uid, ttl);
    const links = await db.collection("guardian_links")
      .where("guardianId", "==", uid).where("status", "==", "active").get();
    links.docs.forEach((l) => add(l.data().protectedPersonId, ttl));
  }
  return result;
}

const TABLE_FIELD: Record<PersonalTable, keyof Retention> = {
  location_reports: "location", heartbeat_signals: "heartbeat", checkins: "checkin",
};

export interface RetentionPlan {
  table: PersonalTable;
  days: number;
  /** Delete rows of exactly these users (paid buckets)… */
  onlyUsers?: string[];
  /** …or of everyone except these (the free bucket). */
  exceptUsers?: string[];
}

/** One DELETE per table and retention length. Pure, so it can be unit-tested. */
export function retentionPlan(paid: Map<string, Retention>): RetentionPlan[] {
  const plans: RetentionPlan[] = [];
  for (const table of BIGQUERY_PERSONAL_TABLES) {
    const field = TABLE_FIELD[table];
    const buckets = new Map<number, string[]>();
    for (const [uid, ttl] of paid) {
      const days = ttl[field];
      if (!buckets.has(days)) buckets.set(days, []);
      buckets.get(days)!.push(uid);
    }
    plans.push({ table, days: PLANS.free.ttlDays[field], exceptUsers: [...paid.keys()] });
    for (const [days, users] of buckets) {
      if (days !== -1) plans.push({ table, days, onlyUsers: users });
    }
  }
  return plans.filter((p) => p.days !== -1);
}

export interface EvidenceHold { protectedPersonId: string; start: Date; end: Date }

function holdClause(holds: EvidenceHold[], params: Record<string, unknown>): string {
  return holds.map((h, i) => {
    params[`hold_uid_${i}`] = h.protectedPersonId;
    params[`hold_start_${i}`] = h.start.toISOString();
    params[`hold_end_${i}`] = h.end.toISOString();
    return ` AND NOT (user_id = @hold_uid_${i} AND timestamp BETWEEN @hold_start_${i} AND @hold_end_${i})`;
  }).join("");
}

/** Apply per-plan retention to BigQuery. Rows under an active evidence hold are kept. */
export async function applyBigQueryRetention(holds: EvidenceHold[]): Promise<void> {
  const plans = retentionPlan(await paidRetentionByUser());
  for (const p of plans) {
    const params: Record<string, unknown> = {
      cutoff: new Date(Date.now() - p.days * 86400_000).toISOString(),
    };
    const types: Record<string, string[]> = {};
    let users = "";
    if (p.onlyUsers) {
      params.users = p.onlyUsers; types.users = ["STRING"];
      users = " AND user_id IN UNNEST(@users)";
    } else if (p.exceptUsers && p.exceptUsers.length > 0) {
      params.users = p.exceptUsers; types.users = ["STRING"];
      users = " AND user_id NOT IN UNNEST(@users)";
    }
    const query = "DELETE FROM " + tableRef(p.table) + " WHERE timestamp < @cutoff" + users + holdClause(holds, params);
    try {
      const [job] = await bigquery.createQueryJob({ query, params, types: types as never });
      await job.getQueryResults();
      console.log(`[Retention] ${p.table}: ${p.days}d for ${p.onlyUsers ? p.onlyUsers.length + " paid users" : "free plan"}`);
    } catch (error) {
      console.error(`[Retention] ${p.table} ${p.days}d failed:`, error);
    }
  }
}

/** Firestore copies of history: arrival check-ins and recorded trips. */
export async function applyFirestoreRetention(): Promise<void> {
  const paid = await paidRetentionByUser();
  const retentionFor = (uid: string) => paid.get(uid) ?? PLANS.free.ttlDays;
  const shortest = (field: keyof Retention) => PLANS.free.ttlDays[field];

  const oldCheckins = await db.collection("checkins")
    .where("timestamp", "<", admin.firestore.Timestamp.fromMillis(Date.now() - shortest("checkin") * 86400_000))
    .limit(2000).get();
  let removed = 0;
  for (const doc of oldCheckins.docs) {
    const days = retentionFor(doc.data().userId).checkin;
    const ts = doc.data().timestamp?.toMillis?.() ?? 0;
    if (days !== -1 && ts < Date.now() - days * 86400_000) { await doc.ref.delete(); removed++; }
  }

  const oldTrips = await db.collection("trips")
    .where("startTime", "<", admin.firestore.Timestamp.fromMillis(Date.now() - shortest("location") * 86400_000))
    .limit(500).get();
  let trips = 0;
  for (const doc of oldTrips.docs) {
    const days = retentionFor(doc.data().userId).location;
    const ts = doc.data().startTime?.toMillis?.() ?? 0;
    if (days !== -1 && ts < Date.now() - days * 86400_000) { await db.recursiveDelete(doc.ref); trips++; }
  }
  console.log(`[Retention] Firestore: ${removed} check-ins, ${trips} trips removed`);
}

// MARK: - Erasure

/**
 * Rows still in BigQuery's streaming buffer (written in the last ~90 minutes) can't be
 * deleted yet; those deletions are queued and retried by the daily cleanup.
 */
export async function deleteBigQueryRows(uid: string): Promise<boolean> {
  let complete = true;
  for (const table of BIGQUERY_PERSONAL_TABLES) {
    try {
      const [job] = await bigquery.createQueryJob({
        query: "DELETE FROM " + tableRef(table) + " WHERE user_id = @uid",
        params: { uid },
      });
      await job.getQueryResults();
    } catch (error) {
      complete = false;
      console.warn(`[Erase] ${table} for ${uid} deferred:`, (error as Error).message);
    }
  }
  if (!complete) {
    await db.collection("pending_deletions").doc(uid).set({
      uid, createdAt: admin.firestore.Timestamp.now(), attempts: 0,
    });
  }
  return complete;
}

/** Retry queued BigQuery erasures (daily). */
export async function processPendingDeletions(): Promise<number> {
  const pending = await db.collection("pending_deletions").limit(200).get();
  let done = 0;
  for (const doc of pending.docs) {
    if (await deleteBigQueryRows(doc.id)) {
      await doc.ref.delete();
      done++;
    } else {
      await doc.ref.update({ attempts: admin.firestore.FieldValue.increment(1) });
    }
  }
  return done;
}

async function deleteWhere(query: FirebaseFirestore.Query): Promise<number> {
  const snap = await query.get();
  for (const doc of snap.docs) await db.recursiveDelete(doc.ref);
  return snap.size;
}

/**
 * Erase everything stored about this person. Kept on purpose (and said so in the policy):
 * consent_audit (legal record of consent), evidence_holds (legal holds; files expire in 90 days).
 */
export async function eraseAccount(uid: string): Promise<{ bigQueryComplete: boolean }> {
  // Docs keyed by uid; recursiveDelete also removes subcollections
  // (users/{uid}/ble_tags, ble_sightings, timeline).
  const byId = ["users", "subscriptions", "home_timers", "medical_cards", "selected_hotlines",
    "user_telemetry", "emergency_contacts", "silent_alarm_schedules"];
  await Promise.all(byId.map((c) => db.recursiveDelete(db.collection(c).doc(uid))));

  await Promise.all([
    deleteWhere(db.collection("device_tokens").where("userId", "==", uid)),
    deleteWhere(db.collection("guardian_links").where("guardianId", "==", uid)),
    deleteWhere(db.collection("guardian_links").where("protectedPersonId", "==", uid)),
    deleteWhere(db.collection("duty_schedules").where("guardianId", "==", uid)),
    deleteWhere(db.collection("duty_schedules").where("protectedPersonId", "==", uid)),
    deleteWhere(db.collection("checkins").where("userId", "==", uid)),
    deleteWhere(db.collection("timeline_entries").where("userId", "==", uid)),
    deleteWhere(db.collection("safe_zones").where("userId", "==", uid)),
    deleteWhere(db.collection("arrival_reports").where("userId", "==", uid)),
    deleteWhere(db.collection("itineraries").where("userId", "==", uid)),
    deleteWhere(db.collection("invites").where("createdBy", "==", uid)),
    deleteWhere(db.collection("crash_reports").where("userId", "==", uid)),
    deleteWhere(db.collection("evidence_shares").where("createdBy", "==", uid)),
    deleteWhere(db.collection("medical_card_shares").where("userId", "==", uid)),
    deleteWhere(db.collection("trips").where("userId", "==", uid)),           // + points
    deleteWhere(db.collection("sos_events").where("protectedPersonId", "==", uid)), // + voice_notes
    deleteWhere(db.collection("family_posts").where("authorId", "==", uid)), // + comments
    deleteWhere(db.collection(SUBSCRIPTION_OWNERS).where("uid", "==", uid)), // frees the Apple subscription
  ]);

  try {
    await admin.storage().bucket().deleteFiles({ prefix: `family/${uid}/` });
  } catch (error) {
    console.warn(`[Erase] family media for ${uid}:`, error);
  }

  return { bigQueryComplete: await deleteBigQueryRows(uid) };
}

// MARK: - Export

const rows = (snap: FirebaseFirestore.QuerySnapshot) => snap.docs.map((d) => ({ id: d.id, ...d.data() }));

async function bigQueryHistory(uid: string, table: PersonalTable): Promise<Record<string, unknown>[]> {
  try {
    const [result] = await bigquery.query({
      query: "SELECT * FROM " + tableRef(table) + " WHERE user_id = @uid ORDER BY timestamp DESC LIMIT 50000",
      params: { uid },
    });
    return result as Record<string, unknown>[];
  } catch (error) {
    console.warn(`[Export] ${table} for ${uid}:`, error);
    return [];
  }
}

/** Everything we hold about this person, as one JSON document. */
export async function exportAccount(uid: string): Promise<Record<string, unknown>> {
  const doc = async (c: string) => {
    const d = await db.collection(c).doc(uid).get();
    return d.exists ? d.data() : null;
  };
  const sub = async (c: string) => rows(await db.collection("users").doc(uid).collection(c).get());
  const where = async (c: string, field: string) => rows(await db.collection(c).where(field, "==", uid).get());

  const [profile, medicalCard, emergencyContacts, homeTimer, silentAlarm, telemetry, hotline] = await Promise.all(
    ["users", "medical_cards", "emergency_contacts", "home_timers", "silent_alarm_schedules", "user_telemetry", "selected_hotlines"].map(doc)
  );

  const tripsSnap = await db.collection("trips").where("userId", "==", uid).get();
  const trips = await Promise.all(tripsSnap.docs.map(async (t) => ({
    id: t.id, ...t.data(), points: rows(await t.ref.collection("points").get()),
  })));

  const sosSnap = await db.collection("sos_events").where("protectedPersonId", "==", uid).get();
  const sosEvents = await Promise.all(sosSnap.docs.map(async (s) => ({
    id: s.id, ...s.data(), voiceNotes: rows(await s.ref.collection("voice_notes").get()),
  })));

  return {
    exportedAt: new Date().toISOString(),
    userId: uid,
    profile, medicalCard, emergencyContacts, homeTimer, silentAlarm,
    lastKnownLocation: telemetry, selectedHotline: hotline,
    guardianLinks: {
      asGuardian: await where("guardian_links", "guardianId"),
      asProtected: await where("guardian_links", "protectedPersonId"),
    },
    dutySchedules: {
      asGuardian: await where("duty_schedules", "guardianId"),
      asProtected: await where("duty_schedules", "protectedPersonId"),
    },
    checkins: await where("checkins", "userId"),
    arrivalReports: await where("arrival_reports", "userId"),
    timeline: await where("timeline_entries", "userId"),
    safeZones: await where("safe_zones", "userId"),
    itineraries: await where("itineraries", "userId"),
    familyPosts: await where("family_posts", "authorId"),
    sosEvents,
    trips,
    bluetoothTags: await sub("ble_tags"),
    bluetoothSightings: await sub("ble_sightings"),
    locationHistory: await bigQueryHistory(uid, "location_reports"),
    heartbeatHistory: await bigQueryHistory(uid, "heartbeat_signals"),
    checkinHistory: await bigQueryHistory(uid, "checkins"),
    deviceTokenCount: (await db.collection("device_tokens").where("userId", "==", uid).get()).size,
  };
}
