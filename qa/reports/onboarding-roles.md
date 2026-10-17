# QA Report: Onboarding, Brand & Role Flow Fixes

**Branch:** `fix/onboarding-roles`
**Date:** 2026-10-17
**Tests:** 213/213 passing (0 failures)

## Commits

| # | Commit | Description |
|---|--------|-------------|
| 1 | e3f99a9 | Brand constants (`Brand.swift`) — single source of truth for names, banned-name scanner test |
| 2 | f02e1cb | Disclaimer screen fixes — SF Symbol body, PageIndicator, AuditLog, status bar, truncation |
| 3 | f528438 | Shared `LanguageSwitcher` — extracted from OnboardingView and LoginView |
| 4 | 20c1ae2 | Login screen polish — helper text, contrast fix, country picker pinning, tagline, logo 120pt |
| 5 | cbd3038 | Role selection flow + InviteAcceptView + deep link wiring |
| 6 | 527d4a0 | Elder mode defaults — `.xLarge` minimum type, bold legibility for Care Receivers |

## Design Items Addressed

- **D-01:** Brand consolidation — `Brand.swift` replaces all inline "Velar Care" / "ShouDeng" references
- **D-02:** Disclaimer screens — SF Symbol icons in body text, page indicators, audit logging
- **D-04:** Language switcher shared component (EN/中/FR) on onboarding + login
- **D-05:** Login screen — tagline, helper text, button label, contrast, country picker pinning
- **D-06:** No separate signup link (backend auto-creates on new phone)
- **D-07:** Role selection as dedicated post-signup step with audit logging
- **D-08:** Invite acceptance view for Universal Link deep links
- **D-09:** Deep link wiring — pending links applied after login
- **D-10:** Elder mode defaults for Care Receivers

## Files Changed

### New Files
- `ShouDeng/Models/Brand.swift`
- `ShouDeng/Views/Shared/PageIndicator.swift`
- `ShouDeng/Views/Shared/LanguageSwitcher.swift`
- `ShouDeng/Views/Shared/ElderModeModifier.swift`
- `ShouDeng/Services/Compliance/AuditLog.swift`
- `ShouDeng/Views/Auth/RoleSelectView.swift`
- `ShouDeng/Views/Auth/InviteAcceptView.swift`
- `ShouDengTests/BrandTests.swift`

### Modified Files
- `ShouDeng/Views/Shared/OnboardingView.swift`
- `ShouDeng/Views/Shared/RootView.swift`
- `ShouDeng/Views/Auth/LoginView.swift`
- `ShouDeng/Views/Auth/CountryCodePicker.swift`
- `ShouDeng/Views/Auth/BiometricGateView.swift`
- `ShouDeng/Views/Protected/ProtectedTabView.swift`
- `ShouDeng/Views/Protected/ProtectedSettingsView.swift`
- `ShouDeng/Services/Compliance/DisclaimerCopy.swift`
- `ShouDeng/App/AppCoordinator.swift`
- `ShouDeng/en.lproj/Localizable.strings`
- `ShouDeng/zh-Hans.lproj/Localizable.strings`
- `ShouDeng/fr.lproj/Localizable.strings`
- `ShouDeng/en.lproj/InfoPlist.strings`
- `ShouDeng/fr.lproj/InfoPlist.strings`

## Test Coverage

- `BrandTests` (8 tests): displayTitle/subtitle per locale, constants, banned-name source scanner
- All 213 existing tests pass with zero regressions

## Manual QA Checklist

- [ ] Onboarding: 3 disclaimer screens render correctly with SF Symbol icons
- [ ] Onboarding: Page dots show correct active state
- [ ] Onboarding: Language switcher changes all text on all screens
- [ ] Login: Helper text visible below phone field before code sent
- [ ] Login: Country picker shows CA, CN, HK, US pinned at top
- [ ] Login: Disabled button has sufficient contrast
- [ ] Login: Logo displays at 120pt
- [ ] Role select: Appears after first signup, cards are tappable
- [ ] Role select: Confirm saves role and navigates to main app
- [ ] Invite accept: Universal Link opens InviteAcceptView as sheet
- [ ] Elder mode: Care Receiver screens use .xLarge minimum text
- [ ] Elder mode: Toggle in Settings works, persists across launches
- [ ] Brand: No "Velar Care" or "ShouDeng" visible anywhere in UI
