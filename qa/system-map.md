# System Map — Vela (守灯) Backend & Pipeline

Generated: 2026-10-17 | Branch: `qa/backend-harness`

---

## 1. Cloud Functions — HTTP API (Express, exported as `api`)

All routes mounted on a single Express app exported as `functions.https.onRequest(api)`.
Auth middleware: JWT access token in `Authorization: Bearer <token>` header.
Rate limiting: Firestore-based, per-user or per-IP, fail-open for safety-critical paths.

### 1.1 Auth Routes (`/v1/auth`) — rate limit: 5/min per IP

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/auth/send-code` | No | `{phone}` | `{success}` (stub — Firebase Auth handles SMS) | No |
| POST | `/v1/auth/login` | No | `{idToken}` (Firebase ID token) | `{accessToken, refreshToken, userId, displayName, role}` or 404 userNotFound | auth.middleware.test.ts (partial) |
| POST | `/v1/auth/signup` | No | `{idToken, displayName, role, countryCode?}` | `{accessToken, refreshToken, userId, displayName, role}` 201 | No |
| POST | `/v1/auth/refresh` | No | `{refreshToken}` | `{accessToken, refreshToken, userId}` | No |

JWT: access 1h, refresh 30d. Dev secret: `shoudeng-dev-jwt-secret-do-not-use-in-prod`.

### 1.2 User Routes (`/v1/user`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/user/me` | Yes | — | `{id, displayName, role, avatarInitial, timeZone, countryCode, cityName, createdAt}` | No |
| PUT | `/v1/user/me` | Yes | `{displayName?, timeZone?, cityName?, countryCode?}` | `{success}` | No |
| PUT | `/v1/user/notification-preferences` | Yes | `{sosAlerts?, checkinReminder?, checkinOverdue?, familyFeed?}` | `{success}` | No |
| POST | `/v1/user/delete` | Yes | — | `{success}` (deletes all PII, retains consent_audit + evidence_holds) | No |
| POST | `/v1/user/export` | Yes | — | Full JSON export of all user data | No |
| POST | `/v1/diagnostics/crash` | Yes | crash report body | `{success}` | No |

### 1.3 Invite Routes (`/v1/invite`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/invite/create` | Yes | `{role?}` | `{inviteId, code, expiresAt, status}` 201 | No |
| POST | `/v1/invite/accept` | Yes | `{inviteId? or code?}` | `{success, guardianId, protectedPersonId, linkId}` | No |

Invite code: 6-char hex, expires 24h. Transaction-protected accept with role matching.

### 1.4 Guardian Routes (`/v1/guardian`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/guardian/protected-persons` | Yes | — | `[{personId, displayName, status, lat, lng, batteryLevel, lastCheckIn, protectionLayers, ...}]` | No |

Status computed from: heartbeat (30min → unreachable), checkin (6h → pending, 8h → overdue).

### 1.5 Protected Routes (`/v1/protected`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/protected/guardians` | Yes | — | `[Guardian]` | No |
| PUT | `/v1/protected/guardians/:id/permissions` | Yes | permissions object | `{success}` | No |
| DELETE | `/v1/protected/guardians/:id` | Yes | — | `{success}` | No |

### 1.6 Telemetry Routes (`/v1`) — rate limit: 120/min

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/heartbeat` | Yes | `{userId, timestamp, source, batteryLevel, batteryState, lat, lng, accuracy}` | `{success}` (→ BigQuery) | No |
| POST | `/v1/location/report` | Yes | `{userId, lat, lng, accuracy, altitude, speed, timestamp, isInSafeZone, safeZoneName}` | `{success}` (→ BigQuery) | No |
| POST | `/v1/checkin` | Yes | `{userId, lat?, lng?, note?}` | `{checkInId, timestamp}` (→ Firestore + BigQuery) | No |

### 1.7 SOS Routes (`/v1/sos`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/sos/trigger` | Yes | `{protectedPersonId, triggerMethod?, lat?, lng?, batteryLevel?}` | `{sosEventId, escalationState}` 201 | sos.routes.test.ts |
| POST | `/v1/sos/resolve` | Yes | `{sosEventId, resolution}` | `{success}` | sos.routes.test.ts |
| POST | `/v1/voice-call` | Yes | `{guardianId, sosEventId, protectedPersonName?}` | `{success, callSid}` | No |
| POST | `/v1/voice-callback` | No | Twilio DTMF: `{Digits, CallSid}` | TwiML XML | No |

### 1.8 Device Routes (`/v1/device`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/device/token` | Yes | `{token, platform, environment}` | `{success}` | No |

### 1.9 Safe Zone Routes (`/v1/safe-zone` and `/v1/safe-zones`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/safe-zone/save` | Yes | zone object | `{success, zoneId}` | No |
| GET | `/v1/safe-zone/` or `/v1/safe-zones/` | Yes | — | `[SafeZone]` | No |

### 1.10 Duty Schedule (`/v1/duty-schedule`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| PUT | `/v1/duty-schedule/` | Yes | schedule object | `{success}` | No |

### 1.11 Evidence (`/v1/evidence`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/evidence/generate` | Yes | `{protectedPersonId, ...}` | evidence data | No |
| POST | `/v1/evidence/share` | Yes | `{...}` | share token | No |
| GET | `/v1/evidence/share/:token` | No | — | evidence data (public) | No |

### 1.12 Family Feed (`/v1/family`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/family/posts` | Yes | — | `[FamilyPost]` | No |
| POST | `/v1/family/posts` | Yes | `{text, mediaURLs}` | `{postId}` | No |
| POST | `/v1/family/posts/:postId/comments` | Yes | `{text}` | `{commentId}` | No |
| PUT | `/v1/family/posts/:postId` | Yes | `{text}` | `{success}` | No |
| DELETE | `/v1/family/posts/:postId` | Yes | — | `{success}` | No |
| POST | `/v1/family/upload` | Yes | `{data, mimeType}` | `{url}` | No |

### 1.13 Payment (`/v1/payment`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/payment/plans` | No | — | plan list | No |
| GET | `/v1/payment/subscription` | Yes | — | current subscription | No |
| POST | `/v1/payment/verify` | Yes | receipt data | `{success}` | No |
| POST | `/v1/payment/stripe-webhook` | No | Stripe event | 200 | No |
| POST | `/v1/payment/apple-webhook` | No | App Store notification | 200 | No |

### 1.14 Webhooks (`/v1/webhooks`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/webhooks/twilio/call-status` | No | Twilio callback | 200 | webhooks.routes.test.ts |
| POST | `/v1/webhooks/twilio/sms-status` | No | Twilio callback | 200 | webhooks.routes.test.ts |
| POST | `/v1/webhooks/apple/subscription` | No | Apple callback | 200 | No |

### 1.15 Timeline (`/v1/timeline`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/timeline/` | Yes | — | `{entries: [TimelineEntry]}` | No |

### 1.16 Home Timer (`/v1/home-timer`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/home-timer/` | Yes | `{label, deadline}` | `{success}` | No |
| GET | `/v1/home-timer/` | Yes | — | timer data | No |
| POST | `/v1/home-timer/dismiss` | Yes | — | `{success}` | No |
| GET | `/v1/home-timer/guardian` | Yes | — | guardian view | No |

### 1.17 Arrival Report (`/v1/arrival-report`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/arrival-report/` | Yes | report data | `{success}` | No |
| GET | `/v1/arrival-report/recent` | Yes | — | recent reports | No |

### 1.18 Itinerary (`/v1/itinerary`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/itinerary/` | Yes | itinerary data | `{success}` | No |
| GET | `/v1/itinerary/` | Yes | — | itineraries list | No |
| DELETE | `/v1/itinerary/:id` | Yes | — | `{success}` | No |

### 1.19 Medical Card (`/v1/medical-card`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| PUT | `/v1/medical-card/` | Yes | card data | `{success}` | No |
| GET | `/v1/medical-card/` | Yes | — | card data | No |
| POST | `/v1/medical-card/share` | Yes | — | share token | No |
| GET | `/v1/medical-card/share/:token` | No | — | card data (public) | No |

### 1.20 Emergency Text (`/v1/emergency-text`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/emergency-text/:lang` | No | — | emergency text templates | No |
| GET | `/v1/emergency-text/` | No | — | default template | No |

### 1.21 Organization (`/v1/org`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/org/` | Yes | org data | `{success}` | No |
| GET | `/v1/org/dashboard` | Yes | — | dashboard | No |
| POST | `/v1/org/members` | Yes | member data | `{success}` | No |
| POST | `/v1/org/alert` | Yes | alert data | `{success}` | No |
| POST | `/v1/org/roll-call/respond` | Yes | response | `{success}` | No |
| GET | `/v1/org/reports` | Yes | — | reports | No |

### 1.22 Insurance (`/v1/insurance`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| POST | `/v1/insurance/claim-materials` | Yes | — | PDF export | No |
| GET | `/v1/insurance/exports` | Yes | — | export list | No |
| POST | `/v1/insurance/claim-report` | Yes | report data | `{reportId}` | No |
| GET | `/v1/insurance/verify/:reportId` | No | — | verification result | No |

### 1.23 Consulate (`/v1/consulate`)

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/v1/consulate/` | No | — | all consulate data | No |
| GET | `/v1/consulate/:countryCode` | No | — | country consulate data | No |
| GET | `/v1/consulate/selected/me` | Yes | — | user's selected hotline | No |
| PUT | `/v1/consulate/selected` | Yes | hotline data | `{success}` | No |
| DELETE | `/v1/consulate/selected` | Yes | — | `{success}` | No |

### 1.24 Health Check

| Method | Path | Auth? | Inputs | Outputs | Existing Test? |
|--------|------|-------|--------|---------|----------------|
| GET | `/health` | No | — | `{status: "ok", service, timestamp}` | No |

---

## 2. Firestore Trigger Functions

| Function | Trigger | Collection | Document | Description |
|----------|---------|------------|----------|-------------|
| `onSOSCreated` | `firestore.document("sos_events/{sosId}").onCreate` | sos_events | new SOS doc | 4-hop escalation: push (0s) → push all (30s) → voice (90s) → share link (120s) |

---

## 3. Scheduled (Cron) Functions

| Function | Schedule | Description |
|----------|----------|-------------|
| `ttlCleanup` | `0 3 * * *` (daily 3AM Shanghai) | Delete expired data from BigQuery (free: 7d, paid: 90d), clean invites, evidence, rate limits |
| `computeIntegrityProof` | `0 4 * * *` (daily 4AM Shanghai) | Merkle root computation for heartbeat + location tables |
| `checkCheckinOverdue` | `every 15 minutes` | Send FCM reminder to guardians when protected person misses 8h check-in |
| `checkHeartbeatMissing` | `every 5 minutes` | Send FCM alert when heartbeat missing > 30 minutes |
| `checkHomeTimerExpiry` | `every 1 minutes` | Escalate expired home timers to guardians |

---

## 4. Firestore Collections & Schemas

| Collection | Doc ID | Schema | Rules |
|------------|--------|--------|-------|
| `users` | `{uid}` | displayName, phone, role, avatarInitial, timeZone, countryCode, cityName, notificationPrefs, createdAt, updatedAt | read/write: owner only; write validates displayName (string), role (protected/guardian), phone (string) |
| `guardian_links` | `{guardianId}_{protectedPersonId}` | guardianId, protectedPersonId, status (pending/active), createdAt, acceptedAt, revokedAt, protectionLayers, permissions | read: either party; create/update/delete: either party |
| `sos_events` | `{uuid}` | protectedPersonId, triggeredAt, triggerMethod, lat/lng, batteryLevel, escalationState, resolvedAt, resolvedBy, resolution, escalationLog[] | read: any auth; write: server only |
| `safe_zones` | `{uuid}` | userId, name, lat, lng, radius, isActive | read/write/delete: owner only |
| `duty_schedules` | `{uuid}` | guardianId, protectedPersonId, dayOfWeek, startHour, endHour, isActive | read: any auth; write: server only |
| `invites` | `{auto}` | code, createdBy, role, acceptedBy, status (pending/accepted/expired), createdAt, expiresAt | read: any auth; create: owner check; update: owner or pending status |
| `device_tokens` | `{auto}` | userId, token, platform, environment, updatedAt | read/write/delete: owner only |
| `timeline_entries` | `{auto}` | userId, timestamp, type, description, detail | read: owner only; write: server only |
| `family_posts` | `{auto}` → subcol `comments` | authorId, text, mediaURLs, createdAt / comment: authorId, text, createdAt | read: any auth; create: owner; update/delete: author only |
| `checkins` | `{uuid}` | userId, timestamp, lat, lng, note | (no explicit rule — covered by default deny) |
| `evidence_holds` | `{auto}` | protectedPersonId, timeWindowStart, timeWindowEnd, expiresAt | read: any auth; write: server only |
| `integrity_proofs` | `{date YYYY-MM-DD}` | date, heartbeatMerkleRoot, locationMerkleRoot, recordCount, computedAt | read: any auth; write: server only |
| `subscriptions` | `{uid}` | plan, status, expiresAt, ... | read: owner only; write: server only |
| `crash_reports` | `{auto}` | ...body, userId, receivedAt | create: any auth; read/update/delete: denied |
| `home_timers` | `{uid}` | userId, label, deadline, status, ... | (no explicit rule) |
| `medical_cards` | `{uid}` | (medical data) | (no explicit rule) |
| `selected_hotlines` | `{uid}` | (hotline data) | (no explicit rule) |
| `arrival_reports` | `{auto}` | userId, ... | (no explicit rule) |
| `itineraries` | `{auto}` | userId, ... | (no explicit rule) |
| `evidence_shares` | `{auto}` | createdBy, token, expiresAt, ... | (no explicit rule) |
| `medical_card_shares` | `{auto}` | userId, ... | (no explicit rule) |
| `rate_limits` | `{windowKey}` | count, expiresAt | (no explicit rule) |
| `claim_material_exports` | `{auto}` | userId, exportedAt, ... | (no explicit rule) |

**Default deny:** `match /{document=**} { allow read, write: if false; }` — catches all unmatched paths.

### Missing Explicit Rules (FINDING)

Collections accessed by Cloud Functions but not explicitly in `firestore.rules`:
- `checkins` — no read rule for guardians viewing check-in status
- `home_timers` — no client rules
- `medical_cards` — no client rules
- `selected_hotlines` — no client rules
- `arrival_reports` — no client rules
- `itineraries` — no client rules
- `evidence_shares` — no client rules
- `medical_card_shares` — no client rules
- `rate_limits` — no client rules (OK: only used by server middleware)
- `claim_material_exports` — no client rules

These are all caught by default deny, which means client-side reads/writes are blocked. The app works because reads go through Cloud Functions (admin SDK bypasses rules). This is secure but means the app is fully server-dependent for these collections.

---

## 5. Firestore Indexes (Composite)

| Collection | Fields | Direction |
|------------|--------|-----------|
| guardian_links | guardianId ASC, status ASC | |
| guardian_links | protectedPersonId ASC, status ASC | |
| sos_events | protectedPersonId ASC, triggeredAt DESC | |
| sos_events | protectedPersonId ASC, triggeredAt ASC | |
| timeline_entries | userId ASC, timestamp ASC | |
| timeline_entries | userId ASC, timestamp DESC | |
| duty_schedules | protectedPersonId ASC, isActive ASC | |
| device_tokens | userId ASC, updatedAt DESC | |
| safe_zones | userId ASC, isActive ASC | |
| evidence_holds | protectedPersonId ASC, expiresAt ASC | |
| checkins | userId ASC, timestamp ASC | |
| claim_material_exports | userId ASC, exportedAt DESC | |
| family_posts | authorId ASC, createdAt DESC | |

---

## 6. Security Rules Files

- `firestore.rules` — see section 4 above
- No `storage.rules` file found in repo (Storage rules may be in Firebase console)

---

## 7. Firebase Emulator Config (`firebase.json`)

```json
"emulators": {
  "functions": { "port": 5001 },
  "firestore": { "port": 8080 },
  "auth": { "port": 9099 },
  "ui": { "enabled": true }
}
```

**Missing:** Storage emulator, Pub/Sub emulator. Need to add for full harness.

---

## 8. Escalation Chain (Server-Side)

Implemented in `onSOSCreated` Firestore trigger (`triggers/onSOSCreated.ts`):

| Hop | Delay from SOS | Action | Target |
|-----|---------------|--------|--------|
| 1 | 0s | FCM push (critical alert) | On-duty guardian(s), fallback to first guardian |
| 2 | 30s | FCM push + SMS fallback (if no device tokens) | ALL guardians |
| 3 | 90s | Twilio voice call with TwiML DTMF gather | On-duty guardian(s) |
| 4 | 120s | Generate emergency share link (evidence) | System |

Each hop re-checks if SOS is resolved or frozen before proceeding.
Uses `delay()` (setTimeout) within the same function invocation (max 300s timeout, 512MB memory).

**Escalation states:** `initiated` → `hop1_notified` → `hop2_allNotified` → `hop3_voiceCalling` → `hop3_exhausted` / `frozen` / `resolved`

---

## 9. Push/SMS/Voice Services

### FCM (`services/fcm.ts`)
- `sendSOSAlert(guardianId, personName, sosId)` — critical alert, interruption-level: critical
- `sendCheckinReminder(guardianId, personName)` — standard, respects notif prefs
- `sendHeartbeatMissingAlert(guardianId, personName, minutesAgo)` — standard, respects notif prefs
- `sendSilentPush(userId)` — background push, content-available: 1
- `sendSOSResolvedNotification(protectedPersonId, resolverName)` — standard

**FINDING:** All push notification titles/bodies are hardcoded in Chinese. No locale-per-caregiver routing.

### SMS (`services/sms.ts`)
- `sendSOSSms(guardianId, personName, sosId, shareUrl?)` — emergency SMS with name + optional map link
- `sendCheckinReminderSms(guardianId, personName)` — reminder
- `sendVerificationSms(phone, code)` — OTP code
- `hasAppInstalled(userId)` — checks device_tokens collection

**FINDING:** SMS templates hardcoded in Chinese only. No per-recipient locale.

### Twilio Voice (`services/twilio.ts`)
- `initiateVoiceCall(guardianId, sosEventId, personName, callbackUrl)` — TwiML with `alice` voice
- TwiML language selection via `getTwimlLanguage(countryCode)` — maps CN→zh-CN, US/CA→en-US, etc.
- DTMF: 1=acknowledge, 2=replay

**FINDING:** TwiML language is based on the *protected person's* country, not the *guardian's* locale.

---

## 10. Rate Limiting (`middleware/rateLimit.ts`)

| Preset | Window | Max Requests | Used On |
|--------|--------|-------------|---------|
| auth | 60s | 5 | `/v1/auth` |
| sms | 10min | 3 | (available, not mounted on any route) |
| publicShare | 1h | 20 | (available) |
| general | 60s | 100 | (available) |
| sos | 1h | 3 | (available, not mounted explicitly on sos routes) |
| telemetry | 60s | 120 | `/v1` telemetry routes |

**FINDING:** SOS rate limit preset exists but is NOT applied to the SOS route. Only auth and telemetry have rate limiters mounted.

---

## 11. BigQuery Integration (`services/bigquery.ts`)

Dataset: `shoudeng`

Tables (inferred from code):
- `heartbeat_signals` — userId, timestamp, source, batteryLevel, batteryState, lat, lng, accuracy
- `location_reports` — userId, lat, lng, accuracy, altitude, speed, timestamp, isInSafeZone, safeZoneName
- `checkins` — userId, timestamp, lat, lng, note
- `consent_audit` — userId, consentType, action, grantedTo, detail, timestamp

---

## 12. Existing Backend Tests

| File | Coverage |
|------|----------|
| `sos.routes.test.ts` | SOS trigger and resolve routes |
| `rateLimit.test.ts` | Rate limiting middleware |
| `webhooks.routes.test.ts` | Twilio webhooks |
| `auth.middleware.test.ts` | Auth middleware token verification |
| `e2e-bots.test.ts` | End-to-end bot scenarios |

**Total:** 5 test files. No rules tests, no scheduled function tests, no schema validation tests.

---

## 13. iOS Location/Sensor Pipeline — Exact Constants

### 13.1 Adaptive Location Manager (`Core/Algorithms/AdaptiveLocationManager.swift`)

**5 Sampling Modes:**

| Mode | desiredAccuracy | distanceFilter | reportInterval |
|------|----------------|---------------|----------------|
| safe | hundredMeters | none | infinity (sigchange only) |
| unknown | hundredMeters | 50m | 600s (10 min) |
| moving | nearestTenMeters | 30m | 60s (1 min) |
| sos | best | none | 5s |
| lowBattery | hundredMeters | 100m | 1200s (20 min) |

**Config Defaults:**
- `movingSpeedThreshold`: 1.5 m/s (walking speed)
- `stationarySpeedThreshold`: 0.5 m/s
- `deduplicationDistanceMeters`: 50m
- `deduplicationTimeSec`: 120s
- `maxGeofenceRegions`: 19 (reserves 1 of iOS 20 for buffer zone)
- `dwellPointRadiusMeters`: 200m
- `dwellPointMinDurationSec`: 1200s (20 min)
- `safeZoneHysteresisMeters`: 50m
- `lowBatteryThreshold`: 0.15 (15%)
- `bufferZoneRadius`: 2000m

### 13.2 Trajectory Processor (`Core/Algorithms/TrajectoryProcessor.swift`)

**4-Layer Pipeline:** Filter -> Kalman Smooth -> Douglas-Peucker -> Segment

**Config Defaults:**
- Layer 1 Filter: `maxAccuracyMeters` = 100m, `maxSpeedKmh` = 200, `flyingSpeedKmh` = 1200
- Layer 2 Kalman: 1D per lat/lng, process noise = `dt * speed^2 * 1e-10`, gain = `variance / (variance + accuracy^2)`
- Layer 3 Douglas-Peucker: `simplificationEpsilon` = 15m
- Layer 4 Segment: `dwellRadiusMeters` = 200m, `dwellMinDurationSec` = 1200s (20 min)
- Transport thresholds: walk < 5 km/h, bike < 20, car < 120, above = flying

### 13.3 Fall Detector (`Core/Algorithms/FallDetector.swift`)

**4-Stage Sequential Pipeline:** Free-fall -> Impact -> Orientation -> Stillness -> 60s confirmation

**Config `youngAdult` (default):**
- Stage 1 Free-fall: SVM < `0.6g` for > `100ms`
- Stage 2 Impact: SVM > `2.5g` within `500ms` of free-fall end
- Stage 3 Orientation: gravity vector rotation > `60 degrees`, sample window `2.0s`
- Stage 4 Stillness: SVM variance < `0.05` for `15.0s`
- Confirmation timeout: `60.0s` (user taps "I'm fine" or escalates to SOS)
- Sample rate: `50Hz`

**Config `elderly`:**
- Free-fall: `0.65g`, Impact: `2.0g`, Orientation: `50 deg`, Stillness variance: `0.06`, duration: `10.0s`

**Config `phoneInPocket`:**
- Impact: `3.0g`, Orientation: `45 deg`

### 13.4 Baseline Scorer (`Core/Algorithms/BaselineScorer.swift`)

**Missing-Person Detection via Personal Baseline Anomaly Scoring:**
- `baselineDaysRequired`: 14 days
- `baselineWindowDays`: 30 days rolling
- `yellowThreshold`: 0.45, `redThreshold`: 0.70

**5 Weighted Factors (sum = 1.0):**

| Factor | Weight | Description |
|--------|--------|-------------|
| Check-in overtime | 0.35 | Gap vs historical max/avg |
| Phone inactivity | 0.25 | Heartbeat gap vs historical max |
| Location anomaly | 0.20 | Grid cell frequency + time-slot match |
| Battery anomaly | 0.10 | < 10% unplugged = 0.9, < 20% = 0.5 |
| Regional risk | 0.10 | Server-provided 0-1 score |

Grid cell resolution: `lat*1000` / `lng*1000` rounded (~111m).
Fallback fixed thresholds when baseline < 14 days: 24h no check-in = +0.4, 12h = +0.2, 8h inactive = +0.2.

### 13.5 Heartbeat Service (`Services/Network/HeartbeatService.swift`)

- `maxHeartbeatsPerHour`: 12
- `minIntervalBetweenBeats`: 60s
- `batteryReportThreshold`: 0.05 (5%)
- 6 beat sources: appForeground, significantLocation, silentPush, pushReceipt, regionEvent, watchSync
- Battery alerts: < 5% critical, < 15% warning
- Background burst (MotionService): 3s, variance < 0.02 = prolongedStillness

### 13.6 Motion Service (`Services/Motion/MotionService.swift`)

- Device motion update interval: 1/50 = 0.02s (50Hz)
- Reference frame: `xArbitraryZVertical`
- Background burst: 3.0s duration, 50Hz, variance threshold 0.02
- States: stopped, foreground (full 50Hz), backgroundBurst (brief), watchDelegated

### 13.7 Push Service (`Services/Push/PushService.swift`)

- 4 notification categories: SOS_ALERT, SAFETY_WARNING, CHECKIN_REMINDER, DUTY_HANDOFF
- Critical alert: `criticalSoundNamed("sos_alert.caf")`, volume 1.0, interruption `.critical`
- Action buttons hardcoded in Chinese: "我已接手", "立即拨号", "我知道了", "我很好，报个平安"

### 13.8 Other Key iOS Files

| File | Purpose |
|------|---------|
| `Services/Escalation/DutyScheduler.swift` | Client-side duty schedule |
| `Services/Compliance/DeviceHealthMonitor.swift` | Permission, battery, connectivity |
| `Services/Auth/KeychainHelper.swift` | Keychain access (afterFirstUnlockThisDeviceOnly) |
| `Services/Auth/AuthManager.swift` | Token refresh (serialized) |
| `Services/Auth/BiometricAuthManager.swift` | Face ID / Touch ID |
| `Services/Network/OfflineQueue.swift` | Request queuing + replay |
| `Services/Network/APIClient.swift` | HTTP client with auth headers |
| `Services/DeepLink/DeepLinkRouter.swift` | Universal link handling |
| `Services/Compliance/ConsentLogger.swift` | JSONL append-only consent log |
| `Services/Localization/LanguageManager.swift` | EN/zh-Hans/FR language switching |

---

## 14. iOS API Endpoints Used (from APIClient calls)

Counted from AppCoordinator.swift and all Views/Services:

| Endpoint | Called From |
|----------|------------|
| GET `/v1/user/me` | AppCoordinator.fetchUserProfile |
| PUT `/v1/user/me` | ProfileEditView |
| PUT `/v1/user/notification-preferences` | AppCoordinator.syncNotificationPrefs |
| POST `/v1/user/delete` | ProtectedSettingsView, GuardianSettingsView |
| GET `/v1/guardian/protected-persons` | AppCoordinator.fetchProtectedPersons |
| GET `/v1/protected/guardians` | AppCoordinator.fetchGuardians |
| PUT `/v1/protected/guardians/:id/permissions` | AppCoordinator.updateGuardianPermissions |
| DELETE `/v1/protected/guardians/:id` | AppCoordinator.removeGuardian |
| POST `/v1/invite/create` | AppCoordinator.createInviteCode |
| POST `/v1/invite/accept` | InviteAcceptView (deep link) |
| POST `/v1/sos/trigger` | AppCoordinator.triggerSOS (postQueued) |
| POST `/v1/sos/resolve` | AppCoordinator.cancelSOS (postQueued) |
| POST `/v1/voice-call` | EscalationEngine (postQueued) |
| POST `/v1/heartbeat` | HeartbeatService (postQueued) |
| POST `/v1/location/report` | AppCoordinator.handleLocationUpdate (postQueued) |
| POST `/v1/checkin` | AppCoordinator.performCheckIn (postQueued) |
| POST `/v1/device/token` | AppCoordinator.registerDeviceToken (postQueued) |
| GET `/v1/timeline` | AppCoordinator.fetchTimeline |
| GET `/v1/family/posts` | AppCoordinator.fetchFamilyPosts |
| POST `/v1/family/posts` | AppCoordinator.createFamilyPost |
| POST `/v1/family/posts/:id/comments` | AppCoordinator.addComment |
| POST `/v1/family/upload` | AppCoordinator.uploadMedia |
| GET `/v1/consulate/selected/me` | AppCoordinator.loadSelectedHotline |
| PUT `/v1/consulate/selected` | AppCoordinator.saveSelectedHotline |
| DELETE `/v1/consulate/selected` | AppCoordinator.removeSelectedHotline |

---

## 15. Coverage Summary

| Area | Routes/Functions | With Tests | Coverage |
|------|-----------------|------------|----------|
| HTTP API routes | ~55 endpoints | 4 files (SOS, webhooks, auth, rate limit) | ~7% |
| Firestore triggers | 1 | 0 | 0% |
| Scheduled functions | 5 | 0 | 0% |
| Firestore rules | 14 collection rules | 0 | 0% |
| iOS services | 18 modules | 213 Swift tests (mixed) | partial |

**Critical gaps:** Firestore rules, scheduled functions, escalation trigger, schema validation, cross-family isolation.
