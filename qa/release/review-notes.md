# App Store Review Notes — Luma (守灯) v1.0.0

## Background Location

### Why "Always" is required
Luma is a passive family safety monitoring app. The core value proposition depends on continuous location availability: if a user falls or triggers SOS, their family needs to see where they are — even if the app is in the background or the screen is locked. Safe-zone entry/exit monitoring (geofencing) also requires background location.

### What happens with "While In Use"
If the user downgrades to "While In Use":
- Location updates stop when the app is backgrounded
- Safe-zone geofencing ceases to function
- The app displays a **degradation alert** (yellow banner) explaining the reduced protection
- Guardians see the user's last known location with a stale timestamp
- SOS still works (foreground) but location may be outdated

### How to disable
- Settings > Privacy & Security > Location Services > Luma > Never
- In-app: Settings > toggle off location sharing (takes effect after 6-hour safety delay)
- The 6-hour delay is a duress protection feature — documented in onboarding disclaimer screen 3

### Consent flow
1. Onboarding screen 1: "Luma is not an emergency service" (must acknowledge)
2. Onboarding screen 2: "We only see what safety requires" (must acknowledge)
3. Onboarding screen 3: "You are in control" including 6-hour delay (must acknowledge)
4. In-app feature disclosure for Location (opt-in consent, logged with version)
5. Only then does the iOS system location prompt appear
6. All consent events are recorded in append-only JSONL log with copy version, locale, device ID

---

## Demo Accounts

### Credentials
| Role | Phone | OTP Code | Language |
|------|-------|----------|----------|
| Guardian (caregiver) | +1 416 555 0199 | 123456 | en-CA |
| Protected Person | +1 416 555 0198 | 123456 | en-CA |

These are sandbox accounts with fixed OTP codes enforced server-side. No real SMS is sent.

### Pre-populated data
- 7 days of location history in Toronto, ON
- 1 past SOS drill (resolved by guardian)
- 1 degradation alert (battery low)
- Medical card (blood type, allergies, medications)
- Claims draft document

### How to test the SOS flow
1. Log in as Protected Person (+1 416 555 0198, code 123456)
2. On the Home screen, long-press the SOS button for 3 seconds
3. SOS triggers — escalation chain begins
4. Log in as Guardian (+1 416 555 0199, code 123456) on a second device/simulator
5. Guardian receives push notification with SOS alert
6. Guardian taps "I've taken over" to resolve
7. Protected Person sees "Guardian has responded" notification

**No real emergency services are contacted.** The app notifies only the user's chosen family members.

### Voice calls for demo
All SMS and voice calls for the Review Family are routed to a Twilio test number. Push notifications are real (APNs).

---

## Export Compliance

**ITSAppUsesNonExemptEncryption = NO**

Reasoning:
- The app uses only standard iOS HTTPS/TLS for network communication
- Firebase SDK handles all encryption (standard TLS, no custom crypto)
- No CryptoKit, AES, or custom encryption algorithms in app code
- PDF generation in ClaimPDFGenerator uses standard iOS UIGraphics, not encryption
- No end-to-end encryption layer
- Falls under the HTTPS/TLS exemption — no self-classification report needed

---

## Age Rating

### Content descriptions
| Category | Answer | Notes |
|----------|--------|-------|
| Violence | None | SOS is a notification tool, no violent content |
| Sexual Content | None | |
| Profanity | None | |
| Drugs/Alcohol/Tobacco | None | |
| Gambling | None | |
| Horror/Fear | None | |
| Medical/Treatment Info | Infrequent/Mild | Medical card stores allergies, blood type, medications — reference only |
| Mature/Suggestive Themes | None | |
| Simulated Gambling | None | |
| Unrestricted Web Access | None | |
| User-Generated Content | None | Family-only content within guardianship relationships; no public UGC |
| Contests | None | |

**Recommended age rating: 4+** (medical info is reference-only, no treatment advice)

### Reference-only disclaimers
Medical card, first-aid info, and consular hotline numbers each display:
> "For reference only — verify with professionals / 仅供参考，请向专业人士确认 / A titre indicatif uniquement — verifiez aupres de professionnels"

### Consular number sources
| Country | Source | Verified |
|---------|--------|----------|
| Canada | travel.gc.ca/assistance/emergency-assistance | 2026-10-20 |
| USA | travel.state.gov/content/travel/en/international-travel/emergencies | 2026-10-20 |
| Embassy numbers | fmprc.gov.cn/ce/ (Chinese MFA) | 2026-10-20 |
