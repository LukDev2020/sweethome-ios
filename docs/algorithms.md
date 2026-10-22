# ShouDeng Algorithm Documentation

> Reference document for algorithm verification (T-algo gate).
> Every number in this document must match the source code exactly.
> Last updated: 2026-10-20

---

## Table of Contents

1. [Fall Detector](#1-fall-detector)
2. [Trajectory Processor](#2-trajectory-processor)
3. [Adaptive Location Manager](#3-adaptive-location-manager)
4. [Baseline Scorer (Missing Person Detection)](#4-baseline-scorer)
5. [Escalation Engine](#5-escalation-engine)

---

## 1. Fall Detector

**Source**: `ShouDeng/Core/Algorithms/FallDetector.swift`

### 1.1 Purpose

Detects potential falls using a four-stage sequential pipeline on accelerometer data from CoreMotion. All four stages must fire in sequence. If all pass, a 60-second on-device confirmation dialog appears. If the user does not dismiss it, the system escalates to SOS.

### 1.2 Pipeline Stages (Ordered)

| Stage | Name | Condition | Transition on Fail |
|-------|------|-----------|-------------------|
| 1 | Free-fall | SVM drops below threshold for minimum duration | Stay in monitoring |
| 2 | Impact | SVM spikes above threshold within window after free-fall end | Reset to monitoring |
| 3 | Orientation Change | Gravity vector rotates more than threshold degrees | Reset to monitoring |
| 4 | Prolonged Stillness | SVM variance stays below threshold for required duration | Reset to monitoring |

### 1.3 Thresholds and Constants

#### Default Profile (`youngAdult`)

| Parameter | Value | Unit |
|-----------|-------|------|
| `freeFallThresholdG` | 0.6 | g |
| `freeFallMinDurationMs` | 100 | ms |
| `impactThresholdG` | 2.5 | g |
| `impactWindowAfterFreeFallMs` | 500 | ms |
| `orientationChangeMinDegrees` | 60 | degrees |
| `orientationSampleWindowSec` | 2.0 | seconds |
| `stillnessMaxVariance` | 0.05 | g^2 |
| `stillnessDurationSec` | 15.0 | seconds |
| `confirmationTimeoutSec` | 60.0 | seconds |
| `sampleRateHz` | 50.0 | Hz |

#### Elderly Profile (`elderly`)

| Parameter | Value | Note |
|-----------|-------|------|
| `freeFallThresholdG` | 0.65 | Higher threshold (more sensitive) |
| `impactThresholdG` | 2.0 | Lower impact required |
| `orientationChangeMinDegrees` | 50 | Less rotation needed |
| `stillnessMaxVariance` | 0.06 | Slightly more movement tolerated |
| `stillnessDurationSec` | 10.0 | Shorter stillness window |

All other elderly values inherit from `youngAdult` defaults.

#### Phone-in-Pocket Profile (`phoneInPocket`)

| Parameter | Value | Note |
|-----------|-------|------|
| `impactThresholdG` | 3.0 | Higher to avoid false triggers from body cushioning |
| `orientationChangeMinDegrees` | 45 | Phone orientation shifts more in pocket |

All other pocket values inherit from `youngAdult` defaults.

### 1.4 State Machine

States: `monitoring`, `freeFallDetected(startTime)`, `impactDetected(impactTime)`, `orientationChanged(changeTime)`, `waitingStillness(since)`, `candidateFall(detectedAt)`, `confirmationPending(expiresAt)`, `confirmed`, `cancelled`

```
monitoring
    |-- SVM < freeFallThresholdG for freeFallMinDurationMs --> freeFallDetected
        |-- SVM > impactThresholdG within impactWindowAfterFreeFallMs --> impactDetected
        |   |-- after orientationSampleWindowSec, angle > orientationChangeMinDegrees --> orientationChanged
        |   |   |-- immediately --> waitingStillness
        |   |       |-- after stillnessDurationSec, variance < stillnessMaxVariance --> candidateFall
        |   |       |   |-- immediately --> confirmationPending(expiresAt = now + 60s)
        |   |       |       |-- user taps "I'm fine" --> cancelled
        |   |       |       |-- timeout (60s) --> confirmed --> escalate to SOS
        |   |       |-- variance > stillnessMaxVariance --> monitoring (person got up)
        |   |       |-- recent variance > stillnessMaxVariance * 3 --> monitoring (early exit)
        |   |-- angle <= orientationChangeMinDegrees --> monitoring
        |-- elapsed > impactWindowAfterFreeFallMs without impact --> monitoring
```

### 1.5 Edge Cases

- **Early exit from stillness**: If recent 2-second variance exceeds `stillnessMaxVariance * 3` (i.e., 0.15 for youngAdult), the detector resets to monitoring immediately without waiting for the full stillness duration.
- **Ring buffer capacity**: `sampleRateHz * 5 = 250` samples (5 seconds of data). Older samples are discarded.
- **Free-fall verification**: Requires `sampleRateHz * freeFallMinDurationMs / 1000` consecutive samples below threshold (i.e., 5 samples at 50 Hz over 100 ms).
- **Gravity capture**: Gravity vector is captured BEFORE the fall using a 2-second window average, then compared against post-impact gravity.
- **Terminal states**: `confirmed` and `cancelled` are terminal. Must call `reset()` to return to monitoring.

### 1.6 Tolerance Values for Verification

| Check | Expected | Tolerance |
|-------|----------|-----------|
| SVM computation | `sqrt(ax^2 + ay^2 + az^2)` | Exact (IEEE 754) |
| Angle computation | `acos(clamp(dot(normalize(a), normalize(b)), -1, 1)) * 180 / pi` | Exact |
| Variance computation | Sample variance (N-1 denominator) | Exact |
| Confirmation timeout | 60.0 seconds | 0 (exact) |

### 1.7 References

Threshold calibration references (from source comments):
- SisFall dataset
- UMAFall dataset
- FallAllD dataset

---

## 2. Trajectory Processor

**Source**: `ShouDeng/Core/Algorithms/TrajectoryProcessor.swift`

### 2.1 Purpose

Cleans raw GPS points through a four-layer pipeline: filter, smooth, simplify, segment. Real-time judgments use smoothed points; display uses simplified points.

### 2.2 Pipeline Stages (Ordered)

| Layer | Name | Purpose |
|-------|------|---------|
| 1 | Filter | Discard bad points (accuracy, speed, timestamp) |
| 2 | Kalman Smooth | 1D Kalman filter on lat/lng separately |
| 3 | Douglas-Peucker | Simplify point count for display (~80% reduction) |
| 4 | Segment | Classify dwell vs. movement, infer transport mode |

### 2.3 Thresholds and Constants

| Parameter | Value | Unit | Layer |
|-----------|-------|------|-------|
| `maxAccuracyMeters` | 100 | meters | 1 |
| `maxSpeedKmh` | 200 | km/h | 1 |
| `flyingSpeedKmh` | 1200 | km/h | 1 |
| `simplificationEpsilon` | 15 | meters | 3 |
| `dwellRadiusMeters` | 200 | meters | 4 |
| `dwellMinDurationSec` | 1200 | seconds (20 min) | 4 |
| `walkMaxKmh` | 5 | km/h | 4 |
| `bikeMaxKmh` | 20 | km/h | 4 |
| `carMaxKmh` | 120 | km/h | 4 |
| Earth radius (haversine) | 6371000.0 | meters | helper |

### 2.4 Layer 1: Filter Rules

Points are discarded if:
1. `accuracy > maxAccuracyMeters` (100m)
2. `timestamp <= previous accepted point's timestamp` (out of order)
3. Computed speed from previous accepted point `> flyingSpeedKmh` (1200 km/h, physically impossible)

Speed is computed as: `(haversine_distance / time_delta) * 3.6` to convert m/s to km/h.

### 2.5 Layer 2: Kalman Smooth

- 1D Kalman filter applied independently to latitude and longitude
- Initial variance: `accuracy^2` from first point
- Process noise: `dt * speed^2 * 1e-10` (velocity-based)
- Kalman gain: `variance / (variance + accuracy^2)`
- No matrix math required for 1D case

### 2.6 Layer 3: Douglas-Peucker Simplification

- Recursive algorithm with epsilon = 15 meters
- Perpendicular distance computed using dot-product projection onto line segment, clamped to [0, 1]
- Base case: 2 or fewer points returned as-is
- Used for display only; real-time judgments use smoothed (Layer 2) points

### 2.7 Layer 4: Segmentation

**Dwell detection**: Consecutive points within `dwellRadiusMeters` (200m) for at least `dwellMinDurationSec` (1200s = 20 min).

**Transport mode inference** (by average speed, no ML):

| Mode | Speed Range |
|------|------------|
| Walking (步行) | < 5 km/h |
| Cycling (骑行) | 5 - 20 km/h |
| Driving (车辆) | 20 - 120 km/h |
| Flying (飞行) | > 200 km/h (or > 120 km/h with no altitude data) |
| Stationary (停留) | Dwell segment |
| Unknown (未知) | 120 - 200 km/h with altitude data |

### 2.8 Edge Cases

- Empty input returns empty results at every layer
- Single-point input passes through filter and Kalman unchanged; Douglas-Peucker returns as-is; segmentation returns empty
- Speed computation guards against `timeDelta == 0` (skip division)
- Trailing dwell candidates are handled: if duration >= threshold, emitted as dwell; otherwise emitted as movement

---

## 3. Adaptive Location Manager

**Source**: `ShouDeng/Core/Algorithms/AdaptiveLocationManager.swift`

### 3.1 Purpose

Five-mode adaptive location sampling that switches automatically based on context (safe zone, movement, SOS, battery). Handles iOS 20-region geofence limit via dynamic swap scheduling and auto-discovers safe zones via dwell-point clustering.

### 3.2 Location Modes

| Mode | Accuracy | Distance Filter | Report Interval | Background Indicator |
|------|----------|----------------|-----------------|---------------------|
| `safe` | hundredMeters | none (significant changes) | infinity | false |
| `unknown` | hundredMeters | 50m | 600s (10 min) | false |
| `moving` | nearestTenMeters | 30m | 60s (1 min) | false |
| `sos` | best | none | 5s | true |
| `lowBattery` | hundredMeters | 100m | 1200s (20 min) | false |

### 3.3 Configuration Constants

| Parameter | Value | Unit |
|-----------|-------|------|
| `movingSpeedThreshold` | 1.5 | m/s |
| `stationarySpeedThreshold` | 0.5 | m/s |
| `deduplicationDistanceMeters` | 50 | meters |
| `deduplicationTimeSec` | 120 | seconds (2 min) |
| `maxGeofenceRegions` | 19 | count (reserve 1 of iOS's 20) |
| `dwellPointRadiusMeters` | 200 | meters |
| `dwellPointMinDurationSec` | 1200 | seconds (20 min) |
| `safeZoneHysteresisMeters` | 50 | meters |
| `lowBatteryThreshold` | 0.15 | ratio (15%) |
| `bufferZoneRadius` | 2000 | meters (2 km) |
| `historyLimit` | 500 | points |

### 3.4 Auto Mode Selection Logic

Priority order (highest first):
1. **SOS mode**: Never downgraded automatically. Only `exitSOSMode()` changes it.
2. **Low battery**: `batteryLevel <= 0.15` AND not charging AND not in SOS.
3. **Safe zone + stationary**: `speed < 0.5 m/s` AND inside any safe zone.
4. **Moving**: `speed > 1.5 m/s`.
5. **Unknown**: Not in safe zone and not moving fast enough.

### 3.5 Geofence Scheduling Algorithm (iOS 20-Region Limit)

1. Sort all safe zones by distance from current position
2. Take closest 19 zones (reserve 1 slot for buffer zone)
3. Register 2 km buffer zone around current position (exit-only notification)
4. Only rebalance when leaving the buffer zone (80% threshold: `distance > bufferZoneRadius * 0.8`)
5. On buffer zone exit, re-sort and re-register closest 19 zones

### 3.6 Deduplication Rules

Location reports are suppressed if ALL of the following are true:
- Distance moved from last report < 50m
- Time since last report < 120s

Exception: SOS mode always reports, bypassing deduplication.

Additionally, reports are suppressed if time since last report < current mode's `reportIntervalSec`.

### 3.7 Safe Zone Hysteresis

- **Enter**: Distance from zone center <= zone radius
- **Exit**: Distance from zone center > zone radius + 50m (hysteresis buffer)
- Prevents border flickering when user is near the edge of a safe zone

### 3.8 Dwell-Point Clustering

**Real-time tracking**: As location updates arrive, points within 200m of an existing candidate are merged. A dwell candidate is promoted when:
- Duration >= 1200s (20 min)
- Point count >= 3

**Classification rules**:

| Classification | Criteria |
|---------------|----------|
| Home (住所) | Nighttime dwell (hour >= 22 or hour <= 6) |
| Work/School (学校/工作地) | Weekday (Mon-Fri), hours 9-17, distance > 500m from home |
| Frequent (常去地点) | Visit count >= 2 |
| Unfamiliar (陌生地点) | Default (none of the above) |

**Batch clustering** (`clusterDwellPoints()`): Processes all history (up to 500 points), merges within 200m radius, requires >= 3 points and duration >= 1200s. Sorted by visit count descending.

**Stale candidate cleanup**: Candidates not seen for > 1 hour AND duration < 1200s are removed.

---

## 4. Baseline Scorer

**Source**: `ShouDeng/Core/Algorithms/BaselineScorer.swift`

### 4.1 Purpose

Builds a per-person behavioral baseline over 14+ days, then scores deviation from that baseline using 5 weighted, explainable factors. Avoids fixed thresholds that would generate false alarms for people with unusual routines (e.g., night-shift workers).

### 4.2 Configuration Constants

| Parameter | Value |
|-----------|-------|
| `baselineDaysRequired` | 14 |
| `baselineWindowDays` | 30 (rolling) |
| `yellowThreshold` | 0.45 |
| `redThreshold` | 0.70 |

### 4.3 Factor Weights

| Factor | Weight | Description |
|--------|--------|-------------|
| Check-in overtime | 0.35 | How late is the current check-in gap vs. personal history |
| Phone inactivity | 0.25 | How long since any phone activity vs. personal history |
| Location anomaly | 0.20 | How unusual is the current location for this time slot |
| Battery anomaly | 0.10 | Battery level concerns (< 10% unplugged = 0.9 deviation) |
| Regional risk | 0.10 | Server-provided regional risk level (0.0-1.0) |
| **Total** | **1.00** | |

### 4.4 Factor Computation Details

#### Factor 1: Check-in Overtime (weight 0.35)

- Deviation = `min(currentGap / longestHistoricalGap, 3.0) / 3.0`
- If no check-in ever: gap set to 48 hours (maximum concern)
- If no baseline: `min(gap / 24h, 1.0)`
- Contribution = `0.35 * deviation`

#### Factor 2: Phone Inactivity (weight 0.25)

- Deviation = `min(inactiveGap / longestInactivePeriod, 3.0) / 3.0`
- If no heartbeat ever: gap set to 24 hours
- If no baseline: `min(gap / 8h, 1.0)`
- Contribution = `0.25 * deviation`

#### Factor 3: Location Anomaly (weight 0.20)

- Location grid: lat/lng bucketed at `* 1000, rounded` (~111m precision)
- Base deviation = `1.0 - min(frequency * 5.0, 1.0)` (>20% historical visits = normal)
- Time-slot check: 6 slots (earlyMorning 05-08, morning 08-12, afternoon 12-17, evening 17-21, night 21-01, lateNight 01-05)
- If location never seen in current time slot AND deviation > 0.5: deviation scaled by 1.3x (capped at 1.0)
- Contribution = `0.20 * deviation`

#### Factor 4: Battery Anomaly (weight 0.10)

| Condition | Deviation |
|-----------|-----------|
| Battery < 10%, unplugged | 0.9 |
| Battery < 20%, unplugged | 0.5 |
| No battery data AND inactive > 4h | 0.7 |
| Otherwise | 0.0 |

Contribution = `0.10 * deviation`

#### Factor 5: Regional Risk (weight 0.10)

- Directly uses server-provided `regionRiskLevel` (0.0-1.0) as deviation
- Contribution = `0.10 * regionRiskLevel`

### 4.5 Score Computation

```
totalScore = min(sum(all factor contributions), 1.0)
```

| Score Range | Alert Level |
|-------------|-------------|
| < 0.45 | info |
| 0.45 - 0.70 | warning (yellow) |
| >= 0.70 | critical (red) |

### 4.6 Human-Readable Reasons

Only factors with `contribution > 0.05` are included in reasons. Sorted by contribution descending. Each factor has a pre-formatted Chinese explanation string.

### 4.7 Fallback (Insufficient Baseline Data)

When baseline has < 14 days of data, fixed thresholds are used:

| Condition | Score Addition |
|-----------|---------------|
| No check-in > 24h | +0.4 |
| No check-in 12-24h | +0.2 |
| Never checked in | +0.3 |
| Phone inactive > 8h | +0.2 |

A note is appended: "正在收集行为数据以建立个人基线，需14天"

### 4.8 Baseline Data Structure

- **Check-in patterns**: Hour-bucketed distribution (0-23), gap statistics (max, avg, stddev)
- **Phone activity**: Active hours set, average active periods/day, longest inactive period
- **Location grid**: `GridCell` at ~111m precision, frequency map (0-1), time-slot location lists
- **Battery**: Average battery at check-in, typical charging hours
- **Standard deviation**: Sample stddev (N-1 denominator)

---

## 5. Escalation Engine

**Source**: `ShouDeng/Core/StateMachine/EscalationEngine.swift`

### 5.1 Purpose

Multi-hop state machine that escalates SOS alerts through increasingly aggressive notification channels until a guardian acknowledges. Any guardian tapping "I've taken over" immediately freezes the entire chain.

### 5.2 State Machine

States: `idle`, `triggered`, `notifyingPrimary`, `notifyingAll`, `voiceCalling`, `acknowledged`, `exhausted`

```
idle --> triggered --> notifyingPrimary (Hop 1)
                         |-- guardian responds --> acknowledged
                         |-- timeout (dynamic) --> notifyingAll (Hop 2)
                                                      |-- guardian responds --> acknowledged
                                                      |-- timeout (120s) --> voiceCalling (Hop 3)
                                                                                |-- someone picks up --> acknowledged
                                                                                |-- all attempts fail --> exhausted
```

Any state can transition to `acknowledged` via `freeze(by:)`.

### 5.3 Hop Timers

| Hop | Base Wait | Night Wait | Conditions |
|-----|-----------|------------|------------|
| 1 (on-duty guardian) | 180s (3 min) | 90s (1.5 min) | Night = 23:00-07:00 in guardian's TZ |
| 2 (all guardians) | 120s (2 min) | 120s (same) | Simultaneous push + SMS |
| 3 (voice call) | `3 * 30s * numGuardians` | Same | Up to 3 attempts per person, 30s interval |

#### Hop 1 Dynamic Wait Computation

```
wait = isNight ? 90 : 180
if guardian.averageResponseTime < 60 && > 0:
    wait += 60   // fast responder bonus
wait = max(wait, 30)  // minimum 30 seconds
```

Night determination: `hour >= 23 || hour < 7` (wrapping logic in code handles start > end).

### 5.4 Notification Channels per Hop

| Hop | Push | SMS | Voice Call | Priority |
|-----|------|-----|------------|----------|
| 1 | Yes | No | No | Critical (bypasses DND) |
| 2 | Yes | Yes | No | Critical |
| 3 | No | No | Yes | N/A (phone call) |

### 5.5 Freeze Behavior

When any guardian calls `freeze(by: guardianId)`:
1. `session.isFrozen = true`
2. `session.state = .acknowledged`
3. All scheduled timers are invalidated
4. All other guardians in all hops are notified: "已有人接手"
5. No further hops are started

### 5.6 SOS Trigger Methods

The engine formats SOS notification bodies with the trigger method. Supported methods:
- `longPress` (手动触发)
- `watchQuickAction` (手表触发)
- `bluetoothButton` (按钮触发)
- `duressPassword` (胁迫密码触发)
- `fallDetection` (跌倒检测触发)
- `voiceWakeWord` (语音触发)

### 5.7 Notification Categories

| Category | Usage |
|----------|-------|
| `sosAlert` | Hop 1 and Hop 2 notifications |
| `escalationUpdate` | "Someone has taken over" freeze notification |
| `checkInReminder` | (Defined but not used in engine) |
| `anomalyWarning` | (Defined but not used in engine) |
| `responderDispatch` | (Defined but not used in engine) |

### 5.8 Edge Cases

- **No guardians**: If `allGuardians` is empty or no on-duty guardian exists, skips directly to Hop 3
- **No on-duty guardian**: Falls back to `allGuardians.first` for Hop 1
- **Already frozen**: All hop-start methods check `session.isFrozen` before proceeding
- **Already resolved**: Scheduled hop callbacks check both `isFrozen` and `isResolved`
- **Timer management**: Uses `Timer.scheduledTimer(withTimeInterval:repeats:false)`, all timers stored in array and invalidated on freeze/resolve
- **Retry config**: `maxRetryAttempts = 3`, `retryIntervalSec = 60` (available in config but hop-level retry logic is in voice call)
