/**
 * In-memory stand-in for the parts of firebase-admin the backend uses, so route
 * tests can mount the REAL routers instead of re-implementing their logic.
 *
 * Usage (top of a test file):
 *   jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
 *   import { fakeDb, resetFakeAdmin, sentMessages } from "./helpers/fakeAdmin";
 *
 * Fidelity notes:
 *  - `where(f, "==", null)` only matches docs whose field is explicitly null (as Firestore).
 *  - Queries that need a composite index are checked against firestore.indexes.json and
 *    throw FAILED_PRECONDITION like production does when the index is missing.
 */
import * as fs from "fs";
import * as path from "path";

// ---------------------------------------------------------------------------
// Timestamp / FieldValue
// ---------------------------------------------------------------------------

export class FakeTimestamp {
  constructor(public readonly seconds: number, public readonly nanoseconds: number) {}
  static now(): FakeTimestamp {
    return FakeTimestamp.fromMillis(Date.now());
  }
  static fromDate(d: Date): FakeTimestamp {
    return FakeTimestamp.fromMillis(d.getTime());
  }
  static fromMillis(ms: number): FakeTimestamp {
    return new FakeTimestamp(Math.floor(ms / 1000), (ms % 1000) * 1e6);
  }
  toMillis(): number {
    return this.seconds * 1000 + Math.floor(this.nanoseconds / 1e6);
  }
  toDate(): Date {
    return new Date(this.toMillis());
  }
  isEqual(o: FakeTimestamp): boolean {
    return o instanceof FakeTimestamp && o.toMillis() === this.toMillis();
  }
}

class FieldValueSentinel {
  constructor(public readonly kind: string, public readonly arg?: unknown) {}
}

export const FakeFieldValue = {
  serverTimestamp: () => new FieldValueSentinel("serverTimestamp"),
  increment: (n: number) => new FieldValueSentinel("increment", n),
  arrayUnion: (...items: unknown[]) => new FieldValueSentinel("arrayUnion", items),
  arrayRemove: (...items: unknown[]) => new FieldValueSentinel("arrayRemove", items),
  delete: () => new FieldValueSentinel("delete"),
};

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

type Data = Record<string, any>;
const store = new Map<string, Data>(); // full doc path -> data
let autoId = 0;

function clone<T>(v: T): T {
  if (v instanceof FakeTimestamp) return v;
  if (Array.isArray(v)) return v.map(clone) as any;
  if (v && typeof v === "object" && !(v instanceof FieldValueSentinel)) {
    const out: Data = {};
    for (const [k, val] of Object.entries(v)) out[k] = clone(val);
    return out as T;
  }
  return v;
}

function getField(data: Data, field: string): unknown {
  return field.split(".").reduce<any>((acc, k) => (acc == null ? undefined : acc[k]), data);
}

function setField(data: Data, field: string, value: unknown) {
  const parts = field.split(".");
  let cur = data;
  for (const p of parts.slice(0, -1)) {
    if (cur[p] == null || typeof cur[p] !== "object") cur[p] = {};
    cur = cur[p];
  }
  const last = parts[parts.length - 1];
  if (value === undefined) delete cur[last];
  else cur[last] = value;
}

function applyValue(existing: unknown, v: unknown): unknown {
  if (!(v instanceof FieldValueSentinel)) return clone(v);
  switch (v.kind) {
    case "serverTimestamp": return FakeTimestamp.now();
    case "increment": return (typeof existing === "number" ? existing : 0) + (v.arg as number);
    case "arrayUnion": {
      const arr = Array.isArray(existing) ? [...existing] : [];
      for (const it of v.arg as unknown[]) if (!arr.some((a) => JSON.stringify(a) === JSON.stringify(it))) arr.push(clone(it));
      return arr;
    }
    case "arrayRemove": {
      const arr = Array.isArray(existing) ? existing : [];
      return arr.filter((a) => !(v.arg as unknown[]).some((it) => JSON.stringify(a) === JSON.stringify(it)));
    }
    case "delete": return undefined;
  }
  return undefined;
}

function writeDoc(p: string, data: Data, mode: "set" | "merge" | "update") {
  const existing = store.get(p);
  if (mode === "update" && !existing) {
    const err: any = new Error(`NOT_FOUND: No document to update: ${p}`);
    err.code = 5;
    throw err;
  }
  const base: Data = mode === "set" ? {} : clone(existing ?? {});
  for (const [k, v] of Object.entries(data)) {
    if (mode === "update") setField(base, k, applyValue(getField(base, k), v));
    else if (mode === "merge" && v && typeof v === "object" && !(v instanceof FieldValueSentinel) &&
             !(v instanceof FakeTimestamp) && !Array.isArray(v)) {
      const sub = clone(base[k] ?? {});
      for (const [sk, sv] of Object.entries(v)) sub[sk] = applyValue(sub[sk], sv);
      base[k] = sub;
    } else {
      const nv = applyValue(base[k], v);
      if (nv === undefined) delete base[k]; else base[k] = nv;
    }
  }
  store.set(p, base);
}

// ---------------------------------------------------------------------------
// Composite-index checking
// ---------------------------------------------------------------------------

interface IndexDef { collectionGroup: string; fields: { fieldPath: string; order?: string; arrayConfig?: string }[] }
let indexDefs: IndexDef[] | null = null;
export let enforceIndexes = true;
export function setEnforceIndexes(v: boolean) { enforceIndexes = v; }

function loadIndexes(): IndexDef[] {
  if (!indexDefs) {
    const file = path.resolve(__dirname, "../../../../firestore.indexes.json");
    indexDefs = JSON.parse(fs.readFileSync(file, "utf8")).indexes as IndexDef[];
  }
  return indexDefs;
}
export function reloadIndexes() { indexDefs = null; }

interface Filter { field: string; op: string; value: unknown }
interface Order { field: string; dir: "asc" | "desc" }

const EQUALITY_OPS = new Set(["==", "in", "array-contains", "array-contains-any"]);

/** Throws if Firestore would require a composite index that isn't declared. */
export function checkIndex(collection: string, filters: Filter[], orders: Order[]) {
  if (!enforceIndexes) return;
  const eq = filters.filter((f) => EQUALITY_OPS.has(f.op));
  const range = filters.filter((f) => !EQUALITY_OPS.has(f.op));
  const fields = new Set([...filters.map((f) => f.field), ...orders.map((o) => o.field)]);
  if (fields.size <= 1) return; // single-field index (automatic)
  if (range.length === 0 && orders.length === 0 && !eq.some((f) => f.op.startsWith("array"))) return; // equality-only → index merge

  // Required shape: equality fields (any order), then order/range fields in sequence.
  const tail: Order[] = [...orders];
  for (const r of range) if (!tail.some((o) => o.field === r.field)) tail.unshift({ field: r.field, dir: "asc" });
  const eqFields = new Set(eq.map((f) => f.field).filter((f) => !tail.some((o) => o.field === f)));

  const ok = loadIndexes().some((idx) => {
    if (idx.collectionGroup !== collection) return false;
    if (idx.fields.length !== eqFields.size + tail.length) return false;
    const head = idx.fields.slice(0, eqFields.size);
    if (!head.every((f) => eqFields.has(f.fieldPath))) return false;
    for (const f of head) {
      const filt = eq.find((e) => e.field === f.fieldPath)!;
      const wantsContains = filt.op.startsWith("array");
      if (wantsContains !== (f.arrayConfig === "CONTAINS")) return false;
    }
    return tail.every((o, i) => {
      const f = idx.fields[eqFields.size + i];
      return f.fieldPath === o.field && (f.order ?? "ASCENDING") === (o.dir === "desc" ? "DESCENDING" : "ASCENDING");
    });
  });
  if (!ok) {
    const desc = [...[...eqFields].map((f) => `${f} ==`), ...tail.map((o) => `${o.field} ${o.dir}`)].join(", ");
    const err: any = new Error(`FAILED_PRECONDITION: The query requires an index. collection=${collection} fields=[${desc}]`);
    err.code = 9;
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Refs / Queries
// ---------------------------------------------------------------------------

function cmp(a: any, b: any): number {
  if (a instanceof FakeTimestamp) a = a.toMillis();
  if (b instanceof FakeTimestamp) b = b.toMillis();
  if (a instanceof Date) a = a.getTime();
  if (b instanceof Date) b = b.getTime();
  if (a === b) return 0;
  if (a === undefined || a === null) return -1;
  if (b === undefined || b === null) return 1;
  return a < b ? -1 : 1;
}

function matches(data: Data, f: Filter): boolean {
  const v = getField(data, f.field);
  switch (f.op) {
    case "==": return f.value === null ? v === null : v !== undefined && cmp(v, f.value) === 0;
    case "!=": return v !== undefined && cmp(v, f.value) !== 0;
    case "<": return v !== undefined && v !== null && cmp(v, f.value) < 0;
    case "<=": return v !== undefined && v !== null && cmp(v, f.value) <= 0;
    case ">": return v !== undefined && v !== null && cmp(v, f.value) > 0;
    case ">=": return v !== undefined && v !== null && cmp(v, f.value) >= 0;
    case "in": return (f.value as unknown[]).some((x) => cmp(v, x) === 0);
    case "not-in": return v !== undefined && !(f.value as unknown[]).some((x) => cmp(v, x) === 0);
    case "array-contains": return Array.isArray(v) && v.some((x) => cmp(x, f.value) === 0);
    case "array-contains-any": return Array.isArray(v) && v.some((x) => (f.value as unknown[]).some((y) => cmp(x, y) === 0));
  }
  throw new Error(`fakeAdmin: unsupported op ${f.op}`);
}

export class FakeDocSnapshot {
  constructor(public readonly ref: FakeDocRef, private readonly _data: Data | undefined) {}
  get exists() { return this._data !== undefined; }
  get id() { return this.ref.id; }
  data(): Data | undefined { return this._data === undefined ? undefined : clone(this._data); }
  get(field: string) { return this._data ? getField(this._data, field) : undefined; }
  get createTime() { return FakeTimestamp.now(); }
}

export class FakeDocRef {
  constructor(public readonly path: string) {}
  get id() { return this.path.split("/").pop()!; }
  get parent() { return new FakeCollectionRef(this.path.split("/").slice(0, -1).join("/")); }
  collection(name: string) { return new FakeCollectionRef(`${this.path}/${name}`); }
  async get() { return new FakeDocSnapshot(this, store.get(this.path)); }
  async set(data: Data, opts?: { merge?: boolean }) { writeDoc(this.path, data, opts?.merge ? "merge" : "set"); return {}; }
  async create(data: Data) {
    if (store.has(this.path)) { const e: any = new Error(`ALREADY_EXISTS: ${this.path}`); e.code = 6; throw e; }
    writeDoc(this.path, data, "set"); return {};
  }
  async update(data: Data) { writeDoc(this.path, data, "update"); return {}; }
  async delete() { store.delete(this.path); return {}; }
}

export class FakeQuery {
  constructor(
    protected readonly collPath: string,
    protected readonly filters: Filter[] = [],
    protected readonly orders: Order[] = [],
    protected readonly lim?: number,
    protected readonly startAfterValues?: unknown[],
  ) {}
  where(field: string, op: string, value: unknown) {
    return new FakeQuery(this.collPath, [...this.filters, { field, op, value }], this.orders, this.lim, this.startAfterValues);
  }
  orderBy(field: string, dir: "asc" | "desc" = "asc") {
    return new FakeQuery(this.collPath, this.filters, [...this.orders, { field, dir }], this.lim, this.startAfterValues);
  }
  limit(n: number) { return new FakeQuery(this.collPath, this.filters, this.orders, n, this.startAfterValues); }
  startAfter(...vals: unknown[]) {
    const v = vals[0] instanceof FakeDocSnapshot ? this.orders.map((o) => (vals[0] as FakeDocSnapshot).get(o.field)) : vals;
    return new FakeQuery(this.collPath, this.filters, this.orders, this.lim, v);
  }
  select() { return this; }
  private collectionName() { return this.collPath.split("/").pop()!; }
  private run(): FakeDocSnapshot[] {
    checkIndex(this.collectionName(), this.filters, this.orders);
    const depth = this.collPath.split("/").length + 1;
    let docs = [...store.entries()]
      .filter(([p]) => p.startsWith(this.collPath + "/") && p.split("/").length === depth)
      .filter(([, d]) => this.filters.every((f) => matches(d, f)))
      // orderBy excludes docs missing the field (as Firestore)
      .filter(([, d]) => this.orders.every((o) => getField(d, o.field) !== undefined))
      .map(([p, d]) => new FakeDocSnapshot(new FakeDocRef(p), d));
    if (this.orders.length) {
      docs.sort((a, b) => {
        for (const o of this.orders) {
          const c = cmp(a.get(o.field), b.get(o.field));
          if (c !== 0) return o.dir === "desc" ? -c : c;
        }
        return 0;
      });
    }
    if (this.startAfterValues) {
      const sv = this.startAfterValues;
      docs = docs.filter((d) => {
        for (let i = 0; i < this.orders.length && i < sv.length; i++) {
          const c = cmp(d.get(this.orders[i].field), sv[i]);
          if (c !== 0) return this.orders[i].dir === "desc" ? c < 0 : c > 0;
        }
        return false;
      });
    }
    if (this.lim !== undefined) docs = docs.slice(0, this.lim);
    return docs;
  }
  async get() {
    const docs = this.run();
    return { docs, empty: docs.length === 0, size: docs.length, forEach: (fn: (d: FakeDocSnapshot) => void) => docs.forEach(fn) };
  }
  count() {
    return { get: async () => { const n = this.run().length; return { data: () => ({ count: n }) }; } };
  }
}

export class FakeCollectionRef extends FakeQuery {
  constructor(collPath: string) { super(collPath); }
  get id() { return this.collPath.split("/").pop()!; }
  get path() { return this.collPath; }
  doc(id?: string) { return new FakeDocRef(`${this.collPath}/${id ?? `auto_${++autoId}`}`); }
  async add(data: Data) { const ref = this.doc(); writeDoc(ref.path, data, "set"); return ref; }
}

// ---------------------------------------------------------------------------
// Transactions / batches
// ---------------------------------------------------------------------------

class FakeWriteBatch {
  private ops: (() => void)[] = [];
  set(ref: FakeDocRef, data: Data, opts?: { merge?: boolean }) { this.ops.push(() => writeDoc(ref.path, data, opts?.merge ? "merge" : "set")); return this; }
  update(ref: FakeDocRef, data: Data) { this.ops.push(() => writeDoc(ref.path, data, "update")); return this; }
  delete(ref: FakeDocRef) { this.ops.push(() => store.delete(ref.path)); return this; }
  create(ref: FakeDocRef, data: Data) {
    this.ops.push(() => {
      if (store.has(ref.path)) { const e: any = new Error(`ALREADY_EXISTS: ${ref.path}`); e.code = 6; throw e; }
      writeDoc(ref.path, data, "set");
    });
    return this;
  }
  async commit() { for (const op of this.ops) op(); return []; }
}

class FakeTransaction extends FakeWriteBatch {
  async get(refOrQuery: FakeDocRef | FakeQuery) { return refOrQuery.get(); }
}

// ---------------------------------------------------------------------------
// Messaging / Auth
// ---------------------------------------------------------------------------

export const sentMessages: any[] = [];
export const failingTokens = new Set<string>();

const messaging = {
  sendEachForMulticast: async (msg: any) => {
    sentMessages.push(clone(msg));
    const responses = (msg.tokens as string[]).map((t) =>
      failingTokens.has(t)
        ? { success: false, error: { code: "messaging/registration-token-not-registered" } }
        : { success: true, messageId: `m_${sentMessages.length}` });
    const successCount = responses.filter((r) => r.success).length;
    return { successCount, failureCount: responses.length - successCount, responses };
  },
  send: async (msg: any) => { sentMessages.push(clone(msg)); return `m_${sentMessages.length}`; },
};

/** Map of bearer token -> uid accepted by verifyIdToken. */
export const validTokens = new Map<string, string>();

const auth = {
  verifyIdToken: async (token: string) => {
    const uid = validTokens.get(token);
    if (!uid) throw new Error("invalid token");
    return { uid };
  },
  createCustomToken: async (uid: string) => `custom_${uid}`,
  getUser: async (uid: string) => ({ uid }),
  deleteUser: async () => undefined,
  revokeRefreshTokens: async () => undefined,
};

// ---------------------------------------------------------------------------
// Module + helpers
// ---------------------------------------------------------------------------

export const fakeDb = {
  collection: (name: string) => new FakeCollectionRef(name),
  doc: (p: string) => new FakeDocRef(p),
  batch: () => new FakeWriteBatch(),
  runTransaction: async <T>(fn: (t: FakeTransaction) => Promise<T>) => {
    const t = new FakeTransaction();
    const result = await fn(t);
    await t.commit();
    return result;
  },
  getAll: async (...refs: FakeDocRef[]) => Promise.all(refs.map((r) => r.get())),
};

const firestoreFn: any = () => fakeDb;
firestoreFn.Timestamp = FakeTimestamp;
firestoreFn.FieldValue = FakeFieldValue;

export const fakeAdminModule = {
  __esModule: false,
  initializeApp: () => ({}),
  apps: [{}],
  firestore: firestoreFn,
  messaging: () => messaging,
  auth: () => auth,
  storage: () => ({
    bucket: () => ({
      name: "test-bucket",
      file: (name: string) => ({
        save: async (data: Buffer) => { savedFiles.set(name, data); },
        makePublic: async () => undefined,
        getSignedUrl: async () => ["https://signed"],
        delete: async () => undefined,
      }),
    }),
  }),
};

/** Files written through admin.storage().bucket().file(name).save(). */
export const savedFiles = new Map<string, Buffer>();

export function resetFakeAdmin() {
  store.clear();
  savedFiles.clear();
  sentMessages.length = 0;
  failingTokens.clear();
  validTokens.clear();
  autoId = 0;
  enforceIndexes = true;
}

/** Seed a document (path like "users/u1"). */
export function seed(p: string, data: Data) {
  writeDoc(p, data, "set");
}

export function readDoc(p: string): Data | undefined {
  const d = store.get(p);
  return d ? clone(d) : undefined;
}

export function listDocs(collection: string): { id: string; data: Data }[] {
  const depth = collection.split("/").length + 1;
  return [...store.entries()]
    .filter(([p]) => p.startsWith(collection + "/") && p.split("/").length === depth)
    .map(([p, d]) => ({ id: p.split("/").pop()!, data: clone(d) }));
}

export const ts = (d: Date | string | number) =>
  FakeTimestamp.fromDate(d instanceof Date ? d : new Date(d));

export const fakeFirestoreSubmodule = {
  Timestamp: FakeTimestamp,
  FieldValue: FakeFieldValue,
  getFirestore: () => fakeDb,
};

/** Signed access token accepted by the real authMiddleware under jest. */
export function tokenFor(uid: string): string {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const jwt = require("jsonwebtoken");
  return jwt.sign({ uid, type: "access" }, "shoudeng-dev-jwt-secret-do-not-use-in-prod", { expiresIn: "1h" });
}
