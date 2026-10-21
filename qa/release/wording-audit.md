# Emergency-Service Wording Audit — Release 1.0 NA

**Date**: 2026-10-20
**Scope**: All Swift files, .strings files, .xcprivacy, Info.plist in ShouDeng/
**Result**: PASS — No dangerous wording found

## Methodology

Searched all user-facing strings across EN/ZH/FR for:
1. Claims the app IS an emergency service
2. "dispatch responders" / "replace 911" language
3. Unqualified "guarantee" / "save lives" claims
4. Any term on DisclaimerCopy.swift bannedWords list

## Key Findings

### All Emergency References Are Properly Disclaimed

| Location | String | Safety |
|----------|--------|--------|
| DisclaimerCopy.swift (onboarding screen 1, ZH) | "无法替代警方、消防或急救" | SAFE — negative framing |
| DisclaimerCopy.swift (onboarding screen 1, EN) | "it cannot replace police, fire, or medical services" | SAFE |
| DisclaimerCopy.swift (onboarding screen 1, FR) | "ne remplace ni la police, ni les pompiers, ni les secours" | SAFE |
| Localizable.strings (all 3 locales) | "This app notifies your family. It does not replace emergency services." | SAFE |
| LegalView.swift | "本应用不替代110/119/120等专业紧急服务" | SAFE |
| DisclaimerCopy.swift (SOS disclosure) | "守灯不会代你拨打急救电话" | SAFE |
| DisclaimerCopy.swift (persistent banner) | "已通知你的家人。如情况危急，请同时拨打 112。" | SAFE |

### Guarantee Claims — All Negated

| Location | String | Safety |
|----------|--------|--------|
| DisclaimerCopy.swift (ZH) | "无法保证网络、设备或对方一定能及时响应" | SAFE — "cannot guarantee" |
| DisclaimerCopy.swift (EN) | "cannot guarantee network, device, or recipient availability" | SAFE |
| DisclaimerCopy.swift (FR) | "ne pouvons garantir la disponibilite..." | SAFE |
| LegalView.swift | "不保证在所有情况下都能成功发送警报" | SAFE |

### Dispatch / Save Lives — Not Used

- No occurrences of "dispatch responders", "save lives", "救命", "sauver des vies"
- `dispatchTimer` in FallConfirmationOverlay.swift is a GCD queue name, not user-facing

### BannedWords Registry (DisclaimerCopy.swift)

```
监控, 追踪, 保证, 确保, 保障, 报警, 实时, 一键报警, 精准检测
```

Coverage is comprehensive. Replacement guidance maps each banned term to safe alternatives.

### Info.plist Usage Descriptions

All 4 permission strings (location, microphone, motion, Face ID) describe data sharing with "chosen family members" — never claim emergency dispatch.

### Store Metadata (en-CA, fr-CA, zh-Hans)

All three store descriptions include explicit "What Luma is NOT" section stating the app is not an emergency service.

## Conclusion

No changes required. All emergency-related terminology is properly disclaimed across all 3 locales with consistent negative framing, liability waivers, and persistent user-facing warnings.
