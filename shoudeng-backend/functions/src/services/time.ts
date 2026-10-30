import { bqTimestampToIso } from "./bigquery";

/**
 * Firestore Timestamp | Date | ISO string | BigQuery timestamp wrapper → ISO-8601
 * (or null). Every timestamp that leaves the API must go through this so the iOS
 * strict ISO-8601 decoder can read it.
 */
export function toIso(v: unknown): string | null {
  if (v == null) return null;
  const maybeTs = v as { toDate?: () => Date };
  if (typeof maybeTs.toDate === "function") return bqTimestampToIso(maybeTs.toDate());
  return bqTimestampToIso(v);
}
