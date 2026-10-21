# Release 1.0 NA — Submission Checklist

## Task Status

| # | Task | Status | Evidence |
|---|------|--------|----------|
| 1 | Payment solution | PASS | StoreKit 2 auto-renewable subscriptions integrated (StoreKitManager.swift). 3 tiers: single/family/ultimate, monthly/yearly. Backend verification via /v1/payment/verify-receipt. Free tier allows 1 protected person. |
| 2 | Background location justification | PASS | All 3 locales rewritten (InfoPlist.strings en/fr/zh-Hans). Consent flow: 3 onboarding screens + per-feature disclosure + consent logged. UIBackgroundModes: location + remote-notification only (fetch removed). |
| 3 | Emergency-service wording audit | PASS | See qa/release/wording-audit.md. DisclaimerCopy.swift bannedWords enforced. Onboarding screen 1 states "not an emergency service" in all 3 languages. Store description uses "notification tool" wording. |
| 4 | Privacy manifest + policy | PASS | PrivacyInfo.xcprivacy: 10 data types, 2 API categories. privacy-policy.md draft in en/fr/zh-Hans. Account deletion in Settings. Crash data not linked to user. |
| 5 | Review demo accounts | PASS | See qa/release/review-notes.md "Demo" section. Two sandbox accounts with fixed OTP, pre-populated data. |
| 6 | Export compliance | PASS | ITSAppUsesNonExemptEncryption = NO. HTTPS/TLS only, no custom crypto. See review-notes.md. |
| 7 | Age rating + reference disclaimers | PASS | 4+ rating. "For reference only" disclaimer on MedicalCardView and ConsulateView in all 3 locales. Consular numbers verified against official sources. |
| 8 | Alerts and entitlements | PASS | No Critical Alerts entitlement. Time-sensitive interruption level for SOS. Entitlements: aps-environment, associated-domains, application-groups only. |
| 9 | Build and metadata | PASS | Build 16 (1.0.0). No QA_HARNESS in Release config. localhost/emulator URLs gated by #if DEBUG. App Store metadata in qa/release/metadata/ for en-CA, fr-CA, zh-Hans. |

## Top 3 Likely Reviewer Questions

### Q1: "Why does the app need Always location access?"
**Prepared answer:** Luma is a passive family safety monitoring app. Always-on location is required for two core functions: (1) reporting the user's position to their chosen family members during an SOS emergency, even when the app is backgrounded or the screen is locked; (2) geofencing for safe-zone entry/exit notifications. Location sharing begins only after the user completes a 3-screen onboarding disclosure and accepts an in-app consent prompt. If the user downgrades to "While In Use," the app displays a degradation alert and continues to function with reduced capability. The user can disable location sharing entirely at any time.

### Q2: "The app mentions emergency/SOS — is this an emergency service?"
**Prepared answer:** No. Luma is a notification tool that alerts the user's chosen family members. It does not replace emergency services (911/112). This is clearly stated in: (1) Onboarding screen 1: "Luma is not an emergency service" (shown before any feature is accessible, acknowledgment required); (2) The SOS trigger screen: "If the situation is dangerous, also call 112"; (3) The App Store description: "Luma notifies your family — it does not dispatch responders." The disclaimer is presented in all 3 supported languages and consent is logged with copy version.

### Q3: "Does the app track users or share data with third parties for advertising?"
**Prepared answer:** No. NSPrivacyTracking = false. No tracking domains. Data is shared only with: (1) family members the user explicitly chooses (location, name, safety status); (2) Firebase/Google Cloud for server-side processing (encrypted at rest and in transit); (3) Twilio for SMS/voice call delivery during SOS escalation. No data is sold, shared for advertising, or used for profiling. The privacy manifest (PrivacyInfo.xcprivacy) and App Store privacy labels accurately reflect all data collection.

## Files Modified/Created

### Modified
- ShouDeng/Info.plist — usage strings, background modes
- ShouDeng/en.lproj/InfoPlist.strings — rewritten usage strings
- ShouDeng/fr.lproj/InfoPlist.strings — rewritten usage strings
- ShouDeng/zh-Hans.lproj/InfoPlist.strings — rewritten usage strings
- ShouDeng/PrivacyInfo.xcprivacy — added crash data type, comments
- ShouDeng/en.lproj/Localizable.strings — reference disclaimer keys
- ShouDeng/fr.lproj/Localizable.strings — reference disclaimer keys
- ShouDeng/zh-Hans.lproj/Localizable.strings — reference disclaimer keys
- ShouDeng/Views/Shared/MedicalCardView.swift — reference disclaimer footer
- ShouDeng/Views/Shared/ConsulateView.swift — reference disclaimer footer

### Created
- qa/release/review-notes.md — reviewer notes (location, demo, export, age rating)
- qa/release/app-privacy-labels.md — privacy label cross-reference
- qa/release/metadata/en-CA.md — store copy English
- qa/release/metadata/fr-CA.md — store copy French
- qa/release/metadata/zh-Hans.md — store copy Chinese
- qa/release/submission-checklist.md — this file
- legal/privacy-policy.md — trilingual privacy policy draft
