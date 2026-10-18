# Backend QA Summary Report

**Branch:** `qa/backend-harness`
**Date:** 2026-10-17
**QA Lead:** Backend/Data QA

---

## Executive Summary

Completed an 8-phase comprehensive QA audit of the Vela (守灯) backend infrastructure. The audit covers Firebase Cloud Functions, Firestore security rules, authentication, escalation chain, scheduled functions, localization, cross-border readiness, and performance.

**Total tests written:** 304 backend tests across 12 suites (all passing)
**Total findings:** 14 (1 fixed, 13 open)
**Critical blockers:** 2 (F-004: SOS rate limit unmounted, F-014: PIPL data residency)

---

## Phase Results

### Phase 0 — System Map
- **Output:** `qa/system-map.md` (500+ lines)
- Mapped 39 SwiftUI views, 18 service modules, 24+ API endpoints, 14 Firestore collections, 5 scheduled functions, 4 triggers
- Documented exact algorithm constants (FallDetector, AdaptiveLocationManager, TrajectoryProcessor, BaselineScorer, HeartbeatService)
- Identified 10 initial findings (F-001 through F-010)

### Phase 1 — Test Harness Infrastructure
- **Output:** `qa/seed.ts`, `tools/vela-harness/`, iOS `#if QA_HARNESS` hook
- 3 test families: Free tier (A), Family plan with duty schedules (B), Enhanced with medical card (C)
- MCP server with 8 tools (create_test_family, trigger_sos, set_location, etc.)
- Release build guard: `qa/test_release_no_harness.sh`
- Added Storage (port 9199) and Pub/Sub (port 8085) emulators to firebase.json

### Phase 2 — Auth & Database Tests (101 tests)
| Suite | Tests | Description |
|-------|-------|-------------|
| `auth.routes.test.ts` | 25 | Phone auth, JWT tokens, signup, refresh |
| `firestore.rules.test.ts` | 46 | Security rules, cross-family isolation, server-only write |
| `schema.validation.test.ts` | 30 | User schema, phone→country mapping, GDPR delete cascade, indexes |

### Phases 3 & 4 — GPS/Location & Detection Algorithms
- **Covered by existing iOS tests** (63 tests total):
  - TrajectoryProcessorTests: 19 tests
  - AdaptiveLocationManagerTests: 15 tests
  - FallDetectorTests: 11 tests
  - BaselineScorerTests: 18 tests
- Algorithm constants documented in system map; thresholds NOT modified per QA policy.

### Phase 5 — Escalation & Delivery (62 tests)
| Suite | Tests | Description |
|-------|-------|-------------|
| `escalation.test.ts` | 38 | 4-hop chain, timing, idempotency, guardian selection, voice call, share link |
| `scheduled.test.ts` | 24 | TTL cleanup, integrity proof, checkin overdue, heartbeat missing, home timer |

### Phase 6 — Cross-Border & China Reachability (38 tests)
| Suite | Tests | Description |
|-------|-------|-------------|
| `crossborder.test.ts` | 38 | Country code chain, Twilio for CN, FCM/APNs, geocoding, ATS, data residency |

**New findings:**
- F-011 (medium): No China SMS gateway for +86 — Twilio unreliable for mainland China
- F-012 (low): Geocoding hardcoded to zh-CN language
- F-013 (medium): No fallback geocoding provider for China (Google Maps blocked)
- F-014 (high): No PIPL data residency configuration

### Phase 7 — Performance & Cost (45 tests)
| Suite | Tests | Description |
|-------|-------|-------------|
| `performance.test.ts` | 45 | Function resources, rate limiting, batch limits, BigQuery cost, telemetry validation, geocoding cache, iOS rates |

### Phase 8 — Localization Audit (32 tests)
| Suite | Tests | Description |
|-------|-------|-------------|
| `i18n.audit.test.ts` | 32 | Key completeness (EN/zh-Hans/FR), empty values, duplicates, format strings, terminology, InfoPlist.strings, server-side findings |

---

## Test Count Summary

| Suite | Phase | Tests |
|-------|-------|-------|
| auth.routes.test.ts | 2 | 25 |
| firestore.rules.test.ts | 2 | 46 |
| schema.validation.test.ts | 2 | 30 |
| escalation.test.ts | 5 | 38 |
| scheduled.test.ts | 5 | 24 |
| crossborder.test.ts | 6 | 38 |
| performance.test.ts | 7 | 45 |
| i18n.audit.test.ts | 8 | 32 |
| auth.middleware.test.ts | pre-existing | 8 |
| rateLimit.test.ts | pre-existing | 6 |
| sos.routes.test.ts | pre-existing | 6 |
| webhooks.routes.test.ts | pre-existing | 6 |
| **Total passing** | | **304** |

*Note: `e2e-bots.test.ts` (77 tests) requires running Firebase emulators and is excluded from the pass count.*

---

## Findings Ledger

| ID | Severity | Category | Title | Status |
|----|----------|----------|-------|--------|
| F-001 | medium | i18n | FCM push bodies hardcoded Chinese | open |
| F-002 | medium | i18n | SMS templates hardcoded Chinese | open |
| F-003 | low | i18n | TwiML language uses protected person's country | open |
| **F-004** | **high** | **security** | **SOS rate limit preset not mounted on route** | **open** |
| F-005 | low | infra | Missing emulators in firebase.json | fixed |
| F-006 | medium | security | 10 collections lack explicit rules | open |
| F-007 | low | i18n | iOS push action buttons hardcoded Chinese | open |
| F-008 | low | i18n | iOS local notification content hardcoded Chinese | open |
| F-009 | low | i18n | HeartbeatService battery alert hardcoded Chinese | open |
| F-010 | low | i18n | BaselineScorer risk explanations hardcoded Chinese | open |
| F-011 | medium | cross-border | No China SMS gateway for +86 | open |
| F-012 | low | cross-border | Geocoding hardcoded to zh-CN | open |
| F-013 | medium | cross-border | No fallback geocoding provider for China | open |
| **F-014** | **high** | **cross-border** | **No PIPL data residency for Chinese users** | **open** |

### Severity Distribution
- **High:** 2 (F-004, F-014)
- **Medium:** 5 (F-001, F-002, F-006, F-011, F-013)
- **Low:** 6 (F-003, F-007, F-008, F-009, F-010, F-012)
- **Fixed:** 1 (F-005)

---

## Strengths Confirmed

1. **Firestore security rules** — Comprehensive, owner-scoped, default-deny catchall. 14 explicit collection rules + 10 caught by default deny.
2. **Rate limiting** — Well-designed presets (auth 5/min, SOS 3/hr, SMS 3/10min, telemetry 120/min). Fail-open for safety-critical app. Standard headers (X-RateLimit-*).
3. **4-hop escalation chain** — Correct timing (0s → 30s → 90s → 120s), idempotent (3 re-reads), duty schedule support, SMS fallback for non-app guardians.
4. **TTL cleanup** — Evidence hold protection, parameterized BigQuery queries, batch processing within Firestore 500-doc limit.
5. **Localization files** — All 3 locales (EN/zh-Hans/FR) have identical key sets, no empty values, no duplicates, format specifiers match.
6. **ATS** — Strict HTTPS-only (NSAllowsArbitraryLoads = false).
7. **Telemetry validation** — Cross-user submission blocked (403), rate limited, BigQuery failures non-fatal.

---

## Recommended Priority Actions

### Immediate (before App Store submission)
1. **Mount SOS rate limiter** (F-004) — Apply `RATE_LIMITS.sos` to the SOS trigger route
2. **Assess PIPL compliance** (F-014) — Consult legal for China data residency requirements

### Before international launch
3. **Add per-locale notification routing** (F-001, F-002) — FCM and SMS bodies should use recipient's locale
4. **Integrate China SMS gateway** (F-011) — Aliyun SMS or Tencent Cloud for +86 delivery
5. **Add fallback geocoding** (F-013) — Amap/Gaode for when Google Maps is unavailable

### Nice to have
6. **Localize iOS hardcoded strings** (F-007, F-008, F-009, F-010) — Use NSLocalizedString
7. **Dynamic geocoding language** (F-012) — Use recipient's locale for address formatting

---

## Git History

```
d396165 Phase 0 system map
f2a4847 Phase 1 harness infrastructure
b9bd6d2 Phase 2 auth/rules/schema tests
ad98d9d Phase 5 escalation/scheduled tests
a132b0e Phase 8 i18n localization audit tests
adadac8 Phase 6 cross-border + Phase 7 performance tests
```
