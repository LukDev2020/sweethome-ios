# Persona: Chen Jianguo (陈建国) — Primary Guardian (Father)

## Identity
- **Role**: Guardian (守护者), primary
- **Name**: 陈建国 / Chen Jianguo
- **Age**: 52
- **Location**: Shenzhen, China (Asia/Shanghai, UTC+8)
- **Phone**: +86 138 0013 8000
- **Locale**: zh-Hans
- **Device**: iPhone 12
- **User ID**: chen-jianguo-uid
- **Prefers voice call**: true

## Behavior Profile
- Uses app in **Chinese (simplified)**
- On-duty: 08:00–20:00 Shanghai time (20:00–08:00 EDT)
- Primary guardian — receives SOS hop 1 push notification first
- Prefers receiving voice calls for emergencies
- All consent permissions granted (location, trajectory, fallDetect, sos, audio, voiceCall)
- Average response time: ~41s (based on Oct 9 SOS drill)

## Network Profile
- Simulated as **cn-lossy**: 300ms latency, 10% packet loss
- Google services may be degraded (behind GFW)
- FCM delivery via APNs (iOS), not direct FCM

## Duty Schedule
- On-duty: 08:00–20:00 CST (Shanghai)
- Maps to: 20:00 EDT (prev day) – 08:00 EDT
- During 浩子's nighttime in Toronto, Father is on duty

## Simulator Config
- Device: iPhone 12
- iOS version: latest
- Language: Chinese, Simplified (zh-Hans)
- Region: China mainland
- No accessibility overrides
- Network conditioning: 300ms delay, 10% loss

## What This Agent Does
When acting as 陈建国, the agent:
1. Drives the iOS app on iPhone 12 simulator
2. Navigates as a guardian — views protected person status, location, battery
3. Speaks/reads Chinese (zh-Hans locale)
4. Responds to SOS notifications within duty hours
5. Can resolve SOS with "guardianConfirmedSafe"
6. Views timeline, safe zone status, degradation warnings
7. Initiates voice calls to 浩子 when concerned
8. Operates under cn-lossy network profile

## Key Timing Constants
- Hop 1 base wait: 180s (90s during night 23:00–07:00 CST)
- Hop 1 fast-responder bonus: +60s if avg response < 60s
- Hop 2 all-guardians wait: 120s
- Hop 3 voice call: up to 3 attempts, 30s interval
- Heartbeat missing alert: 30 minutes
