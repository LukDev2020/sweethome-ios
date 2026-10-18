# Chen Family (陈家) — Persona-Driven Test Suite Report

**Branch**: `qa/family-chen`
**Date**: 2026-10-17
**Family**: Chen Family (陈家) — 3 members, cross-border Toronto/Shenzhen

---

## Family Members

| Persona | Name | Role | Device | Locale | Location |
|---------|------|------|--------|--------|----------|
| haozi | 陈浩 (Chen Hao) | Protected | iPhone 14 | en-CA | Toronto, CA |
| father | 陈建国 (Chen Jianguo) | Guardian (primary) | iPhone 12 | zh-Hans | Shenzhen, CN |
| mother | 李敏 (Li Min) | Guardian (secondary) | iPhone SE | zh-Hans | Shenzhen, CN |

## Scenario Results

| # | Scenario | Status | Assertions | Screenshots | Notes |
|---|----------|--------|------------|-------------|-------|
| S1 | Onboarding | PENDING | 7 | 8 | 3 disclaimers, phone verify, role, invite |
| S2 | Normal Day | PENDING | 6 | 6 | Safe zone enter/exit, heartbeat, check-in |
| S3 | Missed Check-In | PENDING | 4 | 4 | 8h threshold, guardian notification |
| S4 | SOS Full Escalation | PENDING | 11 | 5 | 4-hop chain, voice call, resolution |
| S5 | Fall Detection | PENDING | 6 | 5 | 4-stage pipeline, 60s confirmation |
| S6 | Battery Death | PENDING | 6 | 6 | 30min offline threshold, 9h gap, recovery |
| S7 | Trajectory Consent | PENDING | 5 | 6 | Grant/revoke, JSONL logging, high sensitivity |
| S8 | Subscription Upgrade | PENDING | 2 | 6 | StoreKit sandbox, TTL change 7d→90d |
| S9 | Accessibility | PENDING | 3 | 7 | iPhone SE + xxLarge + VoiceOver |
| S10 | Insurance Claim | PENDING | 3 | 6 | Evidence hold, photo attach, claim draft |
| S11 | Cross-Border | PENDING | 8 | 7 | cn-lossy network, zh-CN geocoding, +86 SMS |
| S12 | Leave Family | PENDING | 3 | 7 | Guardian revocation, access denied |

**Total**: 12 scenarios, 64 backend assertions, 73 planned screenshots

## Timing Constants Reference

| Constant | Value | Source |
|----------|-------|--------|
| Check-in overdue | 8h | checkinOverdue.ts |
| Heartbeat missing | 30min | heartbeatCheck.ts |
| SOS hop 1→2 delay | 30s | onSOSCreated.ts |
| SOS hop 2→3 delay | 60s | onSOSCreated.ts |
| SOS hop 3→4 delay | 30s | onSOSCreated.ts |
| Hop 1 base wait (iOS) | 180s | EscalationEngine.swift |
| Hop 1 night wait (iOS) | 90s | EscalationEngine.swift |
| Hop 2 wait (iOS) | 120s | EscalationEngine.swift |
| Fall confirmation | 60s | FallDetector.swift |
| Free-fall threshold | 0.6g | FallDetector.swift |
| Impact threshold | 2.5g | FallDetector.swift |
| Orientation change | 60 deg | FallDetector.swift |
| Stillness duration | 15s | FallDetector.swift |
| Max heartbeats/hr | 12 | HeartbeatService.swift |
| Min heartbeat interval | 60s | HeartbeatService.swift |
| Battery report threshold | 5% | HeartbeatService.swift |
| SOS rate limit | 3/hr | rateLimit.ts |
| Emergency share expiry | 48h | onSOSCreated.ts |

## Agents

| Agent | File | Purpose |
|-------|------|---------|
| persona-haozi | `qa/agents/persona-haozi.md` | Protected person iOS driver (en-CA, iPhone 14) |
| persona-father | `qa/agents/persona-father.md` | Guardian iOS driver (zh-Hans, iPhone 12, cn-lossy) |
| persona-mother | `qa/agents/persona-mother.md` | Guardian iOS driver (zh-Hans, iPhone SE, xxLarge, VoiceOver) |
| backend-observer | `qa/agents/backend-observer.md` | Firestore/functions log watcher |
| scenario-director | `qa/agents/scenario-director.md` | Orchestrator for all 12 scenarios |

## Seed Data

| Item | Count | Details |
|------|-------|---------|
| Check-ins | 30 | 27 on-time, 2 late, 1 missed (Oct 3) |
| Heartbeats | 720 | ~24/day for 30 days |
| Location points | ~600 | Weekday commute patterns |
| Safe zone events | ~120 | Enter/exit for 4 zones |
| Degradation events | 3 | Notifications off (Oct 6), battery death (Oct 11), LPM (Oct 8-10) |
| SOS drills | 1 | Oct 9, acknowledged by father in 41s |
| Claims | 1 | Oct 12 draft with 2 photos |
| Audit records | 10+ | Consent grants, onboarding screens |
| Subscription | 1 | Family plan, Sep 1 – Nov 1 |

## Known Findings (from backend QA)

| ID | Severity | Description | Impact on Chen Scenarios |
|----|----------|-------------|-------------------------|
| F-001 | Medium | FCM notifications Chinese-only | Father OK (zh-Hans), haozi sees Chinese notifications |
| F-002 | Medium | SMS templates Chinese-only | Both guardians in CN, acceptable |
| F-003 | Low | TwiML language based on protected, not guardian | Both in CN, same language |
| F-011 | Medium | No China SMS gateway for +86 | S11 validates Twilio-only path |
| F-012 | Low | Geocoding hardcoded zh-CN | S11 validates Chinese address output |
| F-014 | Deferred | No PIPL data residency | Current version targets non-CN market |

## File Inventory

```
qa/
  personas/
    chen-family.json          # Family persona definition
  seed-chen.ts                # 30-day seed data generator
  flows/chen/
    S01_onboarding.yaml       # Maestro flow
    S02_normal_day.yaml
    S03_missed_checkin.yaml
    S04_sos_full_escalation.yaml
    S05_fall_detection.yaml
    S06_battery_death.yaml
    S07_trajectory_consent.yaml
    S08_subscription_upgrade.yaml
    S09_accessibility.yaml
    S10_insurance_claim.yaml
    S11_cross_border.yaml
    S12_leave_family.yaml
    chen-scenarios.test.ts    # Backend assertions (Jest)
  reports/chen/
    summary.md                # This file
qa/agents/
    persona-haozi.md
    persona-father.md
    persona-mother.md
    backend-observer.md
    scenario-director.md
```

## Next Steps
1. Run `chen-scenarios.test.ts` to validate backend assertions pass
2. Boot simulators (iPhone 14 + iPhone 12 + iPhone SE)
3. Seed Firebase emulator with `seed-chen.ts`
4. Execute Maestro flows S1–S12
5. Capture screenshots and fill in results table
6. Update this report with pass/fail status
