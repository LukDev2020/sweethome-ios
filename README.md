# 守灯 (ShouDeng) — Family Safety App

A cross-timezone family safety platform for iOS, enabling real-time location sharing, SOS escalation, and check-in monitoring between protected persons and their guardians.

## Architecture

```
sweethomeios/
├── ShouDeng/                  # iOS app (SwiftUI, iOS 17+)
│   ├── App/                   # AppCoordinator, AppDelegate, lifecycle
│   ├── Core/                  # Algorithms (location, escalation, baseline scoring)
│   ├── Models/                # Data models (User, SOSEvent, Guardian, etc.)
│   ├── Services/              # Auth, Network, Push, Payment, LiveActivity
│   └── Views/                 # SwiftUI views by role
│       ├── Protected/         # Protected person screens (A1-A6)
│       ├── Guardian/          # Guardian screens (B1-B6)
│       └── Shared/            # Common views (profile, feed, contacts)
├── ShouDengWidgets/           # WidgetKit extension (lock screen + home screen widgets)
│   ├── Widgets/               # Widget definitions (Protected, Guardian, Timer)
│   ├── Views/                 # Widget view implementations per family size
│   ├── Providers/             # Timeline providers for each widget
│   ├── Intents/               # CheckIn and DismissTimer app intents
│   ├── ProtectedLiveActivity  # Live Activity for protected person role
│   └── GuardianLiveActivity   # Live Activity for guardian role
├── Shared/                    # Code shared between app + widget extension
│   ├── GuardianActivityAttributes   # Guardian Live Activity data model
│   ├── ProtectedActivityAttributes  # Protected Live Activity data model
│   ├── SharedColors                 # Brand colors
│   ├── WidgetState                  # Widget data store model
│   └── WidgetDataStore              # App Group UserDefaults bridge
├── shoudeng-backend/          # Firebase Cloud Functions (Node.js 20 / TypeScript)
│   └── functions/src/
│       ├── routes/            # Express REST API (24 endpoints)
│       ├── triggers/          # Firestore event triggers (SOS escalation)
│       ├── scheduled/         # Cron jobs (heartbeat, check-in, TTL cleanup)
│       ├── services/          # FCM, Twilio, BigQuery, Storage, Payment
│       └── middleware/        # Auth verification, rate limiting
├── docs/                      # Technical architecture documents
└── ShouDengTests/             # Test target (pending)
```

## Key Features

- **Dual-portal design**: Protected person (被守护者) and Guardian (守护者) views
- **Live Activity lock screen cards**: Role-specific cards on the lock screen & Dynamic Island
  - Guardian card: per-person status, city, battery, priority call button
  - Protected card: guardian avatars with online/duty status, SOS + check-in buttons
- **Lock screen widgets**: WidgetKit accessory widgets (inline, circular, rectangular) + home screen (small, medium)
- **4-hop SOS escalation**: Push → SMS → Twilio voice call → emergency share link
- **Adaptive location tracking**: 5 modes from passive to SOS-grade high-frequency
- **Cross-timezone world clocks**: Dynamic display of family members' local times
- **Interactive globe + map**: MapKit with tappable family member pins
- **Family feed**: WeChat-style social feed with comments and media
- **Emergency contacts**: Regional emergency numbers + custom contacts with address book import
- **StoreKit 2 subscriptions**: 3 tiers (单人关注版 `single`, 家庭版 `family`, 企业版 `ultimate`) with monthly/yearly plans; product IDs `com.shoudeng.app.<plan>.<monthly|yearly>`
- **Data integrity**: SHA-256 row hashing + daily Merkle root proofs via BigQuery
- **Evidence system**: Exportable PDF/JSON/GPX bundles with time-limited share links
- **Offline resilience**: Disk-backed offline queue for critical operations (SOS, heartbeat)

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS UI | SwiftUI + MapKit + SceneKit (globe) |
| State | ObservableObject (AppCoordinator) |
| Auth | Firebase Phone Auth + Keychain token storage |
| Network | URLSession + custom APIClient with retry/offline queue |
| Backend | Firebase Cloud Functions + Express.js |
| Database | Firestore (17 collections) + BigQuery (4 time-series tables) |
| Push | FCM with critical alerts (APNs priority 10) |
| Voice | Twilio Programmable Voice (IVR with Chinese prompts) |
| Payments | StoreKit 2 + server-side receipt verification |
| Storage | Firebase Cloud Storage (evidence bundles) |

## Backend API

24 endpoints across 14 route files:

- **Auth**: phone OTP login, signup, token refresh
- **User**: profile CRUD, notification prefs, data export, account deletion
- **Relationships**: invite create/accept, guardian link management
- **Telemetry**: heartbeat, location report, check-in
- **SOS**: trigger, resolve, voice call initiation
- **Family**: posts CRUD, comments, media upload
- **Timeline**: activity log retrieval with pagination
- **Payment**: plans, subscription status, receipt verification
- **Evidence**: bundle generation, share token creation
- **Safe zones / Duty schedule**: geofence and shift management

## Firestore Security

- Owner-only access for user profiles, device tokens, timeline entries
- Guardian links require the requesting user to be one party
- Field-level validation on users (role, displayName, phone) and invites
- Server-write-only collections: SOS events, duty schedules, evidence holds, integrity proofs
- Default deny for all unmatched paths

## Development

### Prerequisites

- Xcode 16+ (iOS 17 deployment target)
- Node.js 20+
- Firebase CLI (`npm install -g firebase-tools`)

### iOS App

```bash
# Open in Xcode
open ShouDeng.xcodeproj

# Build via CLI
xcodebuild -scheme ShouDeng -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

### Backend

```bash
cd shoudeng-backend/functions
npm install
npm run build          # TypeScript compilation
npm run serve          # Start Firebase emulators
```

#### App Store subscriptions (functions/.env)

| Variable | Value |
|---|---|
| `APPLE_APP_ID` | **Required for release.** Numeric Apple ID from App Store Connect → App Information. Not committed — set it in `shoudeng-backend/functions/.env` and redeploy. |
| `APPLE_ALLOW_SANDBOX` | Optional, default `true`. Sandbox purchases (TestFlight, App Review) keep working. |

Signed transactions are verified with Apple's root certificates (`functions/certs/`), Production
first and Sandbox as the fallback. Configure App Store Server Notifications **V2** in App Store
Connect (App Information → App Store Server Notifications) with the same URL for Production and
Sandbox: `https://us-central1-sweethome-b4e82.cloudfunctions.net/api/v1/payment/apple-webhook`.
Each purchase carries an `appAccountToken` (UUID v5 of the user id); one App Store subscription
unlocks exactly one account (`apple_subscription_owners/{originalTransactionId}`).

Products (docs/pricing/PRICING.md): single / family × monthly, yearly (auto-renewing, one
subscription group) and lifetime (`com.shoudeng.app.{single,family}.lifetime`, non-consumable,
stored as `subscriptions/{uid}.lifetime`; the better of subscription and lifetime applies).
`ultimate` products still resolve but are no longer sold in the app (organisation plan, contact us).

SOS SMS fallback and voice escalation are on every plan, free included, within fair use: 50 SMS
and 30 call minutes per protected person per calendar month (UTC, `sos_usage/{uid}_{YYYY-MM}`,
`services/fairUse.ts`). Beyond that, escalation continues by push only; the SOS is never blocked
and texts to emergency contacts (when there are no guardians) are always sent.

Emulators run on:
- Functions: `localhost:5001`
- Firestore: `localhost:8080`
- Auth: `localhost:9099`
- Emulator UI: `localhost:4000`

### Dev Bypass

`devBypassLogin = true` in `AppCoordinator.swift` allows skipping authentication during development. This creates a local-only user session without hitting the backend auth flow.

## Production Readiness Notes

### Completed
- Firestore security rules with field validation and owner-scoping
- SOS function timeout configured (300s) to support full 4-hop escalation
- Invite acceptance wrapped in Firestore transaction (race condition fix)
- SOS delivery failure feedback shown to user
- Error handling for account deletion and data export
- All CRUD operations connected to server APIs

### Remaining Before Submission
- [ ] Apple Critical Alerts entitlement (requires Apple approval)
- [ ] Complete app icon set (all required sizes)
- [ ] Launch screen configuration
- [ ] Create StoreKit subscription products in App Store Connect
- [ ] App Check / reCAPTCHA for bot protection
- [ ] Accessibility labels and Dynamic Type support
- [ ] Localization pipeline (hardcoded Chinese strings → NSLocalizedString)
- [ ] Unit and integration tests
- [ ] CI/CD pipeline (fastlane / GitHub Actions)

## Changelog

| Commit | Description |
|--------|-------------|
| `208c8d6` | Dual-role Live Activity cards — Guardian sees persons, Protected sees guardians |
| `08c2619` | Enable Live Activities + fix simulator debug for lock screen cards |
| `8bebe8e` | Lock screen widgets + backend security hardening |
| `ecef8fe` | Production hardening: security rules, API gaps, error handling |
| `9afe690` | Data sync consistency between guardian and protected views |
| `6dfd91e` | Import emergency contacts from device address book |
| `2ccac3a` | Emergency contacts tab in protected person records |
| `bb92518` | Enhanced protected person home screen |
| `a58b893` | Interactive map — tap family cards to focus on their location |
| `85a7aba` | MapKit location card on both home screens |
| `1ee5700` | Emergency alert system technical architecture |
| `92fd486` | v0.5.0: Profile system, avatar propagation, role UX redesign |
| `83a3510` | v0.4.0: Subscriptions, family feed, records hub, emergency contacts |
| `52bebf4` | Auth flow, role-based routing, backend emulator support |
| `bb888d5` | Auth, persistence, networking, navigation infrastructure |
| `c591627` | Copy and algorithms aligned to spec |
| `652afac` | Disclaimer/warning popup system (4-layer compliance) |
| `761accb` | Initial commit: 12 screens across 2 portals |

## License

Proprietary. All rights reserved.
