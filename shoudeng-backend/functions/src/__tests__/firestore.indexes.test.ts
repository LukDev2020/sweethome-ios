/**
 * Every Firestore query chain written literally in src/ must be servable by the
 * composite indexes declared in firestore.indexes.json. Production returns
 * FAILED_PRECONDITION for a query whose composite index is missing — which is how
 * the guardian dashboard, home-timer escalation, check-in-overdue and TTL cleanup
 * were silently failing.
 */
import * as fs from "fs";
import * as path from "path";
import { checkIndex } from "./helpers/fakeAdmin";

interface Chain { file: string; line: number; collection: string; filters: { field: string; op: string; value: unknown }[]; orders: { field: string; dir: "asc" | "desc" }[] }

function walk(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory()
      ? (e.name === "__tests__" ? [] : walk(path.join(dir, e.name)))
      : e.name.endsWith(".ts") ? [path.join(dir, e.name)] : []);
}

/** Text of the expression that follows `.collection("x")`, up to where it stops chaining. */
function chainText(rest: string): string {
  let depth = 0;
  for (let i = 0; i < rest.length; i++) {
    const c = rest[i];
    if (c === "(") depth++;
    else if (c === ")") { depth--; if (depth < 0) return rest.slice(0, i); }
    else if (depth === 0 && (c === ";" || c === ",")) return rest.slice(0, i);
    if (depth === 0 && /^\.(get|count|doc|add|onSnapshot)\(/.test(rest.slice(i))) return rest.slice(0, i);
  }
  return rest;
}

export function scanQueries(root: string): Chain[] {
  const out: Chain[] = [];
  for (const file of walk(root)) {
    const src = fs.readFileSync(file, "utf8");
    const re = /\.collection\(\s*"([\w_]+)"\s*\)/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(src))) {
      const chain = chainText(src.slice(m.index + m[0].length));
      const filters = [...chain.matchAll(/\.where\(\s*"([\w.]+)"\s*,\s*"([^"]+)"/g)]
        .map((x) => ({ field: x[1], op: x[2], value: null }));
      const orders = [...chain.matchAll(/\.orderBy\(\s*"([\w.]+)"(?:\s*,\s*"(asc|desc)")?/g)]
        .map((x) => ({ field: x[1], dir: (x[2] || "asc") as "asc" | "desc" }));
      out.push({ file: path.relative(root, file), line: src.slice(0, m.index).split("\n").length, collection: m[1], filters, orders });
    }
  }
  return out;
}

describe("firestore.indexes.json covers every query", () => {
  const chains = scanQueries(path.resolve(__dirname, ".."));

  it("finds the queries (scanner sanity)", () => {
    expect(chains.length).toBeGreaterThan(50);
    expect(chains.some((c) => c.collection === "home_timers" && c.filters.length === 2)).toBe(true);
  });

  for (const c of chains.filter((c) => c.filters.length + c.orders.length > 1)) {
    const desc = [...c.filters.map((f) => `${f.field} ${f.op}`), ...c.orders.map((o) => `orderBy ${o.field} ${o.dir}`)].join(", ");
    it(`${c.file}:${c.line} ${c.collection} [${desc}]`, () => {
      expect(() => checkIndex(c.collection, c.filters, c.orders)).not.toThrow();
    });
  }

  it("timeline pagination (dynamic where before) is indexed", () => {
    expect(() => checkIndex("timeline_entries",
      [{ field: "userId", op: "==", value: "u" }, { field: "timestamp", op: "<", value: 1 }],
      [{ field: "timestamp", dir: "desc" }])).not.toThrow();
  });
});
