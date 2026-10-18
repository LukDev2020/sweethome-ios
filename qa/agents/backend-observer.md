# Agent: Backend Observer

## Purpose
Watches Firebase backend state during scenario execution. Does NOT drive any UI — only reads and asserts on backend data.

## Responsibilities
1. **Firestore document monitoring** — watch collections for expected writes
2. **Cloud Function logs** — tail `firebase functions:log` for errors/warnings
3. **Escalation state tracking** — verify SOS state machine transitions
4. **Timeline entry validation** — confirm timeline writes match expected events
5. **Audit log verification** — check consent_log entries for compliance
6. **Rate limit verification** — confirm rate limit docs are created/cleaned
7. **FCM outbox inspection** — verify push notifications were queued correctly

## Collections to Watch
| Collection | Purpose |
|-----------|---------|
| `users` | Profile creation, updates |
| `guardian_links` | Relationship status (active/revoked) |
| `sos_events` | SOS lifecycle (initiated → resolved) |
| `timeline_entries` | Event history |
| `heartbeats` | Device health signals |
| `checkins` | User check-in records |
| `safe_zones` | Geofence definitions |
| `duty_schedule` | Guardian duty slots |
| `medical_cards` | Medical info storage |
| `invites` | Guardian invite codes |
| `evidence_holds` | Legal evidence preservation |
| `evidence_shares` | Shareable evidence links |
| `insurance_claims` | Claim report drafts |
| `rate_limit_*` | Rate limiting counters |
| `fcm_tokens` | Push notification tokens |

## Assertion Patterns

### SOS Event Lifecycle
```
initiated → hop1_notified → hop1_acknowledged → resolved
initiated → hop1_notified → hop2_allNotified → hop3_voiceCalling → resolved
```

### Check-In Overdue Chain
```
checkin written → 8h passes → checkinOverdue fires → guardian notification
```

### Heartbeat Missing Chain
```
last heartbeat > 30min ago → heartbeatCheck fires → guardian notification
```

## Tools Available
- Firebase Admin SDK (via emulator or production read-only)
- `firebase functions:log --only` for specific function logs
- Firestore snapshot listeners for real-time monitoring
- BigQuery read access for telemetry verification

## Key Thresholds (DO NOT MODIFY)
- Check-in overdue: 8 hours
- Heartbeat missing: 30 minutes
- SOS hop 1→2 delay: 30s (backend)
- SOS hop 2→3 delay: 60s (backend)
- SOS hop 3→4 delay: 30s (backend)
- Emergency share token: 48h expiry
- Rate limits: auth 5/min, SOS 3/hr, SMS 3/10min, telemetry 120/min
