# Agent: Scenario Director

## Purpose
Orchestrates persona-driven test scenarios. Dispatches commands to persona agents and backend-observer, manages simulated clock, captures screenshots, and collects assertions.

## Scenarios (S1–S12)

### S1: Onboarding — Fresh Install to Family Joined
- **Actors**: haozi (protected), father (guardian)
- **Flow**: Install → 3 disclaimer screens → phone verify → role select "protected" → father sends invite → haozi accepts → guardian link active
- **Assertions**:
  - 3 onboarding consent records logged (onboard.not_emergency, onboard.scope, onboard.control)
  - Copy version = "v1.1"
  - User doc created with role=protected, countryCode=CA, timeZone=America/Toronto
  - Guardian link doc created with status=active
  - Feature disclosures shown for location, fallDetect, sos

### S2: Normal Day — Campus + Gym + Home
- **Actors**: haozi, mother (on-duty 08:00–20:00 EDT)
- **Clock**: Weekday, 08:00–23:00 EDT
- **Flow**: Wake at home (safe zone) → subway to campus → arrive campus (safe zone) → 4h at campus → gym (safe zone) → home → check-in at 22:00
- **Assertions**:
  - Safe zone enter/exit timeline entries
  - Heartbeats at natural intervals (max 12/hr)
  - Location reports during transit (moving mode = 60s interval)
  - No GPS polling while in safe zones
  - Check-in recorded before 22:00 + 8h = 06:00 next day threshold
  - Battery level reported with heartbeats
  - Mother sees green status during day

### S3: Missed Check-In — 8h Overdue Escalation
- **Actors**: haozi, father (on-duty)
- **Clock**: Simulate Oct 3 — haozi forgets to check in
- **Flow**: Last check-in > 8h ago → checkinOverdue scheduled function fires → guardian notification sent
- **Assertions**:
  - `checkinOverdue` function triggers after 8h
  - Timeline entry type=missedCheckIn
  - FCM notification sent to on-duty guardian
  - Safety status changes to pendingCheckIn → overdue

### S4: SOS Full Escalation — Long Press to Voice Call
- **Actors**: haozi (trigger), father (on-duty, slow response), mother
- **Clock**: 15:00 EDT (07:00 CST next day — father on duty)
- **Flow**: Haozi long-presses SOS → hop 1 push to father → 30s no response → hop 2 push+SMS to all → 60s no response → hop 3 voice call to father → father answers → resolves
- **Assertions**:
  - SOS doc created with triggerMethod=longPress, escalationState=initiated
  - Backend delays: hop1→2 = 30s, hop2→3 = 60s, hop3→4 = 30s
  - Escalation states progress: initiated → hop1_notified → hop2_allNotified → hop3_voiceCalling → resolved
  - Timeline entries: sosTriggered, sosResolved
  - Resolution = guardianConfirmedSafe
  - FCM notification with interruption-level=critical
  - Voice call initiated via Twilio
  - Rate limit: 3 SOS per hour enforced

### S5: Fall Detection — Auto-SOS After 60s Confirmation Timeout
- **Actors**: haozi (fall), father (on-duty)
- **Clock**: 14:00 EDT
- **Flow**: Accelerometer detects fall (free-fall → impact → orientation change → stillness) → 60s confirmation dialog → no response → auto-SOS triggered
- **Assertions**:
  - Fall detection pipeline: freeFall(0.6g, 100ms) → impact(2.5g, 500ms window) → orientation(60deg, 2s) → stillness(0.05 variance, 15s)
  - Confirmation dialog shown for 60s
  - If user taps "I'm fine" within 60s → no SOS
  - If timeout → triggerMethod=fallDetection, auto-SOS
  - SOS escalation chain starts normally

### S6: Battery Death — 9h Offline
- **Actors**: haozi (offline), father, mother
- **Clock**: Simulate Oct 11 — phone dies at 14:00, comes back at 23:00
- **Flow**: Battery drops to 5% → critical alert → battery dies → no heartbeats → 30min threshold → heartbeatCheck fires → guardian notified → 9h later phone boots → heartbeat resumes
- **Assertions**:
  - Battery 5% critical alert sent
  - After 30min no heartbeat → heartbeatCheck function fires
  - Guardian notification: "设备离线提醒"
  - Safety status → unreachable
  - Degradation warning: device_offline (caution at <4h, critical at >=4h)
  - On phone boot: heartbeat resumes, status recovers

### S7: Trajectory Consent Toggle
- **Actors**: haozi
- **Flow**: Haozi currently has trajectory=false → opens settings → enables trajectory → consent logged → disables trajectory → revocation logged
- **Assertions**:
  - Consent log entry: item=consent.trajectory, action=granted, copyVersion=v1.1
  - Feature disclosure shown (requiresOptIn=true, isHighSensitivity=true)
  - Second entry: action=revoked
  - Trajectory data collection starts/stops accordingly

### S8: Subscription Upgrade — Free to Family Plan
- **Actors**: father (payer)
- **Flow**: Father on free plan → views upgrade options → selects family.monthly → StoreKit sandbox purchase → plan activates
- **Assertions**:
  - StoreKit product ID: com.shoudeng.app.family.monthly
  - Receipt validated on backend
  - User plan updated in Firestore
  - TTL retention changes: free 7d → paid 90d
  - Features unlocked (trajectory history, evidence export)

### S9: Accessibility — Mother with Dynamic Type xxLarge + VoiceOver
- **Actors**: mother (iPhone SE, xxLarge, VoiceOver)
- **Flow**: Navigate through all main screens with VoiceOver enabled
- **Assertions**:
  - No text truncation on any screen
  - All buttons have accessibility labels
  - VoiceOver can navigate full SOS flow
  - Minimum tap target 44x44pt
  - SOS button accessible and labeled
  - Guardian dashboard readable at xxLarge
  - No overlapping elements on iPhone SE

### S10: Insurance Claim Report
- **Actors**: haozi
- **Clock**: Oct 12
- **Flow**: After SOS event → haozi opens claims → creates claim report draft → attaches 2 photos → generates PDF
- **Assertions**:
  - Claim report created in Firestore (insurance_claims collection)
  - 2 photo attachments uploaded to Cloud Storage
  - Evidence hold created (prevents TTL deletion)
  - Report includes SOS event reference, timeline entries, location data

### S11: Cross-Border Reachability
- **Actors**: father (cn-lossy network)
- **Flow**: Father in Shenzhen accesses all API endpoints under cn-lossy network profile
- **Assertions**:
  - All API calls complete within 10s (300ms latency + 10% loss)
  - FCM push delivered via APNs pathway
  - Geocoding returns Chinese addresses (language=zh-CN)
  - SMS to +86 uses Twilio (known limitation F-011)
  - TwiML voice language = zh-CN for CN users
  - No Google Maps direct calls from client (uses backend proxy)

### S12: Leaving Family — Guardian Revocation
- **Actors**: haozi, father
- **Flow**: Haozi revokes father as guardian → guardian link deactivated → father loses access → haozi's data inaccessible to father
- **Assertions**:
  - Guardian link status → revoked
  - Father can no longer see haozi's location/battery/health
  - Firestore rules deny father read access to haozi's data
  - Timeline entry logged
  - Father's protected persons list no longer includes haozi
  - If haozi triggers SOS, father does NOT receive notification

## Orchestration Protocol
1. Boot required simulators (up to 3 concurrent)
2. Seed Firestore via `qa/seed-chen.ts` (emulator or staging)
3. For each scenario:
   a. Set simulated clock if needed
   b. Dispatch persona agent commands
   c. Backend-observer watches for expected state changes
   d. Capture screenshots at key moments
   e. Collect pass/fail assertions
   f. Log timing data
4. Generate report in `qa/reports/chen/summary.md`

## Screenshot Naming Convention
`S{scenario}_{step}_{persona}_{description}.png`
Example: `S4_03_haozi_sos-confirmation-dialog.png`

## Report Format
- Per-scenario: pass/fail, assertion table, screenshot links, timing
- Summary: total pass/fail, coverage gaps, findings
- Timing table: scenario durations, escalation timing accuracy
