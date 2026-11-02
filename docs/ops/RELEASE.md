# Archiving: TestFlight (Beta) vs App Store (Release)

## Two configurations, two schemes

| | **Release** (App Store) | **Beta** (TestFlight) |
|---|---|---|
| Build settings | Release, no `BETA` | Release + `SWIFT_ACTIVE_COMPILATION_CONDITIONS = BETA` |
| Shared scheme | `ShouDeng` (Archive = Release) | `ShouDeng-TestFlight` (Run / Profile / Archive = Beta) |
| SOS | Real: server, push, SMS, calls | **Simulated** by default (auto-acknowledged after 2 s, nobody notified); a tester can turn on real SOS |
| Orange "TestFlight 测试版" banner | — | yes (red when real SOS is on) |
| Settings → "TestFlight 开发者选项" | — | "真实 SOS（会通知家人）" switch, default off |
| Family-feed diagnostic line | — | yes (`#if BETA \|\| DEBUG`) |
| Role-switch buttons in Settings | hidden | hidden (DEBUG only — see below) |

History: up to build 39 the Beta configuration did not compile (it referenced
`EscalationState.acknowledged`, which doesn't exist) and the `ShouDeng` scheme archives
Release, so recent TestFlight builds were Release builds — real SOS, no banner (the build 30
and 32 archives contain no beta strings). Release does not define `BETA`.

Everything Beta-only is behind `#if BETA` (`ShouDeng/App/BuildChannel.swift`,
`AppCoordinator.triggerSOS`, `RootView.betaBanner`, both settings views), so none of it is in
a Release binary.

### Why compile-time and not "detect TestFlight at runtime"

A single binary that checks its receipt / `AppTransaction.environment` at runtime would let
the TestFlight build be promoted to the App Store as is. It isn't used because **App Review
runs the app in the same sandbox environment as TestFlight**: the reviewer would get the
beta banner and a simulated SOS, which is both a rejection risk (Guideline 2.2, no beta
content) and wrong (the reviewer must see real behaviour). `appStoreReceiptURL` is also
deprecated since iOS 18.

The runtime check is kept as a **safety net only**: a Beta binary whose `AppTransaction`
says `production` (i.e. installed from the App Store by mistake) behaves like Release —
real SOS, no banner, no developer switches.

### TestFlight testers: real SOS end to end

Settings → **TestFlight 开发者选项** → **真实 SOS（会通知家人）**. While on, the banner turns
red and every SOS goes to the server and notifies that family's guardians by push, then
SMS / calls per the escalation plan. Use test guardian accounts and phones. Stored per device
(`beta.realSOSEnabled`); off after a reinstall.

## Archive for TestFlight (Beta)

Xcode: scheme **ShouDeng-TestFlight** → Product → Archive → Distribute App → TestFlight.

CLI (bump the build number first, see below):

```bash
xcodebuild archive -project ShouDeng.xcodeproj -scheme ShouDeng-TestFlight -destination generic/platform=iOS -archivePath ~/Downloads/ShouDeng_1.0.0_40_beta.xcarchive -allowProvisioningUpdates
```

```bash
xcodebuild -exportArchive -archivePath ~/Downloads/ShouDeng_1.0.0_40_beta.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath /tmp/ShouDeng-export -allowProvisioningUpdates
```

In App Store Connect, put "BETA build — do not submit" in the build's *What to Test*.

## Archive for the App Store (Release)

Xcode: scheme **ShouDeng** → Product → Archive (the scheme's Archive action is Release).

```bash
xcodebuild archive -project ShouDeng.xcodeproj -scheme ShouDeng -configuration Release -destination generic/platform=iOS -archivePath ~/Downloads/ShouDeng_1.0.0_41.xcarchive -allowProvisioningUpdates
```

Check the binary has no beta code before uploading (must print `0`):

```bash
grep -c -a "TestFlight 测试版" ~/Downloads/ShouDeng_1.0.0_41.xcarchive/Products/Applications/ShouDeng.app/ShouDeng
```

Then export/upload with the same `-exportArchive` command (ExportOptions.plist uploads to App
Store Connect). This Release build also appears in TestFlight — install it there for the final
check of the exact binary you will submit (its SOS is real).

`.github/workflows/ci.yml` archives Release, so CI uploads are App Store-safe.

### The one thing to watch in App Store Connect

App Store Connect lets you pick **any** processed build for submission, including a Beta one.
When adding the build to the version, pick a build number you archived with the `ShouDeng`
scheme. (If a Beta build slips through, the runtime safety net makes it behave like Release
for App Store users, but App Review would still see the banner.)

## Build numbers

Every upload needs a new `CFBundleVersion`, Beta or Release. It lives in
`ShouDeng.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION`), `ShouDeng/Info.plist` and
`ShouDengWidgets/Info.plist` — bump all three (example 39 → 40):

```bash
sed -i '' 's/CURRENT_PROJECT_VERSION = 39;/CURRENT_PROJECT_VERSION = 40;/' ShouDeng.xcodeproj/project.pbxproj
```

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 40" ShouDeng/Info.plist
```

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion 40" ShouDengWidgets/Info.plist
```

## Role switching (not shipped)

"切换为守护者 / 切换为被守护者" in Settings → Role is compiled only in DEBUG builds: switching
silently stops protection for the person who switches. The informational role row and "Join
a family" stay. The real fix is roles phase B in `docs/roles/ROLES.md` (dual roles + view
switcher).
