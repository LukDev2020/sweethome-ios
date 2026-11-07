/**
 * The BigQuery tables created by tools/bigquery/setup.sh must match what the
 * functions write and read: every inserted field is a column, every column
 * without a default is written, REQUIRED columns are never null, and every
 * table the code touches is created by the script.
 */
const mockInserted: Record<string, Record<string, unknown>[]> = {};
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: (ds: string) => ({
      table: (t: string) => ({
        insert: jest.fn(async (rows: Record<string, unknown>[]) => {
          (mockInserted[`${ds}.${t}`] ??= []).push(...rows);
        }),
      }),
    }),
  })),
}));

import * as fs from "fs";
import * as path from "path";
import { insertHeartbeat, insertLocationReport, insertCheckin, insertConsentAudit } from "../services/bigquery";
import { BIGQUERY_PERSONAL_TABLES } from "../services/accountData";

const ROOT = path.join(__dirname, "..", "..", "..", "..");
const TOOLS = path.join(ROOT, "tools", "bigquery");
const SRC = path.join(__dirname, "..");

type Field = { name: string; type: string; mode: string; defaultValueExpression?: string };
const schema = (table: string): Field[] =>
  JSON.parse(fs.readFileSync(path.join(TOOLS, "schemas", `${table}.json`), "utf8"));
const schemaTables = () =>
  fs.readdirSync(path.join(TOOLS, "schemas")).filter((f) => f.endsWith(".json")).map((f) => f.replace(/\.json$/, "")).sort();

jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

beforeAll(async () => {
  const timestamp = "2026-11-02T10:00:00.000Z";
  await insertHeartbeat({
    userId: "u1", timestamp, source: "timer", batteryLevel: 0.5, batteryState: "unplugged",
    latitude: 1, longitude: 2, accuracy: 3,
  });
  await insertLocationReport({
    userId: "u1", timestamp, latitude: 1, longitude: 2, accuracy: 3, altitude: 4, speed: 5,
    isInSafeZone: true, safeZoneName: "Home", activityType: "walking",
  });
  await insertCheckin({ userId: "u1", timestamp, latitude: 1, longitude: 2, note: "ok" });
  await insertConsentAudit({
    userId: "u1", consentType: "location", action: "granted", grantedTo: "g1",
    detail: "d", ipAddress: "1.2.3.4", deviceInfo: "iPhone",
  });
});

describe.each(["heartbeat_signals", "location_reports", "checkins", "consent_audit"])("%s", (table) => {
  const row = () => {
    const rows = mockInserted[`shoudeng.${table}`];
    expect(rows).toHaveLength(1);
    return rows[0];
  };

  it("every inserted field is a column, and every column without a default is inserted", () => {
    const fields = schema(table);
    const inserted = Object.keys(row()).sort();
    const writable = fields.filter((f) => !f.defaultValueExpression).map((f) => f.name).sort();
    expect(inserted).toEqual(writable);
  });

  it("REQUIRED columns are written non-null", () => {
    for (const f of schema(table).filter((f) => f.mode === "REQUIRED")) {
      expect({ column: f.name, value: row()[f.name] ?? null }).not.toEqual({ column: f.name, value: null });
    }
  });

  it("types match the values written", () => {
    const r = row();
    for (const f of schema(table)) {
      const v = r[f.name];
      if (v == null) continue;
      const ok = {
        STRING: typeof v === "string",
        FLOAT64: typeof v === "number",
        BOOL: typeof v === "boolean",
        TIMESTAMP: typeof v === "string" && !isNaN(Date.parse(v as string)),
      }[f.type];
      expect({ column: f.name, type: f.type, ok }).toEqual({ column: f.name, type: f.type, ok: true });
    }
  });

  it("has the columns every reader filters/sorts on (user_id, timestamp, row_hash)", () => {
    const names = schema(table).map((f) => f.name);
    expect(names).toEqual(expect.arrayContaining(["id", "user_id", "timestamp", "row_hash"]));
    expect(schema(table).find((f) => f.name === "timestamp")).toMatchObject({ type: "TIMESTAMP", mode: "REQUIRED" });
  });
});

describe("tables referenced by the code exist in the setup script", () => {
  const sources = () => {
    const out: string[] = [];
    const walk = (dir: string) => {
      for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) { if (e.name !== "__tests__") walk(p); } else if (p.endsWith(".ts")) out.push(fs.readFileSync(p, "utf8"));
      }
    };
    walk(SRC);
    return out.join("\n");
  };

  it("insert targets, ${DATASET}.x queries, retention and integrity-proof tables", () => {
    const code = sources();
    const referenced = new Set<string>([
      ...[...code.matchAll(/\.table\("([a-z_]+)"\)/g)].map((m) => m[1]),
      ...[...code.matchAll(/\$\{DATASET\}\.([a-z_]+)/g)].map((m) => m[1]),
      ...[...code.matchAll(/computeDailyMerkleRoot\("([a-z_]+)"/g)].map((m) => m[1]),
      ...BIGQUERY_PERSONAL_TABLES,
    ]);
    expect(referenced.size).toBeGreaterThanOrEqual(4);
    for (const t of referenced) expect(schemaTables()).toContain(t);
  });

  it("setup.sh creates exactly the tables in schemas/, partitioned on timestamp and clustered by user_id", () => {
    const sh = fs.readFileSync(path.join(TOOLS, "setup.sh"), "utf8");
    const listed = (sh.match(/^TABLES=\(([^)]*)\)/m)?.[1] ?? "").trim().split(/\s+/).sort();
    expect(listed).toEqual(schemaTables());
    expect(sh).toMatch(/^DATASET="shoudeng"$/m);
    expect(sh).toContain("--time_partitioning_field=timestamp");
    expect(sh).toContain("--time_partitioning_type=DAY");
    expect(sh).toContain("--clustering_fields=user_id");
  });

  it("the dataset name matches the code", () => {
    for (const f of ["services/bigquery.ts", "services/accountData.ts"]) {
      expect(fs.readFileSync(path.join(SRC, f), "utf8")).toMatch(/const DATASET = "shoudeng";/);
    }
  });

  it("shoudeng-backend/bigquery/schema.sql (reference DDL) has the same columns", () => {
    const sql = fs.readFileSync(path.join(ROOT, "shoudeng-backend", "bigquery", "schema.sql"), "utf8");
    for (const table of schemaTables()) {
      const body = sql.match(new RegExp(`CREATE TABLE IF NOT EXISTS shoudeng\\.${table} \\(([\\s\\S]*?)\\n\\)`))?.[1];
      expect(body).toBeDefined();
      const cols = body!.split("\n").map((l) => l.trim().match(/^([a-z_]+)\s+[A-Z]/)?.[1]).filter(Boolean).sort();
      expect({ table, cols }).toEqual({ table, cols: schema(table).map((f) => f.name).sort() });
    }
  });
});
