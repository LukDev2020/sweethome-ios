# ShouDeng Iteration Plan — Front + Backend
## Prototype-to-Production Gap Analysis & Roadmap
### Date: 2026-10-26 | Current Build: 22 (1.0.0)

---

## Current State Summary

| Area | Status | Detail |
|------|--------|--------|
| **iOS Views** | 50 SwiftUI files | 41 views + 9 components, both roles complete |
| **Services** | 32 service modules | Auth, BLE, audio, crypto, location, push, payment |
| **Backend Routes** | 70+ endpoints | 20 route files, full CRUD for all entities |
| **Widgets** | 6 widgets + 2 Live Activities | Status, timer, SOS, Dynamic Island |
| **Localization** | 3 languages x 954 strings | EN, zh-Hans, FR |
| **Tests** | 202 iOS + 328 backend | 14 iOS test files, 13 backend suites |
| **Subscriptions** | 6 StoreKit products configured | 3 tiers x monthly/yearly |

---

## GAP ANALYSIS: Prototype vs Real App

### Frontend Gaps (13 items)

| # | Feature | Prototype | Real App | Priority |
|---|---------|-----------|----------|----------|
| F1 | Floating SOS FAB | Always visible, pulsing | Long-press buried in layout | P0 |
| F2 | "I'm Home Safe" button | Compact pill below cards | Generic check-in exists | P1 |
| F3 | Battery on guardian cards | Inline % + bar on home | Only in detail/alert views | P1 |
| F4 | Distance/ETA chips | "10,900 km away" | Not shown | P2 |
| F5 | Tab notification badges | Red dots with count | None | P1 |
| F6 | Chat reactions | Thumbs/heart/clap buttons | Edit/delete/reply only | P2 |
| F7 | Slide-to-SOS lock screen | Draggable slider widget | SOS widget exists (tap only) | P2 |
| F8 | Dark mode toggle | Light/Dark/Auto in settings | System-follows only | P3 |
| F9 | Language/font quick pills | Home screen pills | Settings only | P3 |
| F10 | Enhanced profile card | Photo, role badge, medical summary | Basic avatar + name | P2 |
| F11 | Weather/AQI cards | Full weather + forecast + AQI bar | Not present | P2 |
| F12 | Emergency Yellow Pages | 8-country selector with numbers | ConsulateView partial | P2 |
| F13 | Location sharing card | Map preview card in chat | Not in family feed | P2 |

### Backend Gaps (10 items)

| # | Feature | Needed For | Current State | Priority |
|---|---------|-----------|---------------|----------|
| B1 | Real-time battery endpoint | F3 (battery on cards) | BigQuery heartbeat only | P1 |
| B2 | Badge count endpoint | F5 (tab badges) | Not implemented | P1 |
| B3 | Chat reactions CRUD | F6 (reactions) | No reaction model | P2 |
| B4 | Weather/AQI proxy | F11 (weather cards) | Not implemented | P2 |
| B5 | Nearby places search | Coverage clinic cards | Not implemented | P2 |
| B6 | Location share card | F13 (share in chat) | Evidence share only | P2 |
| B7 | Widget data endpoint | Lock screen widgets | Full auth required | P1 |
| B8 | User preferences sync | F8, F9 (dark mode, font) | No pref fields | P3 |
| B9 | Distance calculation | F4 (distance chips) | Not implemented | P2 |
| B10 | Quick safe endpoint | F2 ("Home Safe") | Generic checkin works | P3 |

---

## ITERATION PHASES

---

### PHASE 1: Safety-Critical UX (Sprint 1 — ~3 days)
> Goal: Make SOS always reachable, surface battery warnings, add notification badges

#### Frontend (iOS)

**F1. Floating SOS FAB** — `ProtectedHomeView.swift` + `ProtectedTabView.swift`
- Add persistent `ZStack` overlay with 56pt red circular button
- Position: bottom-right, above tab bar (96pt from bottom, 20pt from right)
- Pulsing shadow animation (matching prototype `fabPulse`)
- Long-press (1.5s) to activate → reuse existing SOS trigger logic
- Show on ALL tabs via `ProtectedTabView` overlay
- Files: `ProtectedTabView.swift`, new `FloatingSOSButton.swift`

**F3. Battery on Guardian Home Cards** — `GuardianHomeView.swift`
- Add battery % + bar to `person-card` rows on guardian home
- Color-coded: green (>50%), amber (20-50%), red pulsing (<20%)
- Pull from `AppCoordinator.protectedPersons[].batteryLevel`
- Add `BatteryIndicator` SwiftUI component (bar + percentage text)
- Files: `GuardianHomeView.swift`, new `BatteryIndicatorView.swift`

**F5. Tab Notification Badges** — `ProtectedTabView.swift`, `GuardianTabView.swift`
- Add `.badge()` modifier to tab items
- Guardian Home: count of overdue check-ins + active SOS
- Guardian Family: unread post count
- Protected Family: unread message count
- Source: computed from `AppCoordinator` state
- Files: `ProtectedTabView.swift`, `GuardianTabView.swift`

#### Backend

**B1. Real-time Battery Endpoint** — `routes/telemetry.ts`
- Modify `POST /v1/heartbeat` to write `lastBatteryLevel` + `lastBatteryTimestamp` to Firestore `users/{uid}` doc (not just BigQuery)
- Modify `GET /v1/guardian/protected-persons` to include `batteryLevel`, `batteryTimestamp`, `isCharging` in response
- Add Firestore field: `users/{uid}.lastBatteryLevel: number`, `users/{uid}.lastBatteryAt: Timestamp`
- Files: `routes/telemetry.ts`, `routes/guardian.ts`

**B2. Badge Count Endpoint** — new `routes/badges.ts`
- `GET /v1/badges` → returns `{ overdueCheckins: number, activeSOS: number, unreadPosts: number }`
- Guardian: count overdue check-ins across all protected persons, active SOS events, posts since last read
- Protected: count unread family posts
- Add Firestore field: `users/{uid}.lastFeedReadAt: Timestamp`
- Files: new `routes/badges.ts`, update `routes/index.ts`

**B7. Widget Data Endpoint** — new `routes/widget.ts`
- `GET /v1/widget/data` — lightweight response for WidgetKit timeline
- Returns: persons' status, battery %, last check-in, active SOS, duty schedule
- Authentication: App Group shared token (not full JWT flow)
- Files: new `routes/widget.ts`, update `routes/index.ts`

#### Tests
- Unit test: `FloatingSOSButton` tap/long-press behavior
- Unit test: `BatteryIndicatorView` color thresholds
- Backend: badge count with 0/1/many overdue check-ins
- Backend: heartbeat writes battery to Firestore

---

### PHASE 2: Communication & Social (Sprint 2 — ~3 days)
> Goal: Enrich family feed with reactions, location sharing, and "I'm Home Safe"

#### Frontend (iOS)

**F2. "I'm Home Safe" Pill** — `ProtectedHomeView.swift`
- Add compact pill button below card deck (centered row with globe + Aa pills if F9 done)
- Green gradient, house icon + "Home Safe" text
- Tap → animate checkmark, call existing `POST /v1/checkin` with note "home_safe"
- Auto-dismiss confirmation after 4s
- Files: `ProtectedHomeView.swift`, new `HomeSafePill.swift`

**F6. Chat Reactions** — `FamilyFeedView.swift`
- Add reaction bar below each message: thumbs-up, heart, clap
- Tap to toggle reaction (fill/unfill)
- Show reaction counts next to emoji
- Long-press message → reaction picker overlay
- Files: `FamilyFeedView.swift`, new `ReactionBarView.swift`

**F13. Location Sharing Card** — `FamilyFeedView.swift`
- Add "Share Location" button at top of family feed
- Creates a special post type with embedded map preview
- Card shows: address, coordinates, mini MapKit snapshot, live pulse dot
- Tapping card opens full LocationCardView
- Files: `FamilyFeedView.swift`, new `LocationShareCardView.swift`

#### Backend

**B3. Chat Reactions CRUD** — `routes/family.ts`
- New Firestore subcollection: `family_posts/{postId}/reactions/{reactorId}`
- Schema: `{ emoji: string, userId: string, createdAt: Timestamp }`
- `POST /v1/family/posts/:postId/reactions` — add/toggle reaction
- `DELETE /v1/family/posts/:postId/reactions` — remove reaction
- Modify `GET /v1/family/posts` — include `reactions` summary per post
- Update Firestore rules: reaction write allowed if authenticated family member
- Files: `routes/family.ts`, `firestore.rules`

**B6. Location Share Card** — `routes/family.ts`
- Allow `POST /v1/family/posts` to accept `type: "location_share"` with lat/lng/address
- Return location metadata in `GET /v1/family/posts` for rendering
- Auto-expire location shares after configurable duration (default 1hr)
- Files: `routes/family.ts`

#### Tests
- Unit test: reaction toggle visual state
- Unit test: location card renders map snapshot
- Backend: create/toggle/remove reaction
- Backend: create location share post, verify auto-expiry

---

### PHASE 3: Coverage & Information (Sprint 3 — ~3 days)
> Goal: Add weather, AQI, nearby medical, and Yellow Pages to coverage tab

#### Frontend (iOS)

**F11. Weather/AQI Cards** — `ProtectedCoverageView.swift`
- Weather card: temp, icon, description, wind/humidity/UV, 5-day forecast row
- AQI card: color-coded bar (green→red gradient), marker dot, health advice
- Fetch from backend proxy on tab appear
- Cache results for 30 min
- Files: `ProtectedCoverageView.swift`, new `WeatherCardView.swift`, `AQICardView.swift`

**F12. Emergency Yellow Pages** — new `EmergencyYellowPagesView.swift`
- Country selector dropdown (8 countries: CA, CN, JP, US, UK, AU, FR, DE)
- Per-country cards: police, fire, ambulance, Chinese embassy, poison control, crisis line
- Merge with existing `ConsulateView` data + extend
- Add to Records tab for BOTH roles (below timeline)
- Files: new `EmergencyYellowPagesView.swift`, `ProtectedRecordsView.swift`, `GuardianRecordsView.swift`

**Nearby Medical Clinics** — `ProtectedCoverageView.swift`
- Hospital/clinic/pharmacy cards with name, address, distance, open status
- Use MapKit local search or backend proxy
- Show 3 nearest results per category
- Files: `ProtectedCoverageView.swift`, new `NearbyMedicalView.swift`

#### Backend

**B4. Weather/AQI Proxy** — new `routes/coverage.ts`
- `GET /v1/coverage/weather?lat=X&lng=Y` — proxy to OpenWeatherMap API (free tier)
- `GET /v1/coverage/aqi?lat=X&lng=Y` — proxy to WAQI API
- Cache responses in Firestore for 30 min per location grid cell (rounded to 0.1 deg)
- Rate limit: 60/min per user
- Files: new `routes/coverage.ts`, update `routes/index.ts`
- Env vars: `OPENWEATHER_API_KEY`, `WAQI_API_KEY`

**B5. Nearby Places Search** — new `routes/coverage.ts`
- `GET /v1/coverage/nearby?lat=X&lng=Y&type=hospital|pharmacy|police`
- Proxy to Google Places API (or Apple MapKit Server API)
- Return top 5 results with name, address, distance, open_now
- Cache for 1hr per grid cell + type
- Env var: `GOOGLE_PLACES_API_KEY`

#### Tests
- Unit test: weather card renders forecast
- Unit test: AQI bar marker position
- Backend: weather proxy with cache hit/miss
- Backend: nearby search returns sorted by distance

---

### PHASE 4: Enhanced UX Polish (Sprint 4 — ~2 days)
> Goal: Distance chips, improved profile, slide-to-SOS, dark mode

#### Frontend (iOS)

**F4. Distance/ETA Chips** — `GuardianHomeView.swift`, `ProtectedHomeView.swift`
- Calculate great-circle distance between coordinates (Haversine formula)
- Show as "10,900 km" chip below location text
- If < 50km: show drive time estimate (distance / 40 km/h)
- Client-side calculation — no backend needed
- Files: `GuardianHomeView.swift`, `ProtectedHomeView.swift`, new `DistanceChip.swift`

**F10. Enhanced Profile Card** — `ProtectedSettingsView.swift`, `GuardianSettingsView.swift`
- Avatar with camera overlay (tap to change photo)
- Role badge pill ("Protected Person" / "Guardian") with role color
- Inline medical summary row (blood type | allergy | ICE contact)
- "Edit" button aligned right
- Files: `ProtectedSettingsView.swift`, `GuardianSettingsView.swift`, new `ProfileHeaderView.swift`

**F7. Slide-to-SOS on Lock Screen** — `ProtectedLiveActivity.swift`
- Replace static SOS button with slide-to-activate gesture
- Use SwiftUI `DragGesture` on SOS thumb within track
- Trigger at 75% threshold → fire `SOSIntent`
- Auto-reset after 2.5s if activated
- Note: Live Activities have limited interactivity — may need to keep as deep-link button
- Files: `ShouDengWidgets/ProtectedLiveActivity.swift`

**F8. Dark Mode Toggle** — `ProtectedSettingsView.swift`, `GuardianSettingsView.swift`
- Segmented picker: Light / Dark / Auto
- Store in `@AppStorage("appearanceMode")`
- Apply via `.preferredColorScheme()` on RootView
- Files: `RootView.swift`, `ProtectedSettingsView.swift`, `GuardianSettingsView.swift`

**F9. Language/Font Quick Pills** — `ProtectedHomeView.swift`
- Row of 3 pills below card deck: Home Safe | EN/中文/FR | Aa S/M/L
- Language pill cycles through LanguageManager options
- Font pill cycles through FontScaleManager levels
- Files: `ProtectedHomeView.swift`, new `QuickPillRow.swift`

#### Backend

**B8. User Preferences Sync** — `routes/user.ts`
- Extend `PUT /v1/user/me` to accept `preferences` object
- Schema: `{ darkMode: "light"|"dark"|"auto", fontSize: "S"|"M"|"L"|"XL", language: "en"|"zh"|"fr" }`
- Store in `users/{uid}.preferences`
- Sync on app launch → apply stored values
- Files: `routes/user.ts`

**B9. Distance Calculation** — `routes/guardian.ts`
- Add `distanceKm` field to `GET /v1/guardian/protected-persons` response
- Calculate Haversine distance between guardian's last known location and each person
- Requires guardian location (from heartbeat) — include only if guardian has shared location
- Files: `routes/guardian.ts`

#### Tests
- Unit test: Haversine distance calculation accuracy
- Unit test: dark mode toggle persists across launch
- Unit test: profile header renders medical summary
- Backend: preferences round-trip save/load

---

### PHASE 5: Quality & Production Hardening (Sprint 5 — ~3 days)
> Goal: Test coverage, performance, accessibility, App Store readiness

#### Frontend

**Accessibility Pass**
- All interactive elements: minimum 44x44pt touch targets
- VoiceOver labels on SOS button, battery indicator, reaction buttons
- Dynamic Type support verification on all new views
- Color contrast check (WCAG AA) on all new components
- Files: all new views from Phases 1-4

**Performance Optimization**
- Lazy load weather/AQI data (only when Coverage tab selected)
- Debounce badge count polling (max 1 request per 30s)
- Cache Yellow Pages data locally (offline access)
- Map snapshot generation: use `MKMapSnapshotter` instead of live MapView for feed cards
- Reduce globe `requestAnimationFrame` when not visible (power saving)

**Missing Test Coverage**
- 20 untested iOS services need unit tests (target: 80% coverage)
- New views need snapshot tests
- Integration tests for widget → main app data flow
- E2E test: SOS from floating FAB → guardian notification → resolve

#### Backend

**Security Hardening**
- Validate all new endpoints have rate limits
- Weather/AQI proxy: API key rotation support
- Widget endpoint: validate App Group token securely
- Chat reactions: prevent reaction spam (max 1 per emoji per user per post)

**Performance**
- Badge count: use Firestore aggregation queries (COUNT) instead of fetching all docs
- Weather cache: TTL-based cleanup (scheduled function)
- Nearby places: result caching with geo-hash bucketing

**Monitoring**
- Add Cloud Monitoring alerts for new endpoints
- Track weather/places API quota usage
- Dashboard for badge count query latency

#### App Store Preparation
- Screenshot generation for all new features (6.7" + 6.1" + iPad)
- Update App Store description with new features
- Update privacy nutrition labels (weather data = coarse location usage)
- Verify Critical Alerts entitlement for SOS FAB

---

## TIMELINE SUMMARY

| Phase | Focus | Duration | Dependencies |
|-------|-------|----------|-------------|
| **Phase 1** | Safety-Critical UX | 3 days | None — start immediately |
| **Phase 2** | Communication & Social | 3 days | B1 from Phase 1 |
| **Phase 3** | Coverage & Information | 3 days | API keys (OpenWeather, Google Places) |
| **Phase 4** | Enhanced UX Polish | 2 days | None — parallel with Phase 3 |
| **Phase 5** | Quality & Hardening | 3 days | Phases 1-4 complete |
| **Total** | | **~14 days** (2 sprints) | |

---

## PRIORITY MATRIX

```
                    HIGH IMPACT
                        |
         P0: F1(SOS)    |    P1: F3(Battery), F5(Badges)
         B7(Widget)     |    B1(Battery EP), B2(Badge EP)
                        |
   LOW EFFORT ----------+---------- HIGH EFFORT
                        |
         P3: F8(Dark)   |    P2: F6(Reactions), F11(Weather)
         F9(Pills)      |    F12(YellowPages), F13(LocShare)
         B8(Prefs)      |    B3(Reactions), B4(Weather)
                        |
                    LOW IMPACT
```

---

## FILE CHANGE MAP

### New Files to Create (13)

| File | Phase | Purpose |
|------|-------|---------|
| `Views/Shared/FloatingSOSButton.swift` | 1 | Persistent SOS FAB component |
| `Views/Shared/BatteryIndicatorView.swift` | 1 | Battery % bar component |
| `Views/Shared/HomeSafePill.swift` | 2 | "I'm Home Safe" compact button |
| `Views/Shared/ReactionBarView.swift` | 2 | Emoji reaction row for chat |
| `Views/Shared/LocationShareCardView.swift` | 2 | Location card for family feed |
| `Views/Shared/WeatherCardView.swift` | 3 | Weather + forecast card |
| `Views/Shared/AQICardView.swift` | 3 | Air quality index card |
| `Views/Shared/NearbyMedicalView.swift` | 3 | Nearby clinic/pharmacy list |
| `Views/Shared/EmergencyYellowPagesView.swift` | 3 | Country-selector emergency directory |
| `Views/Shared/DistanceChip.swift` | 4 | Distance pill component |
| `Views/Shared/ProfileHeaderView.swift` | 4 | Enhanced profile with photo + badge |
| `Views/Shared/QuickPillRow.swift` | 4 | Home screen quick action pills |
| `backend: routes/coverage.ts` | 3 | Weather/AQI/nearby proxy |
| `backend: routes/badges.ts` | 1 | Notification badge counts |
| `backend: routes/widget.ts` | 1 | Widget data endpoint |

### Existing Files to Modify (18)

| File | Phase | Changes |
|------|-------|---------|
| `ProtectedTabView.swift` | 1 | Add FloatingSOSButton overlay, badge modifiers |
| `GuardianTabView.swift` | 1 | Badge modifiers on tabs |
| `GuardianHomeView.swift` | 1,4 | Battery indicator, distance chips |
| `ProtectedHomeView.swift` | 2,4 | HomeSafePill, QuickPillRow, distance chips |
| `FamilyFeedView.swift` | 2 | ReactionBar, LocationShareCard, share button |
| `ProtectedCoverageView.swift` | 3 | WeatherCard, AQI, NearbyMedical sections |
| `ProtectedRecordsView.swift` | 3 | Emergency Yellow Pages section |
| `GuardianRecordsView.swift` | 3 | Emergency Yellow Pages section |
| `ProtectedSettingsView.swift` | 4 | ProfileHeader, dark mode toggle |
| `GuardianSettingsView.swift` | 4 | ProfileHeader, dark mode toggle |
| `RootView.swift` | 4 | `.preferredColorScheme()` from AppStorage |
| `ProtectedLiveActivity.swift` | 4 | Slide-to-SOS (if feasible) |
| `AppCoordinator.swift` | 1,2 | Badge state, battery tracking |
| `APIEndpoints.swift` | 1,2,3 | New endpoint definitions |
| `backend: routes/telemetry.ts` | 1 | Write battery to Firestore |
| `backend: routes/guardian.ts` | 1,4 | Include battery + distance in response |
| `backend: routes/family.ts` | 2 | Reactions + location share post type |
| `backend: routes/index.ts` | 1,2,3 | Register new routes |

---

## RISK REGISTER

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Weather API rate limits | Coverage tab broken | Cache aggressively (30min), show cached data if quota hit |
| Live Activity slide gesture limitations | F7 impossible | Fall back to deep-link button (current approach) |
| Badge count query cost at scale | Firestore reads spike | Use aggregation queries, poll max 1/30s |
| Google Places API cost | Budget overrun | Cache 1hr, limit to 5 results, consider MapKit Server API (free) |
| Dark mode breaks existing views | Visual regressions | Incremental rollout, test all 50 views |

---

## DEFINITION OF DONE

Each phase is complete when:
1. All listed features compile with 0 errors, 0 warnings
2. New unit tests pass (min 2 tests per new component)
3. Existing 202 iOS + 328 backend tests still pass
4. Features work in both EN and zh-Hans
5. VoiceOver reads all new interactive elements
6. TestFlight build uploaded and smoke-tested on physical device
