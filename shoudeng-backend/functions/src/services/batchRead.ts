import * as admin from "firebase-admin";

/**
 * Reads of many documents in a few round trips instead of one per item (the
 * N+1 pattern): getAll for documents known by id, `in` queries for "the X of each
 * of these people".
 */

/** Firestore allows at most 30 values in an `in` filter. */
export const IN_LIMIT = 30;
/** Documents fetched per getAll call (keeps each request a reasonable size). */
const GET_ALL_LIMIT = 100;

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * The documents with these ids in one collection, by id. Missing documents are
 * left out; duplicate and empty ids are ignored.
 */
export async function getDocsById(
  collection: string,
  ids: Iterable<string>,
): Promise<Map<string, FirebaseFirestore.DocumentData>> {
  const db = admin.firestore();
  const unique = [...new Set([...ids].filter((id) => typeof id === "string" && id.length > 0))];
  const found = new Map<string, FirebaseFirestore.DocumentData>();
  if (unique.length === 0) return found;
  const batches = await Promise.all(chunk(unique, GET_ALL_LIMIT)
    .map((part) => db.getAll(...part.map((id) => db.collection(collection).doc(id)))));
  for (const snaps of batches) {
    for (const snap of snaps) {
      if (snap.exists) found.set(snap.id, snap.data() ?? {});
    }
  }
  return found;
}

/**
 * Runs `query(part)` for each group of at most 30 values and returns every
 * document found. Use it for an `in` filter over a list that may be longer than 30.
 */
export async function docsWhereIn<T>(
  values: Iterable<T>,
  query: (part: T[]) => FirebaseFirestore.Query,
): Promise<FirebaseFirestore.QueryDocumentSnapshot[]> {
  const unique = [...new Set(values)];
  if (unique.length === 0) return [];
  const snaps = await Promise.all(chunk(unique, IN_LIMIT).map((part) => query(part).get()));
  return snaps.flatMap((s) => s.docs);
}
