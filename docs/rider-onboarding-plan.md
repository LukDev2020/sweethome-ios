# Rider onboarding: plan

Status: phases 1–3 built (2026-11-07). See "Built" at the end for what shipped and the operator steps left.

## Problem

Today a delivery rider who installs Lantern Care has to work out the route alone:

1. Sign in with phone and SMS code.
2. At "Choose your role", pick **Protected Person**. The description mentions seniors, students and travellers, never riders.
3. Go through the general wizard: email → city → Face ID → payment → invite family.
4. Discover **Settings → Home screen → Rider**, three levels deep.
5. Land on a rider home with no crew, no watcher and no lock-screen card. Nothing has explained why those matter.

Most riders will never find Rider mode, and the ones who do will start a shift with nobody watching.

Bug found while checking this:

- The shift state (`rider_shift` in UserDefaults) is shared between Explore Mode and the real app.
- A demo shift leaked into real storage and showed "On shift 8:53" with crew (0).
- The home style is also kept only on the phone, so it is lost on a new phone or after a reinstall.

## Principles

- **Rider is a use case, not a role.** In the data model a rider stays a protected person, with a home style and a rider profile. No third role and no migration; guardians, SOS and fall detection all keep working.
- **Ask what brings them here, in their own words.** "I deliver or drive for work", not "Protected Person".
- **Get safety in place before they work, and nothing else.** The rider flow is 60–90 s. Email, Face ID and plan details can wait for Settings.
- **The first shift is the activation moment.** Success means the first shift has at least one crew mate and one person at home watching, plus the lock-screen card.
- **Riders recruit riders.** A crew invite link is the main way in, so it has to land the new rider straight in the right flow.

## 1. Entry points

| Entry | Change |
|---|---|
| Sign-in page | **No change.** One phone field stays the clearest start. "Try a demo first" already includes Kai, the rider. |
| Role screen after the SMS code | Becomes **"Who is this phone for?"** with three cards (below). |
| Crew invite link / QR | `https://…/crew/ABC123` or `lanterncare://crew/ABC123`. Before sign-in: open the app → sign in → Rider is pre-selected and the crew code pre-filled. After sign-in: join directly. This is the main growth loop. |
| Partner link (platform, union, rider community) | `…/start?for=rider&org=…`. Rider pre-selected; `org` is kept for the free-plan check. |
| Existing users | Settings → Home screen → Rider now opens the same rider setup when it isn't finished, instead of only switching tabs. |
| Gentle suggestion (phase 3) | On-device only: after several long cycling or driving sessions in the evening, show one suggestion card: "Riding for work? Rider mode adds a crew that hears your SOS first." It's dismissible and never asked again. |

### "Who is this phone for?"

```
┌──────────────────────────────────────────┐
│  Who is this phone for?                  │
│                                          │
│  🛡  Me — so my family knows I'm safe     │
│      Living alone, studying abroad,      │
│      travelling                          │
│                                          │
│  🚲  Me — I deliver or drive for work     │  ← new
│      Shifts, a crew of riders who look   │
│      out for each other, SOS for the     │
│      street                              │
│                                          │
│  👁  Someone I look after                 │
│      Get their safety signals and help   │
│      remotely                            │
└──────────────────────────────────────────┘
```

The first two cards map to role `protected`. The rider card also sets home style `rider` and starts the rider setup.

## 2. Rider setup (replaces the general wizard for riders)

Each screen has one job and one big button. Every screen except the last can be skipped with "Later". A progress bar shows "3 of 6".

| # | Screen | Why it matters | Notes |
|---|---|---|---|
| R1 | **Where do you ride?** City (auto from location / country code) + platform chips: Uber Eats, DoorDash, Deliveroo, Menulog, Meituan, Ele.me, Uber, DiDi, Other | Local emergency number, caution spots, free-plan check | Chips, no typing |
| R2 | **Your crew**: join with a code or QR · start a crew (share the link to the group chat) · later | Crew mates nearby are alerted first, often a minute away | Pre-filled when they came from an invite link |
| R3 | **Someone at home**: invite one person by link, or pick from contacts | Each shift needs ≥ 1 crew mate + ≥ 1 family watcher (the shift-watcher rule) | Uses the existing invite flow |
| R4 | **SOS without looking**: lock-screen rider card (one tap) · Action button / Siri shortcut · handlebar Bluetooth button (optional) | Gloves, a bike, no time to unlock | Shows the card preview from the mock |
| R5 | **Permissions in rider words**: location "Always" ("so your crew sees you while you're on shift — never off shift") · notifications + Critical Alerts ("when a mate nearby needs help") · motion ("crash and fall detection") | iOS asks once; the reason must be clear the first time | Each asked just before it's explained, never all at once |
| R6 | **Your plan**: Rider Free if eligible, otherwise trial / paid | No payment wall before safety | Eligibility can come from the platform chips or the org link; proof can be requested later |
| R7 | **Ready**: a checklist ✓ crew · ✓ watcher · ✓ lock-screen card · then **Start your first shift** or **Not working now** | The activation moment | Rider home afterwards |

Once, at R2 or R7, the rider agrees to the rider duty notice:

- crew mates are volunteers, not emergency responders;
- in danger, call 000 / 110 / 911 first.

Logged with ConsentLogger like the guardian duty notice.

Email, Face ID and the family invite from the general wizard move to an **"Finish setting up" card** on the rider home (checklist, 4 of 7 done). Nothing is lost; it's just later.

## 3. Rider home when setup isn't finished

- The shift card shows who will be watching: "Watching this shift: Wei (crew) · Mum". Missing pieces appear as a tap-to-fix row: "No one at home is watching — add someone".
- Starting a shift with no watcher at all still works, but shows one clear warning, not a block. A rider must never be stopped from working.

## 4. Data and backend

- `users/{uid}`:
  - `useCase: "rider" | "personal" | "guardian"`;
  - `homeStyle`, saved on the server so it survives a reinstall or new phone;
  - `riderProfile { city, platforms[], org?, onboardedAt, freePlan: { eligible, reason } }`.
- `PUT /v1/user/me` accepts `homeStyle`, `useCase`, `riderProfile`, with validated values only.
- Crew invite universal links: an apple-app-site-association entry for `/crew/*` and a small web fallback page with App Store links. The deep-link router stores a pending crew code through sign-in.
- **Fix:** `rider_shift` moves behind the same demo / real storage split as LocalStore, so Explore Mode never reads or writes it, and a stale shift past its end is cleared or offered to end. Add `rider_shift` to ExploreModeTests' byte-identical storage check.
- Funnel events (no personal data, respects analytics consent): `intent_selected`, `rider_setup_step_n`, `crew_joined`, `watcher_added`, `lock_card_enabled`, `first_shift_started`.

## 5. Phases

**Phase 1 — sign-up path (≈ 2 days)**
- The rider-shift storage leak fix; home style saved on the server.
- "Who is this phone for?" with the rider card.
- Rider setup R2, R3, R4, R5 and R7; existing users get the same setup from Settings.
- The rider duty notice.
- Strings in all 5 languages.
- Tests: the flow, storage isolation, the server fields.

**Phase 2 — growth loop (≈ 2 days)**
- Crew invite universal links + QR + web fallback.
- Platform chips and free-plan eligibility (R1 + R6).
- Partner links.
- The "Finish setting up" checklist card.
- Funnel events.

**Phase 3**
- A guardian who also rides (dual roles, docs/roles/ROLES.md phase B: "I also ride").
- The on-device cycling suggestion.
- Organisation dashboards for partners.

## 6. How we'll know it works

| Metric | Target |
|---|---|
| Riders who reach the rider home after choosing the rider card | ≥ 90 % |
| Riders whose first shift has ≥ 1 crew mate **and** ≥ 1 family watcher, within 7 days | ≥ 50 % |
| Lock-screen card on within the first shift | ≥ 60 % |
| Median rider setup time | ≤ 90 s |
| New riders arriving through a crew invite (by month 2) | ≥ 30 % |

## Built (2026-11-07)

| Plan item | Where |
|---|---|
| Shift state isolated from Explore Mode | `AppCoordinator` (riderShift read/written only for the real account); `RiderOnboardingTests.testDemoNeitherReadsNorWritesTheRealShift` |
| "I deliver or drive for work" at sign-up | `SignupView` (rider card → protected role + Rider mode + rider setup instead of the general wizard) |
| Rider setup R1–R7 | `RiderSetupView` (also from Settings → Home screen → Rider, links, the home card) |
| Rider notice (consent v1.0, logged) | `DisclaimerCopy.RiderDuty`, `ConsentLogger.logRiderDuty` |
| Home style / use case / rider profile on the server | `PUT/GET /v1/user/me` (`useCase`, `homeStyle`, `riderProfile`), `services/riderProfile.ts` |
| Milestones (crew, first shift, lock card, setup) | server sets crew / shift ones in `services/crew.ts`; phone reports lockCard / setupDone |
| Crew invite universal links + web fallback | QR is now `https://shoudeng.app/crew/CODE`; AASA `/crew/*`, `/start*`; `web/crew.html`, `web/start.html` |
| Partner links + free-plan status | `/start?for=rider&org=CODE`; `POST /v1/org/partner-code`, `GET /v1/org/partner/:code`, `POST …/join {shareStats}`, `GET /v1/org/riders` (totals only); `riderFree` in the profile |
| Partner dashboard | `OrgRidersPanel` in the organisation dashboard |
| "Finish setting up" card, forgotten-shift prompt | `RiderHomeView` |
| Login banner for link arrivals | `LoginView.riderLinkBanner` |
| Funnel | `npm run rider-funnel [days]` (counts only) |
| On-device "Riding for work?" suggestion | `RiderSuggestion` (CMMotionActivity, never uploaded), `RiderSuggestionCard` |

Not built: the dual-role "I also ride" for guardians (needs roles phase B, docs/roles/ROLES.md); a guardian opening a crew link is told the link is for the rider.

### Operator steps left
1. Deploy functions (the new routes): `firebase deploy --only functions`.
2. Deploy Hosting so the universal links and fallback pages exist: `firebase deploy --only hosting` (serves `web/apple-app-site-association` with `/crew/*` and `/start`).
3. Put the App Store URL into `APP_STORE_URL` in `web/crew.html` and `web/start.html` once the app is live.
4. Index: `users` on `riderProfile.onboardedAt` is single-field (automatic) — no composite index needed.

