# Beaconify / 守灯 — Production gap review (2026-11-22)

Scope: build 59, `release/1.0-integration` @3ad06f5. Four read-only reviews (backend, iOS, compliance, release/ops); the top findings were re-checked by hand against the code.

**Verdict:** the core SOS design is solid (durable server escalation, idempotent trigger, offline queue, SMS fallback, IDOR checks, honest disclaimers, full 5-language parity). It is **not yet safe for a public launch** because of a handful of places where an SOS can silently fail to reach anyone, plus no monitoring to notice when it does. Launch scope should be **Canada / US / Japan, adults**. China and the EU need business/legal work first.

**Update (same day):** fixed in code — P0 #1–6, #9, #10 (high/critical gone; 13 moderate left need breaking upgrades), #11, #13. Still open: #7, #8, #12, #14 (console / business). Backend changes need `firebase deploy` (functions, firestore:indexes, storage) to take effect.

Legend: [code] = we fix in the repo · [you] = App Store Connect / console / business / lawyer

---

## P0 — before public launch

### SOS can fail silently
1. **Monthly fair-use cap can block an SOS entirely** [code] — the SMS to a guardian whose push failed (or who has no app) counts against 50 SMS / 30 call-min per month; once used up, that guardian gets nothing usable. `functions/src/services/escalation.ts:233,290,311`, `fairUse.ts:14`. Fix: first SMS + first call per guardian per SOS are never capped; cap only repeats.
2. **Failed SOS isn't retried while online** [code] — queue only flushes on reconnect / foreground / login; a 5xx or timeout on a "reachable" network leaves it queued. Duress SOS has no screen. `AppCoordinator.swift:267,475,670`. Fix: backoff retry (5→60 s) while a `/v1/sos/trigger` item is queued.
3. **No background task around the SOS request** [code] — `clearPendingSOS` ends it (`AppCoordinator.swift:1586`) before `triggerSOS` posts (`:1689`); fall/duress/voice/dead-man triggers have none. Fix: begin/end a background task inside `triggerSOS`.
4. **Dead-man switch (safety timer) is phone-only** [code] — relies on BGAppRefresh; dead/killed phone = no SOS, while copy and review notes say it "sends the SOS". `DeadManSwitchService.swift:25,620`. Fix: store deadline on the server like the home timer (already server-side), or reword + limits notice.
5. **Relaunch heartbeat reports location 0,0** [code] — `AppDelegate.swift:67-75` posts lat/lon 0; guardians can see it. Fix: send `CLLocationManager().location` or no location.
6. **SOS function runs cold** [code] — `api` has no `minInstances`, 256 MB, us-central1 (`functions/src/index.ts:14`). Fix: `minInstances: 1` (or split `/v1/sos/*` into a warm function).

### Nobody would notice an outage
7. **No monitoring/alerting** [code + you] — `/health` is static (`app.ts:166`); no alerts on escalation/APNs/Twilio errors or missed scheduled jobs (checkinOverdue, heartbeat, advanceEscalations). Fix: uptime check on a deep health endpoint + log-based alerts paging a real person.
8. **No backup / runbook** [you] — no Firestore PITR or daily export visible; no SOS-outage or rollback runbook. Fix: enable PITR + scheduled export; one-page runbook.

### Security / data
9. **No Storage security rules in repo** [code] — `firebase.json` only configures the storage emulator; bucket holds evidence PDFs, GPX, family media. Fix: deploy deny-all `storage.rules` (all access is via Admin SDK + signed URLs).
10. **18 npm vulnerabilities (1 critical, 4 high)**, all fixable [code] — `npm audit fix`.

### App Store / legal
11. **Hidden features not disclosed to App Review (2.3.1)** [code/metadata] — disguise mode (calculator/weather/notes), duress code, silent alarm, fake call (CallKit) missing from `metadata/review_notes.txt`. Fix: one paragraph each: what, how to trigger, how to exit.
12. **"Kids" in marketing, no age gate** [you + code] — description says "kids coming home late"; policy says not for under 13; no age question at signup. Fix: drop "kids" from the listing for 1.0 (simplest), or add age gate + parental consent.
13. **Privacy URL in Info.plist doesn't resolve** [code] — `NSPrivacyPolicyURL` = `https://shoudeng.app/privacy`; associated domains also list `shoudeng.app` (someone else could register it). Fix: point to `omni-webb.web.app/beaconify/privacy`; drop or register the domain.
14. **Storefronts** [you] — keep **China mainland** off (no ICP, relay not deployed — `API_RELAY_URL` empty, PIPL rep/CAC transfer, CallKit banned) and **EU/France** off (DSA trader status, GDPR Art. 27 representative, DPIA) until done.

---

## P1 — soon after launch

**iOS**
- Map spans uncapped → same class of crash as the 180° bug: `TripDetailView.swift:273`, `TripReport.swift:548`, `IncidentReportBuilder.swift:209`. One shared clamp helper.
- SOS uses `lastReportedLocation` (can be hours old in safe mode), no fix time/accuracy sent (`AppCoordinator.swift:1677`).
- Always→When-In-Use downgrade and Precise-off not detected (`AdaptiveLocationManager.swift:564`, `DeviceHealthMonitor.swift:108`); guardians not told.
- Crash reporting broken: custom `CrashReporter` replaces Crashlytics handlers without chaining (`CrashReporter.swift:27-38`); no dSYM upload phase.
- No force-update / kill switch (no app-version header, no Remote Config).
- GPS never pauses when stationary outside all safe zones → battery drain for people with no zones.
- Offline queue unbounded, whole-file rewrite on main thread (`OfflineQueue.swift:108`).
- 3 unguarded `print`, 8 `NSLog` in Release (one logs part of a push token, `GuardianActivityManager.swift:334`).
- VoiceOver: SOS hold buttons have no accessibility action; ~10 icon buttons unlabeled.
- Critical Alerts entitlement: apply to Apple (code is correctly gated off).

**Backend**
- Crew codes 6 chars from `Math.random`, `/v1/crew/join` not rate-limited → brute force gets SOS + live location (`services/crew.ts:114`, `routes/crew.ts:45`).
- `JWT_SECRET` in plain `.env`, not Secret Manager (`services/session.ts:8`).
- Account delete/export inside 60 s request; deletion misses `sos_usage`, `voice_calls`, `sms_delivery_log`, evidence files.
- Firestore retention: SOS trail, timeline, SMS log, voice calls, BLE sightings never purged; `rate_limits` grows unbounded → TTL policies.
- Scheduled jobs scan all users serially (heartbeat every 5 min, check-in every 15); `advanceEscalations` 60 s timeout, sequential.
- e2e suite: namespaced `admin.firestore.Timestamp` (171 uses) + wrong project id `sweethome-d1edd` in `e2e-bots.test.ts:24`.

**Release / ops**
- CI dead: only triggers on `main` (release branch is 171 ahead), Xcode 16 vs iOS 26 APIs, Node 20 vs 22, no GoogleService-Info in CI; TestFlight job's `agvtool` would break build numbering.
- Single Firebase project: TestFlight testers' SOS land in prod. Add staging.
- `functions/lib` half-tracked in git; `.gitignore` missing `.secret.local`, `.firebase/`, service-account patterns.
- No XCUITest smoke test (sign-in → SOS → guardian receives).

**Compliance**
- App description over-promises fall detection (doesn't say "while app is open").
- Review notes list wrong IAPs, omit Alipay, Ultimate org plan needs 3.1.3(c) explanation.
- In-app policy (Oct 31) differs from web policy (Nov 18); one source.
- No in-app consent withdrawal.
- Privacy officer, business address, non-gmail contact, French policy (PIPEDA / Law 25).
- Terms say "personal, non-commercial" but rider crews + org dashboard exist; policy doesn't mention crew/org sharing.
- Fake call via CallKit without VoIP may draw 2.5.1 — disclose, have fallback.

## P2 — nice to have
Paywall links Apple EULA instead of own Terms · App Privacy label: add activity type · remove unused `CrowdSourcedBLEService` · Japan external-transmission notice · 219 fixed-size fonts (rider/weather views) · a few hardcoded Chinese strings · `AppCoordinator` not `@MainActor` · dead watch code · invite codes 24-bit · region choice for Asia · build-bump script · stale `project.yml`.

## Already solid
- Server SOS escalation: transactional state machine, per-target sent markers, 1-min backstop, idempotent by `clientSOSId`; APNs direct with retry + SMS fallback.
- Client: SOS persisted before send, dual-route, survives logout/relaunch; SMS-from-phone fallback after 15 s.
- Webhooks verified (Twilio HMAC, Apple signed data, Alipay RSA2); Apple sign-in nonce/aud checked; IDOR checks consistent; Firestore rules default-deny.
- Paywall disclosures, Restore, in-app account deletion + SIWA revoke, export, cross-border consent, privacy manifests, Critical Alerts correctly gated.
- Tests: iOS 524, backend 979 passing; tsc clean; 5 languages × 2642 keys in parity; no secrets in git history.
