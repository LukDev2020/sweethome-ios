# Incident Report for Police — and a fall chain that cannot lose an SOS

Status: design + phase 1 implementation (2026-11-07)
Owner: Lantern Care / 守灯 iOS + backend

Two pieces, built together because the second feeds the first:

1. **Incident Report for Police (事件报告 / 报警材料)**: one tap turns the last hours or days into
   a package police can work with. It contains a PDF, map images, a GPX track, CSV/JSON data, and a
   manifest that police can verify.
2. **Fall chain hardening**: a detected fall must end either in "I'm OK" or in an SOS, never in silence.
   Every detection is recorded, so it can appear in the report.

---

## 1. Who uses it, and when

| Situation | Who makes the report | Window | Purpose |
|---|---|---|---|
| Mum hasn't come home and isn't answering | Guardian (Sarah) | last 24 h / 72 h | Missing person |
| A rider was attacked during a shift | The rider, or a crew mate / family guardian | the shift | Assault / threat |
| Dad fell, the ambulance came, and insurance or police ask what happened | Guardian | around the fall | Accident / fall |
| The person wants their own record ("he followed me") | The person themselves | up to 7 days | Harassment / other |

Police **never get an account or standing access**. A report is something the family or the person
hands over: as files, or later as a time-limited link (phase 2). Formal requests from law enforcement
to the company (Vela Care) go through a manual legal process. That is out of the app's scope and
covered by a published law-enforcement request policy (see §8).

## 2. Principles

1. **The data owner decides.** Two people may create a report: the person, or an active guardian
   who may see the person's location (`canSeeLocation`). Everyone else gets 403. A rider's crew mates
   cannot pull reports; only the rider and the rider's family can.
2. **Transparent to the person.** When a guardian creates a report about someone, that person gets a
   push and an entry in their timeline ("Sarah created a police report covering 6 Nov 18:00 – 7 Nov 18:00").
   Every creation, seal and verification is audited.
3. **Evidence-grade, honestly labelled.**
   - The server assembles the data and hashes it before the app ever sees it. The app saves those exact
     bytes as `data.json`, so the hash in the PDF matches the server's registry.
   - Renderings (PDF, map images, GPX, CSV) are registered ("sealed") afterwards. Police can check that a
     file is unchanged since the app produced it.
   - Gaps (no data for more than 30 min) are shown, not hidden.
   - Every position carries its accuracy radius.
   - Fall detections are labelled "automatic detection — not a medical finding", together with what the
     person did ("tapped I'm OK after 12 s" / "no response → SOS sent").
4. **Minimal.**
   - Maximum window 7 days, maximum 20,000 points.
   - Medical card, chat messages and voice notes are never included.
   - Sections the reporter switches off are not fetched at all, not merely hidden.
5. **Works when parts are down.** Locations are merged from every place they exist, so a report still has
   a trail if BigQuery is unavailable:
   - the BigQuery `location_reports` table;
   - SOS trails;
   - recorded trips;
   - check-ins;
   - fall events.

   The report states which sources answered.

## 3. What is in the report

```
LanternCare_Report_<name>_<yyyyMMdd-HHmm>/
  report.pdf          human-readable, in the reporter's language
  map-overview.png    whole trail; start, last known position, SOS and fall markers
  map-last-known.png  ~600 m around the last known position
  map-event-N.png     ~400 m around each SOS / fall (up to 4)
  track.gpx           GPX 1.1 track + waypoints (SOS, falls, check-ins), for police GIS tools
  locations.csv       time (UTC + local), lat, lon, accuracy m, speed, activity, source
  data.json           the server's canonical data, byte for byte
  manifest.json       SHA-256 of every file, report id, verify URL
```

PDF sections:

1. **Cover**
   - Report ID and verify code.
   - Person and reporter.
   - Window, including the time zone.
   - Purpose; optional police case number.
2. **Summary**
   - Last known position (time, address, accuracy) and battery.
   - Last check-in and last heartbeat.
   - Counts: SOS, falls, gaps.
3. **Maps**: overview, last known position, each event.
4. **Key events**: SOS, falls, check-ins, home-timer expiries, leaving or entering safe zones, battery
   low, phone inactive, tracking paused (pauses are shown honestly).
5. **Activity**: segments such as "walking 18:02–18:20, 1.3 km" or "driving 18:25–18:50, 14 km", built from
   activity-tagged locations and speed.
6. **Falls**: for each detection:
   - time and place;
   - impact (g), free-fall time, change in body orientation;
   - stillness afterwards;
   - response and outcome.
7. **SOS events**:
   - trigger method;
   - who was alerted and who acknowledged;
   - resolution;
   - trail.
8. **Location table**, with data gaps called out.
9. **Integrity and limits**:
   - the hashes and how to verify them;
   - what the app cannot know (indoor accuracy, a phone left behind, clock drift);
   - the disclaimer.

## 4. Architecture

```
 iOS (reporter)                                 Cloud Functions                      Stores
 ─────────────                                  ───────────────                      ──────
 IncidentReportView ── POST /v1/incident-reports ─► authorize (self | guardian+loc)
   purpose, window,                                 fetch in parallel ─────────────► BigQuery location_reports,
   case no., sections                                                                 heartbeat_signals
                                                                                    ► Firestore sos_events (+trail),
                                                                                      timeline_entries, trips/points,
                                                                                      safety_events (falls)
                                                    merge + dedupe + derive activity
                                                    segments and gaps
                                                    canonical JSON → SHA-256
                                                    incident_reports/{id} ◄──────────  registry (server-only)
                                                    push + timeline to the person
                     ◄── { report, canonical, dataSha256, verifyCode }
 IncidentReportBuilder
   MKMapSnapshotter → PNGs (trail drawn on snapshot)
   UIGraphicsPDFRenderer → PDF
   GPX / CSV writers
   SHA-256 every file → manifest.json
   ── POST /v1/incident-reports/:id/seal {files:{name:sha256}} ─► once, creator only
 Share sheet (files / AirDrop / mail)

 Police ── GET /v1/incident-reports/verify?code=…&sha256=… ─► public, rate-limited:
           "genuine: report R-…, created 7 Nov 18:04 for 6–7 Nov; file report.pdf unchanged"
```

Why the map is rendered on the phone:

- `MKMapSnapshotter` needs no API key, costs nothing, and matches the maps the family already sees.
- Rendering on the server would need a paid static-maps key.
- The map is a rendering. The evidence is the hashed data.

### Data model

`safety_events/{userId}_{clientEventId}` (server-only, written via the API):

```
userId, type: "fall", clientEventId, detectedAt, escalateAt,
latitude?, longitude?, accuracy?, batteryLevel?,
metrics: { peakImpactG, freeFallMs, orientationChangeDeg, stillnessVariance, detector: "threshold-v2" },
outcome: "pending" | "dismissed" | "escalated" (no answer) | "help_requested" ("I need help") | "escalated_by_server",
respondedAfterSec?, sosEventId?, clientSOSId, updatedAt
```

`incident_reports/{reportId}` (server-only):

```
personId, createdBy, createdByRole ("self" | "guardian"), purpose, caseNumber?,
windowStart, windowEnd, sections[], dataSha256, verifyCode (8 chars, unambiguous alphabet),
sources: { bigquery: "ok" | "unavailable", ... }, counts: {...},
files: { "report.pdf": sha256, ... } (set once by /seal), sealedAt, createdAt
```

`incident_report_audit` (server-only, append-only): create / seal / verify events with uid or IP hash.

### API

| Method | Path | Who | Notes |
|---|---|---|---|
| POST | `/v1/safety-events/fall` | the person | Upserts by `clientEventId`; first call `pending` with `escalateAt`, then `dismissed` / `escalated` / `help_requested`. |
| POST | `/v1/incident-reports` | person or guardian with location | Body `{personId, windowStart, windowEnd, purpose, caseNumber?, sections?}`. Window ≤ 7 days and not in the future. Rate limit 10/h. |
| POST | `/v1/incident-reports/:id/seal` | creator | `{files: {name: sha256}}` with ≤ 16 files; one-shot (409 after). |
| GET | `/v1/incident-reports?personId=` | the person (reports about them) or the creator | Transparency list. |
| GET | `/v1/incident-reports/verify?code=&sha256=` | public | Rate-limited per IP. Never returns the name or the data, only whether the file and code match. |

## 5. Fall chain — what was wrong, and the design that fixes it

Measured on the current code with synthetic 50 Hz traces (`FallSensorTrace`, `FallScenarioTests`). See §7.

| # | Problem | Effect (measured) |
|---|---|---|
| F1 | The 60 s "Are you OK?" countdown advanced only when new sensor samples arrived, and sensors stop when the app leaves the foreground. | Screen auto-locks during the countdown, or the app is backgrounded: **no SOS, ever**. |
| F2 | After a fall escalated, the detector stayed in `.confirmed` and was never reset. | A second fall went undetected until the app restarted. |
| F3 | "Stillness" was judged on the last 5 s only (the buffer), and its threshold (variance 0.05) let ordinary walking (≈ 0.045) count as lying still. | **False alarms**: falling and then getting up and walking away, or dropping the phone and picking it up, both reached the check. |
| F4 | Scream detection and voice "help" reused the fall screen: "Fall detected"; tapping "I'm OK" counted as a fall false alarm. | Wrong message and wrong statistics. |
| F5 | Detections were never recorded anywhere unless they became an SOS. | No history for the family, the report, or tuning. |
| F6 | There was no way to get help at once from the check screen. | A hurt but conscious person had to wait the full 60 s. |

Checked and fine: a fall down stairs (≈ 0.9 s in the air) is caught, because the detector re-arms while still falling. Jumps, running and sitting down hard never reach the check.

Design:

```
 sensor 50 Hz ─► FallDetector (pure, sample-driven: free fall → impact → orientation → stillness)
                    │ candidate(metrics)            detector pauses until resolved
                    ▼
 AppCoordinator.beginAutoSOSCheck(reason: .fall, metrics)
   • deadline = now + 60 s, by the wall clock (DispatchWorkItem), not by samples
   • background task + a time-sensitive notification at once ("Fall detected — open to cancel")
   • POST /v1/safety-events/fall {pending, escalateAt}  ← server-side fallback is armed
   • overlay with the reason-specific text and "I need help — send SOS now"
        ├─ "I'm OK"   → outcome dismissed, detector re-armed; guardians get a quiet note
        └─ deadline / send now → triggerSOS(.fallDetection, clientSOSId) → outcome escalated, detector re-armed
 Back in the foreground after the deadline without an answer → SOS at once.

 Server: every minute — pending fall with escalateAt + 30 s ≤ now
        → same transaction as /v1/sos/trigger (dedupes on the active SOS and the clientSOSId)
        → outcome escalated_by_server; onSOSCreated escalates to guardians as usual.
```

This closes F1 even if:

- the phone is face-down and locked;
- the app was killed;
- the battery dies right after the detection was posted.

The server sends the SOS 1–2 minutes later. If the phone was offline at the moment of the fall, the
client-side timer is the only arm. The SOS then goes out through the offline queue as soon as the phone
has a network connection.

Known limits, stated in the app and in the report:

- The iPhone detects falls only while the app is in the foreground (iOS gives no continuous background
  motion stream). Continuous detection needs Apple Watch: Apple's `CMFallDetectionManager`, which
  requires the `com.apple.developer.health.fall-detection` entitlement. That is the phase 3 plan.
- A slow slump with no free fall is not detected by the threshold pipeline. The ML classifier (shadow
  mode, no model shipped yet) is meant to cover it.
- A phone dropped and left lying looks exactly like a fall. The 60 s check exists for that.

## 6. Phases

- **Phase 1 (this change)**
  - Fall chain F1–F6.
  - `safety_events`, plus the server fallback.
  - Report generation API with registry, seal and verify.
  - iOS report builder (PDF, maps, GPX, CSV, JSON, manifest).
  - Entry points:
    - the guardian's person card and the SOS alert screen ("Police report");
    - the person's Records.
  - Demo data, so Explore Mode shows it.
  - Tests: scenario traces, coordinator chain, backend routes.
- **Phase 2**
  - Police link: a token valid ≤ 72 h with ≤ 20 views, serving a read-only HTML report plus the files.
  - Ed25519-signed manifests: offline verification with a published public key, managed in Secret Manager.
  - Bilingual PDF (the reporter's language plus English).
- **Phase 3**
  - Apple Watch fall detection (entitlement).
  - Activity history from `CMMotionActivityManager` (7 days on device) for reports the person makes themselves.

## 7. Testing

- `FallScenarioTests`: real fall, fall down stairs, phone left on the floor → check appears. Getting up,
  phone picked up, sitting down hard, jump, 30 s run → nothing. Slow slump → documented miss.
- `FallChainTests`: candidate → countdown → SOS with `.fallDetection`; "I'm OK" → no SOS; the detector
  re-arms after both outcomes; deadline passed while backgrounded → SOS on return.
- Backend:
  - `safetyEvents` (auth, upsert, server fallback creates exactly one SOS, dedupes with the device's
    SOS, never escalates dismissed);
  - `incidentReports` (authorization matrix, window limits, canonical hash, seal once, verify,
    transparency push).
- Simulator end to end: the debug "Simulate fall" action replays `forwardFall` through the real detector,
  so the overlay, the countdown and the SOS reach the guardian side in Explore Mode.

## 8. Open items found while building this

- **Location history store.**
  - All location history goes to the BigQuery dataset `shoudeng`, and its existence could not be confirmed from the developer account.
  - If the dataset is missing, `/location/report` answers "queued for retry", but nothing is actually queued.
  - Reports still get positions from trips, SOS trails, check-ins and falls, and they say which source was unavailable.
  - To do: confirm the dataset and its tables in sweethome-b4e82.
- **Activity in history.** `activityType` is sent with every location report but never written to BigQuery: `insertLocationReport` drops it. Report activity therefore comes from speed, except for trip points. Adding an `activity_type` column needs a schema migration before the insert can include it.
- **Elderly fall profile.** The detector has an elderly profile (`Config.elderly`), which is the only one that catches a slow slump. Nothing selects it yet: everyone gets `.youngAdult`. A natural trigger is the Simple home style, or an age band in the profile.
- **Apple Watch.** Continuous fall detection needs `CMFallDetectionManager` and Apple's fall-detection entitlement (phase 3).

## 9. Legal notes (for counsel review)

- Sharing a report is the user's own act; the app shows who sees what before sharing.
- Guardians reporting about an adult: allowed because the person agreed to guardianship. The person is told
  every time (transparency push), and the report is limited to what the guardian could already see.
- Retention: report registry entries (hashes and metadata only, no location data) are kept 2 years for
  verification. The data itself follows the normal retention.
- Publish a Law Enforcement Request policy: requests to `legal@` with legal process; no direct access.
