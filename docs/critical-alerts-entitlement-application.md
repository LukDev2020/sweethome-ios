# Critical Alerts Entitlement Application

> Submit at: https://developer.apple.com/contact/request/notifications-critical-alerts-entitlement/
>
> Apple typically responds within 2-4 weeks.

---

## Application Fields

### App Name
守灯 ShouDeng

### App Store URL / Bundle ID
com.shoudeng.app (not yet published — requesting for initial submission)

### Describe your app

ShouDeng is a family safety guardian app designed for elderly parents, solo travelers, and other vulnerable individuals. It enables designated family guardians to monitor the safety of their loved ones through real-time location sharing, fall detection, and a multi-hop emergency escalation system.

### Why does your app need Critical Alerts?

ShouDeng's core value proposition is ensuring that emergency SOS alerts reach guardians immediately, even when:

1. **The guardian's device is in Do Not Disturb or Sleep Focus mode** — Emergencies cannot wait until morning. If an elderly parent falls at 2 AM and their adult child's phone is in sleep mode, the alert must break through.

2. **The guardian has notification volume turned down** — Critical Alerts play at system volume regardless of the ringer switch position, ensuring audibility.

3. **The alert is automatically triggered by fall detection** — When the protected person is unconscious after a fall and cannot manually call for help, the system automatically escalates through a 3-hop chain (push → SMS → voice call). The initial push notification MUST be a Critical Alert to maximize the chance of immediate response.

### Specific use cases for Critical Alerts

1. **SOS Emergency**: The protected person long-presses the SOS button (3 seconds) to trigger an emergency. A Critical Alert is sent to the on-duty guardian with the person's real-time GPS location, battery level, and trigger method.

2. **Automatic Fall Detection**: The app's 4-stage fall detection algorithm (free-fall → impact → orientation change → prolonged stillness) detects a potential fall. If the user does not respond within 60 seconds, the system automatically triggers SOS and sends a Critical Alert.

3. **Escalation Chain**: If the first guardian does not acknowledge within the dynamic wait period (90-180 seconds depending on time of day), Critical Alerts are sent to ALL guardians simultaneously.

### What information is displayed in the Critical Alert?

- Name of the protected person who triggered SOS
- Trigger method (manual, fall detection, duress password)
- Current location (address or coordinates)
- Battery level of the protected person's device
- Action buttons: "I've taken over" (freezes the escalation chain) and "Call now"

### How do you ensure Critical Alerts are not abused?

1. **Rate limiting**: SOS can be triggered at most 3 times per hour per user (enforced server-side).
2. **User-initiated only**: Critical Alerts are sent only upon explicit SOS trigger or confirmed fall detection (4-stage algorithm with 60-second user confirmation window).
3. **No marketing or promotional use**: Critical Alerts are exclusively used for genuine safety emergencies.
4. **Escalation freeze**: Any guardian can immediately stop further alerts by tapping "I've taken over."

### Relevant App Store category
Health & Fitness / Medical (or Utilities / Safety)

---

## Implementation Details (for Apple's reference)

- **Framework**: `UserNotifications` with `UNNotificationInterruptionLevel.critical`
- **Sound**: System critical alert sound at system volume
- **Entitlement**: `com.apple.developer.usernotifications.critical-alerts`
- **Code location**: `ShouDeng/Services/Push/PushService.swift` — `fireCriticalSOSAlert()` method
- **Permission request**: Requested alongside `.alert`, `.sound`, `.badge` during onboarding, with clear explanation of why Critical Alerts are needed

---

## Supporting Materials

If Apple requests additional documentation, prepare:

1. **App demo video** showing the SOS trigger → Critical Alert → Guardian response flow
2. **Fall detection demo** showing the 4-stage algorithm and automatic escalation
3. **Screenshot** of the Critical Alert notification on a locked device in DND mode
4. **Architecture diagram** showing the 3-hop escalation chain
