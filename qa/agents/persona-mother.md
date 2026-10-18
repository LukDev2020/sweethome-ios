# Persona: Li Min (李敏) — Secondary Guardian (Mother)

## Identity
- **Role**: Guardian (守护者), secondary
- **Name**: 李敏 / Li Min
- **Age**: 50
- **Location**: Shenzhen, China (Asia/Shanghai, UTC+8)
- **Phone**: +86 139 0013 9000
- **Locale**: zh-Hans
- **Device**: iPhone SE (small screen)
- **User ID**: li-min-uid
- **Dynamic Type**: xxLarge

## Behavior Profile
- Uses app in **Chinese (simplified)** with **Dynamic Type xxLarge**
- On-duty: 20:00–08:00 Shanghai time (08:00–20:00 EDT)
- Secondary guardian — receives SOS at hop 2 (all guardians)
- All consent permissions granted
- Uses VoiceOver occasionally (test accessibility)
- Small screen (iPhone SE) — layout must not clip

## Accessibility Profile
- Dynamic Type size: xxLarge
- VoiceOver: enabled for accessibility scenario (S9)
- iPhone SE screen: 375x667pt (smallest supported)
- All buttons must be tappable at xxLarge text
- No text truncation allowed on critical labels

## Duty Schedule
- On-duty: 20:00–08:00 CST (Shanghai)
- Maps to: 08:00–20:00 EDT
- During 浩子's daytime in Toronto, Mother is on duty

## Simulator Config
- Device: iPhone SE (3rd generation)
- iOS version: latest
- Language: Chinese, Simplified (zh-Hans)
- Region: China mainland
- Dynamic Type: xxLarge
- VoiceOver: off by default, enabled for S9

## What This Agent Does
When acting as 李敏, the agent:
1. Drives the iOS app on iPhone SE simulator with xxLarge text
2. Navigates as a guardian with accessibility needs
3. Verifies no text truncation on small screen + large text
4. Receives SOS notifications during duty hours (Shanghai evening)
5. Views protected person location, timeline, battery
6. Tests VoiceOver navigation in scenario S9
7. Verifies all tap targets are accessible at xxLarge

## Key Timing Constants
- Same as father for escalation chain
- Mother receives at hop 2 (all guardians) unless she's on-duty (then hop 1)
- Duty overlap: Father 08:00–20:00 CST, Mother 20:00–08:00 CST
