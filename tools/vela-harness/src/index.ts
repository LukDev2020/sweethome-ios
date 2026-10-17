#!/usr/bin/env node
/**
 * vela-harness MCP Server
 *
 * Test harness for Vela QA. Provides 8 tools to drive Firebase emulator state
 * and verify backend behavior without touching production.
 *
 * Tools:
 *   create_test_family  — Seed a family in the emulator
 *   trigger_sos         — Trigger SOS for a protected person
 *   set_location        — Set a user's location in Firestore/BigQuery
 *   replay_sensor       — Replay accelerometer CSV for fall detection
 *   set_network         — Simulate network conditions (latency, packet loss)
 *   advance_clock       — Advance emulator clock (for scheduled function testing)
 *   read_audit_log      — Read consent_audit from BigQuery emulator
 *   read_outbox         — Read FCM/SMS/Voice outbox (emulator intercepts)
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import * as admin from "firebase-admin";
import * as jwt from "jsonwebtoken";

// --- Firebase Init ---

const FIRESTORE_HOST = process.env.FIRESTORE_EMULATOR_HOST || "localhost:8080";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || "localhost:9099";
const FUNCTIONS_HOST = process.env.FUNCTIONS_EMULATOR_HOST || "localhost:5001";
const JWT_SECRET = "shoudeng-dev-jwt-secret-do-not-use-in-prod";

process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_HOST;
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;

let app: admin.app.App;
try {
  app = admin.initializeApp({ projectId: "sweethome-d1edd" });
} catch {
  app = admin.app();
}
const db = app.firestore();
const auth = app.auth();

function ts(date?: Date): admin.firestore.Timestamp {
  return admin.firestore.Timestamp.fromDate(date ?? new Date());
}

function makeToken(uid: string): string {
  return jwt.sign({ uid }, JWT_SECRET, { expiresIn: "1h" });
}

async function callFunction(
  path: string,
  method: string,
  body: Record<string, unknown>,
  uid?: string
): Promise<{ status: number; data: unknown }> {
  const url = `http://${FUNCTIONS_HOST}/sweethome-d1edd/us-central1/api${path}`;
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
  };
  if (uid) {
    headers["Authorization"] = `Bearer ${makeToken(uid)}`;
  }

  const resp = await fetch(url, {
    method,
    headers,
    body: method !== "GET" ? JSON.stringify(body) : undefined,
  });

  let data: unknown;
  const text = await resp.text();
  try {
    data = JSON.parse(text);
  } catch {
    data = text;
  }
  return { status: resp.status, data };
}

// --- Tool Implementations ---

async function createTestFamily(args: {
  familyName: string;
  plan: string;
  guardians: Array<{
    id: string;
    name: string;
    phone: string;
    country: string;
    timezone: string;
    city: string;
  }>;
  protectedPerson: {
    id: string;
    name: string;
    phone: string;
    country: string;
    timezone: string;
    city: string;
  };
}): Promise<string> {
  const results: string[] = [];

  // Create protected person
  const pp = args.protectedPerson;
  await auth.createUser({
    uid: pp.id,
    phoneNumber: pp.phone,
    displayName: pp.name,
  });
  await db
    .collection("users")
    .doc(pp.id)
    .set({
      displayName: pp.name,
      phone: pp.phone,
      role: "protected",
      avatarInitial: pp.name.charAt(0),
      countryCode: pp.country,
      timeZone: pp.timezone,
      cityName: pp.city,
      notificationPrefs: {
        sosAlerts: true,
        checkinReminder: true,
        checkinOverdue: true,
        familyFeed: true,
      },
      createdAt: ts(),
      updatedAt: ts(),
    });
  await db.collection("subscriptions").doc(pp.id).set({
    plan: args.plan,
    status: "active",
    expiresAt: null,
  });
  await db.collection("device_tokens").add({
    userId: pp.id,
    token: `fake-token-${pp.id}`,
    platform: "ios",
    environment: "sandbox",
    updatedAt: ts(),
  });
  results.push(`Created protected person: ${pp.name} (${pp.id})`);

  // Create guardians
  for (const g of args.guardians) {
    await auth.createUser({
      uid: g.id,
      phoneNumber: g.phone,
      displayName: g.name,
    });
    await db
      .collection("users")
      .doc(g.id)
      .set({
        displayName: g.name,
        phone: g.phone,
        role: "guardian",
        avatarInitial: g.name.charAt(0),
        countryCode: g.country,
        timeZone: g.timezone,
        cityName: g.city,
        notificationPrefs: {
          sosAlerts: true,
          checkinReminder: true,
          checkinOverdue: true,
          familyFeed: true,
        },
        createdAt: ts(),
        updatedAt: ts(),
      });

    const linkId = `${g.id}_${pp.id}`;
    await db.collection("guardian_links").doc(linkId).set({
      guardianId: g.id,
      protectedPersonId: pp.id,
      status: "active",
      createdAt: ts(),
      acceptedAt: ts(),
      revokedAt: null,
      protectionLayers: 1,
      permissions: {
        canSeeLocation: true,
        canSeeBattery: true,
        canSeeHealth: false,
        canSeePhoneActivity: false,
        canHearEmergencyAudio: false,
      },
    });
    await db.collection("device_tokens").add({
      userId: g.id,
      token: `fake-token-${g.id}`,
      platform: "ios",
      environment: "sandbox",
      updatedAt: ts(),
    });
    results.push(`Created guardian: ${g.name} (${g.id}) linked to ${pp.id}`);
  }

  return results.join("\n");
}

async function triggerSos(args: {
  protectedPersonId: string;
  triggerMethod?: string;
  lat?: number;
  lng?: number;
  batteryLevel?: number;
}): Promise<string> {
  const result = await callFunction(
    "/v1/sos/trigger",
    "POST",
    {
      protectedPersonId: args.protectedPersonId,
      triggerMethod: args.triggerMethod || "button",
      lat: args.lat,
      lng: args.lng,
      batteryLevel: args.batteryLevel,
    },
    args.protectedPersonId
  );

  return JSON.stringify(result, null, 2);
}

async function setLocation(args: {
  userId: string;
  lat: number;
  lng: number;
  accuracy?: number;
  speed?: number;
  altitude?: number;
}): Promise<string> {
  const result = await callFunction(
    "/v1/location/report",
    "POST",
    {
      userId: args.userId,
      lat: args.lat,
      lng: args.lng,
      accuracy: args.accuracy ?? 10,
      altitude: args.altitude ?? 0,
      speed: args.speed ?? 0,
      timestamp: new Date().toISOString(),
      isInSafeZone: false,
      safeZoneName: null,
    },
    args.userId
  );

  return JSON.stringify(result, null, 2);
}

async function replaySensor(args: {
  csvPath: string;
  protectedPersonId: string;
  speedMultiplier?: number;
}): Promise<string> {
  // Read CSV file and parse accelerometer data
  const fs = await import("fs");
  const path = await import("path");

  const csvPath = path.resolve(args.csvPath);
  if (!fs.existsSync(csvPath)) {
    return `Error: CSV file not found at ${csvPath}`;
  }

  const content = fs.readFileSync(csvPath, "utf-8");
  const lines = content.trim().split("\n");
  const header = lines[0].split(",");

  // Expect columns: timestamp, ax, ay, az (or similar)
  const tsIdx = header.findIndex((h) =>
    h.trim().toLowerCase().includes("time")
  );
  const axIdx = header.findIndex(
    (h) => h.trim().toLowerCase() === "ax" || h.trim().toLowerCase() === "x"
  );
  const ayIdx = header.findIndex(
    (h) => h.trim().toLowerCase() === "ay" || h.trim().toLowerCase() === "y"
  );
  const azIdx = header.findIndex(
    (h) => h.trim().toLowerCase() === "az" || h.trim().toLowerCase() === "z"
  );

  if (axIdx === -1 || ayIdx === -1 || azIdx === -1) {
    return `Error: CSV must have ax/ay/az (or x/y/z) columns. Found: ${header.join(", ")}`;
  }

  const samples = lines.slice(1).map((line) => {
    const cols = line.split(",");
    return {
      timestamp: tsIdx >= 0 ? parseFloat(cols[tsIdx]) : 0,
      ax: parseFloat(cols[axIdx]),
      ay: parseFloat(cols[ayIdx]),
      az: parseFloat(cols[azIdx]),
    };
  });

  return JSON.stringify({
    status: "replayed",
    samples: samples.length,
    file: csvPath,
    note: "Sensor replay is processed client-side by FallDetector. This tool verifies CSV parsing. Use xcode-runner test_one to run FallDetector unit tests with this data.",
  });
}

async function setNetwork(args: {
  profile: "normal" | "slow3g" | "offline" | "highLatency" | "packetLoss";
  durationSec?: number;
}): Promise<string> {
  // Network condition simulation is done via iOS Network Link Conditioner
  // or by manipulating emulator responses. For the harness, we track state.
  const profileSettings: Record<string, { latencyMs: number; lossRate: number; bandwidth: string }> = {
    normal: { latencyMs: 20, lossRate: 0, bandwidth: "unlimited" },
    slow3g: { latencyMs: 400, lossRate: 0.02, bandwidth: "400kbps" },
    offline: { latencyMs: -1, lossRate: 1.0, bandwidth: "0" },
    highLatency: { latencyMs: 2000, lossRate: 0.01, bandwidth: "1mbps" },
    packetLoss: { latencyMs: 100, lossRate: 0.3, bandwidth: "5mbps" },
  };

  const settings = profileSettings[args.profile];
  if (!settings) {
    return `Unknown profile: ${args.profile}. Use: normal, slow3g, offline, highLatency, packetLoss`;
  }

  // Store in Firestore so tests can read the current condition
  await db.collection("_qa_state").doc("network").set({
    profile: args.profile,
    ...settings,
    setAt: ts(),
    expiresAt: args.durationSec
      ? ts(new Date(Date.now() + args.durationSec * 1000))
      : null,
  });

  return JSON.stringify({
    profile: args.profile,
    ...settings,
    durationSec: args.durationSec ?? "indefinite",
    note: "Network profile stored in _qa_state/network. Tests should check this before making requests. For real device testing, use Network Link Conditioner.",
  });
}

async function advanceClock(args: {
  byMinutes: number;
}): Promise<string> {
  // The emulator doesn't support time travel natively.
  // We store a clock offset that scheduled function tests can read.
  const offsetDoc = await db.collection("_qa_state").doc("clock").get();
  const existingOffset = offsetDoc.exists
    ? (offsetDoc.data()?.offsetMinutes as number) || 0
    : 0;

  const newOffset = existingOffset + args.byMinutes;

  await db.collection("_qa_state").doc("clock").set({
    offsetMinutes: newOffset,
    virtualNow: new Date(Date.now() + newOffset * 60 * 1000).toISOString(),
    updatedAt: ts(),
  });

  return JSON.stringify({
    previousOffset: existingOffset,
    addedMinutes: args.byMinutes,
    totalOffsetMinutes: newOffset,
    virtualNow: new Date(Date.now() + newOffset * 60 * 1000).toISOString(),
    note: "Clock offset stored in _qa_state/clock. Scheduled function tests should use virtualNow instead of Date.now().",
  });
}

async function readAuditLog(args: {
  userId?: string;
  consentType?: string;
  limit?: number;
}): Promise<string> {
  // In emulator mode, consent_audit is written to Firestore instead of BigQuery
  // (BigQuery emulator doesn't exist). Check both locations.
  let query: admin.firestore.Query = db.collection("consent_audit");

  if (args.userId) {
    query = query.where("userId", "==", args.userId);
  }
  if (args.consentType) {
    query = query.where("consentType", "==", args.consentType);
  }

  const limit = args.limit ?? 50;
  const snap = await query.orderBy("timestamp", "desc").limit(limit).get();

  if (snap.empty) {
    // Try BigQuery-style table in Firestore (some backends mirror here)
    const bqSnap = await db
      .collection("_bq_consent_audit")
      .orderBy("timestamp", "desc")
      .limit(limit)
      .get();

    if (bqSnap.empty) {
      return JSON.stringify({ entries: [], note: "No consent_audit entries found in Firestore emulator." });
    }

    return JSON.stringify({
      source: "_bq_consent_audit",
      entries: bqSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
    });
  }

  return JSON.stringify({
    source: "consent_audit",
    entries: snap.docs.map((d) => ({ id: d.id, ...d.data() })),
  });
}

async function readOutbox(args: {
  channel?: "fcm" | "sms" | "voice" | "all";
  userId?: string;
  limit?: number;
}): Promise<string> {
  const channel = args.channel ?? "all";
  const limit = args.limit ?? 50;
  const results: Record<string, unknown[]> = {};

  const channels = channel === "all" ? ["fcm", "sms", "voice"] : [channel];

  for (const ch of channels) {
    // The emulator intercepts outbound messages and stores them in
    // _qa_outbox/{channel} collection
    let query: admin.firestore.Query = db.collection(`_qa_outbox_${ch}`);
    if (args.userId) {
      query = query.where("recipientId", "==", args.userId);
    }
    const snap = await query.orderBy("sentAt", "desc").limit(limit).get();
    results[ch] = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  }

  return JSON.stringify({ outbox: results, note: "Outbox entries are written by test stubs for FCM/SMS/Twilio services." });
}

// --- MCP Server Setup ---

const server = new Server(
  { name: "vela-harness", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "create_test_family",
      description:
        "Create a test family in Firebase emulator with guardian links and device tokens",
      inputSchema: {
        type: "object" as const,
        properties: {
          familyName: { type: "string", description: "Family identifier" },
          plan: {
            type: "string",
            enum: ["free", "family", "enhanced"],
            description: "Subscription plan",
          },
          guardians: {
            type: "array",
            items: {
              type: "object",
              properties: {
                id: { type: "string" },
                name: { type: "string" },
                phone: { type: "string" },
                country: { type: "string" },
                timezone: { type: "string" },
                city: { type: "string" },
              },
              required: ["id", "name", "phone", "country", "timezone", "city"],
            },
          },
          protectedPerson: {
            type: "object",
            properties: {
              id: { type: "string" },
              name: { type: "string" },
              phone: { type: "string" },
              country: { type: "string" },
              timezone: { type: "string" },
              city: { type: "string" },
            },
            required: ["id", "name", "phone", "country", "timezone", "city"],
          },
        },
        required: ["familyName", "plan", "guardians", "protectedPerson"],
      },
    },
    {
      name: "trigger_sos",
      description: "Trigger an SOS event for a protected person via the API",
      inputSchema: {
        type: "object" as const,
        properties: {
          protectedPersonId: { type: "string" },
          triggerMethod: {
            type: "string",
            enum: ["button", "fall_detection", "voice", "watch"],
          },
          lat: { type: "number" },
          lng: { type: "number" },
          batteryLevel: { type: "number" },
        },
        required: ["protectedPersonId"],
      },
    },
    {
      name: "set_location",
      description: "Report a location update for a user via the telemetry API",
      inputSchema: {
        type: "object" as const,
        properties: {
          userId: { type: "string" },
          lat: { type: "number" },
          lng: { type: "number" },
          accuracy: { type: "number" },
          speed: { type: "number" },
          altitude: { type: "number" },
        },
        required: ["userId", "lat", "lng"],
      },
    },
    {
      name: "replay_sensor",
      description:
        "Parse and validate accelerometer CSV for fall detection testing",
      inputSchema: {
        type: "object" as const,
        properties: {
          csvPath: { type: "string", description: "Path to accelerometer CSV" },
          protectedPersonId: { type: "string" },
          speedMultiplier: { type: "number", description: "Playback speed (default 1.0)" },
        },
        required: ["csvPath", "protectedPersonId"],
      },
    },
    {
      name: "set_network",
      description:
        "Set simulated network conditions for testing degraded connectivity",
      inputSchema: {
        type: "object" as const,
        properties: {
          profile: {
            type: "string",
            enum: ["normal", "slow3g", "offline", "highLatency", "packetLoss"],
          },
          durationSec: { type: "number" },
        },
        required: ["profile"],
      },
    },
    {
      name: "advance_clock",
      description:
        "Advance the virtual clock by N minutes for scheduled function testing",
      inputSchema: {
        type: "object" as const,
        properties: {
          byMinutes: { type: "number", description: "Minutes to advance" },
        },
        required: ["byMinutes"],
      },
    },
    {
      name: "read_audit_log",
      description: "Read consent audit log entries from the emulator",
      inputSchema: {
        type: "object" as const,
        properties: {
          userId: { type: "string" },
          consentType: { type: "string" },
          limit: { type: "number" },
        },
      },
    },
    {
      name: "read_outbox",
      description:
        "Read intercepted FCM/SMS/Voice messages from the emulator outbox",
      inputSchema: {
        type: "object" as const,
        properties: {
          channel: {
            type: "string",
            enum: ["fcm", "sms", "voice", "all"],
          },
          userId: { type: "string" },
          limit: { type: "number" },
        },
      },
    },
  ],
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    let result: string;
    switch (name) {
      case "create_test_family":
        result = await createTestFamily(args as Parameters<typeof createTestFamily>[0]);
        break;
      case "trigger_sos":
        result = await triggerSos(args as Parameters<typeof triggerSos>[0]);
        break;
      case "set_location":
        result = await setLocation(args as Parameters<typeof setLocation>[0]);
        break;
      case "replay_sensor":
        result = await replaySensor(args as Parameters<typeof replaySensor>[0]);
        break;
      case "set_network":
        result = await setNetwork(args as Parameters<typeof setNetwork>[0]);
        break;
      case "advance_clock":
        result = await advanceClock(args as Parameters<typeof advanceClock>[0]);
        break;
      case "read_audit_log":
        result = await readAuditLog(args as Parameters<typeof readAuditLog>[0]);
        break;
      case "read_outbox":
        result = await readOutbox(args as Parameters<typeof readOutbox>[0]);
        break;
      default:
        result = `Unknown tool: ${name}`;
    }

    return { content: [{ type: "text", text: result }] };
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    return {
      content: [{ type: "text", text: `Error: ${message}` }],
      isError: true,
    };
  }
});

// --- Start ---

async function main(): Promise<void> {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("[vela-harness] MCP server running on stdio");
}

main().catch((err) => {
  console.error("[vela-harness] Fatal:", err);
  process.exit(1);
});
