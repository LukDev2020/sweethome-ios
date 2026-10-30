# Explore Mode — implementation report

Branch `feat/explore-mode-truth`, cut from `qa/loop-2026-10-20` @ 5b813cd. Not merged, not pushed, nothing deployed.

| Commit | Workstream |
|---|---|
| c178108 | W0-5 app lifecycle through the SwiftUI scene (scenePhase, onOpenURL, universal links, SOS-link confirmation) |
| a22f4de | W0-1..4 guardian dashboard decode, timeline, Firestore indexes, missing routes (+ fake Firestore / contract fixtures) |
| 25888a0 | 0-warning baseline under Xcode 27.1 |
| 14eda4d | W1 raw keys, unformatted strings, SOS button overlap, globe labels |
| 9fcbf91 | W2 backend: durable escalation, acknowledge, active-SOS reads, Home Safe push, router auth bleed, rate limits, Twilio, time zones, voice language |
| 69e5695 | W2 iOS: guardian response, 3 s hold, SOS screen for every trigger, offline delivery, trigger paths, location, medical card, keychain, critical-alert gating |
| f6d6d87 | W2 follow-up: format keys that dropped their arguments, honest SOS banner |
| 4d714ef | W3 Firestore rules + real emulator tests, evidence share authorization |
| 12abfc6 | W4 Explore Mode |

Final state: iOS 302 tests pass, 0 warnings (clean build of app + widgets, and the test target); backend `npx jest` 501 pass (20 rules tests skipped without an emulator), `npm run test:rules` 20/20 against the Firestore emulator (11 of them fail against the old rules).

## Storyboard claims → commits that make them true

| # | Claim | Commits |
|---|---|---|
| 1 | "Try a demo first — no account needed" on login | 12abfc6 (login + last onboarding page) |
| 2 | Meet the Chen family, live local times, Mom's or Sarah's phone | 12abfc6 |
| 3 | Guardian dashboard: status, city, local time, last check-in, protection layers; tap for details | a22f4de (BigQuery timestamps → ISO, Firestore-first telemetry, per-item decoding, `checkins` index), 14eda4d (raw keys, battery label, globe, SOS overlap), 69e5695 (guardians list decoded `timeZone` strings — the whole list used to fail) |
| 4 | Home Safe: "one tap lets Sarah, Kevin and Lucy know you arrived" | 9fcbf91 (push to every guardian, city + local time, prefs, 10-min dedupe), 69e5695 (widget / Live Activity check-in reach the server, guardian language synced) |
| 5 | Practice SOS: hold 3 s → alert, then a text, then a phone call until someone responds | 9fcbf91 (durable state machine: push → all → 3 voice rounds with the link SMS in between, idempotent, scheduler backstop; no-guardians → emergency contacts), 69e5695 (3 s hold everywhere, SOS screen for every trigger path, offline delivery, dead-man / fake-call / widget / disguise paths, SOS location mode), f6d6d87, 4d714ef |
| 6 | Hand-off "Meanwhile in Toronto…" | 12abfc6 |
| 7 | Sarah's push with location + battery, Needs Attention card, "call her or press I've got it so Kevin and Lucy know and the automatic calls stop" | 9fcbf91 (push payload, `GET /v1/guardian/sos/active`, `activeSOS` on the dashboard, `POST /v1/sos/acknowledge`, keypad "1" via CallSid, router auth fix so Twilio callbacks aren't 401), 69e5695 (GuardianAlertResponseView on live state, push routing, push "I've got it" calls the server), 4d714ef |
| 8 | Checklist: duty-schedule coverage gaps, export records, "Set up my real family" | 12abfc6; 9fcbf91 + 69e5695 make the coverage screen and the real escalation use the same time-zone / overnight-slot rules |

## Changed in copy instead of code
- `NSMotionUsageDescription` (en/zh/fr): fall detection works **while the app is open** (iOS gives no continuous background accelerometer); it no longer claims a toggle that doesn't exist.
- Voice call: "we will call again in about two minutes until someone responds" (matches the 3 voice rounds) instead of "in one minute".
- "No guardians yet" alert and the SOS banner ("sending / family alerted / no guardians — call {local number}") — the old banner claimed "family notified" before anything was sent, in Chinese, with 112.
- Hold-to-SOS: code changed to 3 s to match the existing copy (no copy change). Fake-call auto-SOS made real (no relabel).

## Needs you
- **Deploy** (not done): `firestore.indexes.json` (11 new composite indexes), `firestore.rules`, functions (new routes, new scheduled function `advanceEscalations` every minute — needs Cloud Scheduler).
- **Apple**: request the Critical Alerts entitlement (docs/critical-alerts-entitlement-application.md). Meanwhile the app ships the **Time Sensitive Notifications** entitlement — enable that capability on the App ID / profile. After approval: add `com.apple.developer.usernotifications.critical-alerts`, build with the `CRITICAL_ALERTS` Swift flag, set `CRITICAL_ALERTS_ENABLED=true` for functions.
- **Twilio / secrets**: `twilio.account_sid`, `twilio.auth_token`, `twilio.from_number` (voice), `twilio.sms_from`; point status callbacks at `/v1/webhooks/twilio/*`. Set `PUBLIC_API_BASE_URL` if the API is served from a custom domain (signatures are computed over it; default `https://us-central1-<project>.cloudfunctions.net/api`). Consider moving these from `functions.config()` to Secret Manager.
- **Sound**: `ShouDeng/sos_alert.caf` is a generated 3 s two-tone placeholder — replace with a designed sound if wanted.
- **Rules tests** need Java: `npm run test:rules` uses Homebrew `openjdk` by default.
- Release build: bump CFBundleVersion in both places before TestFlight.

## Follow-ups noticed (not done)
- `DisclaimerCopy` degradation-banner messages are Chinese-only (seen in the English UI).
- `/v1/payment/*` (PaymentMethodManager) and `/v1/device/crowd-tags` are called by unreachable code with no backend route (allowlisted in `route.inventory.test.ts`).
- iOS DEBUG/Release base URLs use project `sweethome-b4e82`; project memory says `sweethome-d1edd` — check which is current.
