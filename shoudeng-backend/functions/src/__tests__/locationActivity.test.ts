/**
 * location_reports.activity_type (services/bigquery.ts):
 *  - the phone's motion tag is written, normalised; anything else is null
 *  - a table that has not been migrated yet still gets the position (without the tag)
 *  - /location/report and /location/batch pass the tag through
 */
const mockInserted: Record<string, unknown>[] = [];
let mockColumnMissing = false;
let mockInsertError: Error | null = null;
jest.mock("@google-cloud/bigquery", () => ({
  BigQuery: jest.fn().mockImplementation(() => ({
    query: jest.fn(async () => [[]]),
    dataset: () => ({
      table: () => ({
        insert: jest.fn(async (rows: Record<string, unknown>[]) => {
          if (mockInsertError) throw mockInsertError;
          if (mockColumnMissing && rows.some((r) => "activity_type" in r)) {
            // What @google-cloud/bigquery throws (PartialFailureError) for an unknown column
            throw Object.assign(new Error("A failure occurred during this request."), {
              name: "PartialFailureError",
              errors: rows.map((row) => ({ row, errors: [{ reason: "invalid", message: "no such field: activity_type." }] })),
            });
          }
          mockInserted.push(...rows);
        }),
      }),
    }),
  })),
}));
jest.mock("firebase-admin", () => require("./helpers/fakeAdmin").fakeAdminModule);
jest.mock("firebase-admin/firestore", () => require("./helpers/fakeAdmin").fakeFirestoreSubmodule);

import * as crypto from "crypto";
import express from "express";
import request from "supertest";
import { insertLocationReport, locationActivityType } from "../services/bigquery";
import { resetFakeAdmin, tokenFor } from "./helpers/fakeAdmin";

const base = { userId: "u1", latitude: 43.65, longitude: -79.38, accuracy: 8, timestamp: "2026-11-07T10:00:00.000Z" };

const rowHash = (row: Record<string, unknown>) => {
  const fields = { ...row };
  delete fields.row_hash;
  const sorted = Object.keys(fields).sort().map((k) => `${k}=${String(fields[k] ?? "")}`).join("|");
  return crypto.createHash("sha256").update(sorted).digest("hex");
};

beforeEach(() => {
  mockInserted.length = 0;
  mockColumnMissing = false;
  mockInsertError = null;
  resetFakeAdmin();
});

it("known tags are kept (CoreMotion's automotive is driving); anything else is null", () => {
  expect(["stationary", "walking", "running", "cycling", "driving", "unknown"].map(locationActivityType))
    .toEqual(["stationary", "walking", "running", "cycling", "driving", "unknown"]);
  expect(locationActivityType("automotive")).toBe("driving");
  expect(locationActivityType(" Walking ")).toBe("walking");
  expect(locationActivityType("teleporting")).toBeNull();
  expect(locationActivityType("<script>")).toBeNull();
  expect(locationActivityType(undefined)).toBeNull();
  expect(locationActivityType(3)).toBeNull();
});

it("writes activity_type, and the row hash covers it", async () => {
  await insertLocationReport({ ...base, activityType: "walking" });
  await insertLocationReport(base);
  expect(mockInserted.map((r) => r.activity_type)).toEqual(["walking", null]);
  for (const r of mockInserted) expect(r.row_hash).toBe(rowHash(r));
});

it("a table without the column yet: the position is still written, without the tag", async () => {
  mockColumnMissing = true;
  const warn = jest.spyOn(console, "warn").mockImplementation(() => undefined);
  await insertLocationReport({ ...base, activityType: "driving" });
  expect(mockInserted).toHaveLength(1);
  expect(mockInserted[0]).not.toHaveProperty("activity_type");
  expect(mockInserted[0]).toMatchObject({ user_id: "u1", latitude: 43.65 });
  expect(mockInserted[0].row_hash).toBe(rowHash(mockInserted[0]));
  expect(warn).toHaveBeenCalledWith(expect.stringContaining("setup.sh"));
  warn.mockRestore();
});

it("other insert errors are not swallowed", async () => {
  mockInsertError = new Error("Not found: Dataset sweethome-b4e82:shoudeng");
  await expect(insertLocationReport({ ...base, activityType: "walking" })).rejects.toThrow("Not found: Dataset");
  expect(mockInserted).toHaveLength(0);
});

describe("routes pass the phone's tag through", () => {
  const app = express();
  app.use(express.json());
  app.use("/v1", require("../routes/telemetry").default);
  const post = (path: string, body: object) =>
    request(app).post(path).set("Authorization", `Bearer ${tokenFor("u1")}`).send(body);

  it("/v1/location/report", async () => {
    const r = await post("/v1/location/report", { ...base, activityType: "cycling" });
    expect(r.status).toBe(200);
    expect(mockInserted.map((x) => x.activity_type)).toEqual(["cycling"]);
  });

  it("/v1/location/batch", async () => {
    const r = await post("/v1/location/batch", {
      reports: [{ ...base, activityType: "running" }, { ...base, activityType: "automotive" }, base],
    });
    expect(r.status).toBe(200);
    expect(mockInserted.map((x) => x.activity_type)).toEqual(["running", "driving", null]);
  });
});
