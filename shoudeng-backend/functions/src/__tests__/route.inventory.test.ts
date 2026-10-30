/**
 * Every API path the iOS app calls must exist on the backend (W0-4: the app was
 * calling /v1/location/pause, /v1/emergency-contacts and
 * /v1/guardian/resend-invite, which 404'd).
 *
 * Paths are scraped from Swift string literals; each is requested against the full
 * Express app with a valid token. Express' default 404 ("Cannot GET /x") means no
 * route matched.
 */
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({ table: () => ({ insert: jest.fn(async () => undefined) }) }),
  })),
}));

import * as fs from "fs";
import * as path from "path";
import request from "supertest";
import { resetFakeAdmin, tokenFor, setEnforceIndexes } from "./helpers/fakeAdmin";

const IOS_ROOTS = ["ShouDeng", "ShouDengWidgets", "Shared"].map((d) => path.resolve(__dirname, "../../../..", d));

function swiftFiles(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? swiftFiles(path.join(dir, e.name)) : e.name.endsWith(".swift") ? [path.join(dir, e.name)] : []);
}

/** Replace Swift string interpolations `\(...)` (balanced parens) with a placeholder. */
function stripInterpolation(lit: string): string {
  let out = "";
  for (let i = 0; i < lit.length; i++) {
    if (lit[i] === "\\" && lit[i + 1] === "(") {
      let depth = 0;
      let j = i + 1;
      for (; j < lit.length; j++) {
        if (lit[j] === "(") depth++;
        else if (lit[j] === ")" && --depth === 0) break;
      }
      out += "x";
      i = j;
    } else out += lit[i];
  }
  return out;
}

interface Call { file: string; line: number; method: string | null; path: string }

function scrape(): Call[] {
  const calls: Call[] = [];
  for (const file of IOS_ROOTS.flatMap(swiftFiles)) {
    const src = fs.readFileSync(file, "utf8");
    const re = /"(\/v1\/(?:[^"\\]|\\\((?:[^()]|\([^()]*\))*\))*)"/g;
    let m: RegExpExecArray | null;
    while ((m = re.exec(src))) {
      const before = src.slice(Math.max(0, m.index - 160), m.index);
      const mm = [...before.matchAll(/\.(get|post|put|delete|postQueued|patch)\s*(?:<[^>]*>)?\(\s*$/g)].pop()
        ?? [...before.matchAll(/\.(get|post|put|delete|postQueued|patch)\s*\(\s*\n?\s*$/g)].pop();
      const method = mm ? (mm[1] === "postQueued" ? "post" : mm[1]) : null;
      const p = stripInterpolation(m[1]).split("?")[0].replace(/\/x(?=\/|$)/g, "/x");
      calls.push({ file: path.relative(path.resolve(__dirname, "../../../.."), file), line: src.slice(0, m.index).split("\n").length, method, path: p });
    }
  }
  return calls;
}

/**
 * Calls in code no screen can reach. Anything added here needs a reason; when the
 * feature ships, implement the route and delete the entry.
 */
const KNOWN_UNREACHABLE: Record<string, string> = {
  "get /v1/device/crowd-tags": "CrowdSourcedBLEService is never instantiated",
  "post /v1/payment/create-intent": "PaymentMethodManager is not used by any view (StoreKit is the purchase path)",
  "post /v1/payment/confirm": "PaymentMethodManager is not used by any view",
  "post /v1/payment/verify-callback": "PaymentMethodManager is not used by any view",
};

describe("every iOS API call has a backend route", () => {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const { app } = require("../app");
  const calls = scrape();

  beforeAll(() => setEnforceIndexes(false));
  beforeEach(() => { resetFakeAdmin(); setEnforceIndexes(false); });

  it("scrapes the app's calls (sanity)", () => {
    expect(calls.length).toBeGreaterThan(60);
    expect(calls.some((c) => c.path === "/v1/sos/trigger")).toBe(true);
  });

  const unique = new Map<string, Call>();
  for (const c of calls) unique.set(`${c.method ?? "*"} ${c.path}`, c);

  for (const [key, c] of unique) {
    if (KNOWN_UNREACHABLE[key]) continue;
    it(`${key}  (${c.file}:${c.line})`, async () => {
      const methods = c.method ? [c.method] : ["get", "post", "put", "delete"];
      const results: string[] = [];
      for (const m of methods) {
        const res = await (request(app) as any)[m](c.path)
          .set("Authorization", `Bearer ${tokenFor("inventory-user")}`)
          .send({});
        const missing = res.status === 404 && /Cannot (GET|POST|PUT|DELETE|PATCH)/.test(res.text);
        results.push(missing ? `${m.toUpperCase()}:missing` : `${m.toUpperCase()}:${res.status}`);
        if (!missing) return;
      }
      throw new Error(`No backend route for ${key}: ${results.join(", ")}`);
    });
  }
});
