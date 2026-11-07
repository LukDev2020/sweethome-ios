#!/usr/bin/env node
/**
 * Rider onboarding funnel (docs/rider-onboarding-plan.md §6): counts only.
 *   npm run build && node scripts/rider-funnel.js [days=30]
 * Uses Application Default Credentials (gcloud auth application-default login).
 */
const admin = require("firebase-admin");
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "sweethome-b4e82" });
const { riderFunnel } = require("../lib/services/riderProfile");

const days = Number(process.argv[2] || 30);
const since = new Date(Date.now() - days * 86400_000);
riderFunnel(since).then((c) => {
  const pct = (n) => (c.started ? `${Math.round((100 * n) / c.started)}%` : "—");
  console.log(`Riders who started setup in the last ${days} days: ${c.started}`);
  for (const [k, label] of [["crew", "joined or started a crew"], ["watcher", "have someone at home watching"],
    ["lockCard", "lock-screen card on"], ["setupDone", "finished setup"], ["firstShift", "started a shift"],
    ["firstShiftWithin7dFullyWatched", "first shift within 7 days with crew + home watcher (target ≥ 50%)"]]) {
    console.log(`  ${pct(c[k]).padStart(4)}  ${String(c[k]).padStart(5)}  ${label}`);
  }
  process.exit(0);
}).catch((e) => { console.error(e); process.exit(1); });
