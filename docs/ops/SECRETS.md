# Backend secrets and config (Cloud Functions, project `sweethome-b4e82`)

The functions read their configuration through **firebase-functions params**
(`shoudeng-backend/functions/src/config/params.ts`). `functions.config()` (Runtime Config) is
no longer used anywhere — Google shuts it down in March 2027, and production's Runtime Config is
empty anyway (`firebase functions:config:get` → `{}`), which is why SOS SMS and voice calls were
never sent.

There are two kinds of value:

| Kind | Where it lives | How the functions get it |
|---|---|---|
| **Secret** (`defineSecret`) | Cloud Secret Manager | Only functions that bind it (`runWith({ secrets })`) see it as an env var |
| **Plain value** (`defineString` / `process.env`) | `shoudeng-backend/functions/.env` (git-ignored) | Copied into every function's env at deploy |

## 1. Secrets — set once, before the next deploy

Each command prompts for the value (input hidden). Run from the repo root, logged in as a
project owner. **Don't paste values into chat, commits, or this file.**

```bash
firebase functions:secrets:set TWILIO_ACCOUNT_SID --project sweethome-b4e82
```

```bash
firebase functions:secrets:set TWILIO_AUTH_TOKEN --project sweethome-b4e82
```

```bash
firebase functions:secrets:set GOOGLE_MAPS_API_KEY --project sweethome-b4e82
```

```bash
firebase functions:secrets:set APNS_AUTH_KEY --data-file AuthKey_KEYID.p8 --project sweethome-b4e82
```

| Secret | Value | Used by |
|---|---|---|
| `TWILIO_ACCOUNT_SID` | Twilio Console → Account Info → Account SID (`AC…`) | SOS SMS, SOS voice calls |
| `TWILIO_AUTH_TOKEN` | Twilio Console → Account Info → Auth Token | Same, plus verifying Twilio's webhook signatures (`/v1/voice-callback`, `/v1/webhooks/twilio/call-status`) |
| `GOOGLE_MAPS_API_KEY` | Google Cloud Console → APIs & Services → Credentials; key restricted to the **Geocoding API** | Reverse-geocoding addresses for guardians / evidence |
| `APPLE_SIWA_PRIVATE_KEY` | Contents of the Sign in with Apple key file (`AuthKey_XXXX.p8`, see §4) | Revoking a person's Sign in with Apple when they delete their account (App Review 5.1.1(v)) |
| `ALIPAY_PRIVATE_KEY` | Your app's RSA2 private key from Alipay's key tool (see §5) | Sign in with Alipay |
| `APNS_AUTH_KEY` | Contents of the APNs auth key file (`AuthKey_XXXX.p8`, see §6) | **Every push notification**, SOS alerts included (sent straight to Apple, not through FCM) |

Which functions bind them (`firebase deploy` grants each function's service account
`secretAccessor` automatically):

| Function | Secrets |
|---|---|
| `api` | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `APNS_AUTH_KEY`, `GOOGLE_MAPS_API_KEY`, `APPLE_SIWA_PRIVATE_KEY`, `ALIPAY_PRIVATE_KEY` |
| `onSOSCreated` (Firestore trigger) | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `APNS_AUTH_KEY` |
| `advanceEscalations` (every minute) | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `APNS_AUTH_KEY` |
| `checkHeartbeatMissing`, `checkCheckinOverdue`, `checkHomeTimerExpiry`, `checkSilentAlarms` | `APNS_AUTH_KEY` |

`firebase deploy` **refuses to deploy** (or, in an interactive terminal, asks for the value)
while a bound secret doesn't exist in Secret Manager. If you don't have a Google Maps key yet
and want geocoding off, store the word `disabled` — the code treats it as "not configured":

```bash
printf disabled | firebase functions:secrets:set GOOGLE_MAPS_API_KEY --data-file - --project sweethome-b4e82
```

(The same works for the Twilio secrets, but then SOS reaches guardians by push only.)

**New since Sign in with Apple / Alipay:** the next deploy needs `APPLE_SIWA_PRIVATE_KEY` and
`ALIPAY_PRIVATE_KEY` to exist. Until you have the keys, store `disabled` (Apple sign-in still
works; account deletion just can't revoke it; the Alipay button stays hidden):

```bash
printf disabled | firebase functions:secrets:set APPLE_SIWA_PRIVATE_KEY --data-file - --project sweethome-b4e82
```

```bash
printf disabled | firebase functions:secrets:set ALIPAY_PRIVATE_KEY --data-file - --project sweethome-b4e82
```

**New since direct APNs push:** the next deploy needs `APNS_AUTH_KEY` to exist (and
`APNS_KEY_ID=` in `functions/.env`, see §2). Until you have the key, store `disabled` — no push
is sent at all then, and SOS reaches guardians by SMS and calls only:

```bash
printf disabled | firebase functions:secrets:set APNS_AUTH_KEY --data-file - --project sweethome-b4e82
```

**Rotating a secret:** run the same `secrets:set` command again, then redeploy the functions
so running instances pick up the new version:

```bash
firebase deploy --only functions --project sweethome-b4e82
```

Old versions can be listed with `firebase functions:secrets:get TWILIO_AUTH_TOKEN --project sweethome-b4e82`
and removed with `firebase functions:secrets:prune --project sweethome-b4e82`.

## 2. Plain values — `shoudeng-backend/functions/.env`

`.env` is git-ignored and already holds `JWT_SECRET`. Add the lines below with your own values
(no quotes needed). Every key that a `defineString` param declares must be present —
otherwise a non-interactive `firebase deploy` stops with "have no value for the following
environment variables", and an interactive one prompts. An empty value (`KEY=`) is fine.

```dotenv
# --- Twilio (SOS SMS + voice calls) ---
# Your Twilio phone number in E.164 (e.g. +1…), voice-capable. Caller ID for SOS calls,
# and the SMS sender unless TWILIO_SMS_FROM is set.
TWILIO_FROM_NUMBER=
# Optional separate SMS sender: another Twilio number, or an alphanumeric sender ID where
# the destination country allows it (not US/CA). Empty = TWILIO_FROM_NUMBER.
TWILIO_SMS_FROM=

# --- App Store (payment code — owned by the payment work, documented here for completeness) ---
# Numeric Apple ID of the app (App Store Connect → App Information → Apple ID).
APPLE_APP_ID=
# Verifier tries Production, then Sandbox (TestFlight, App Review). "false" refuses Sandbox.
APPLE_ALLOW_SANDBOX=true
# APPLE_ENVIRONMENT — not read by the code on release/1.0-integration (environments are
# handled by Production-then-Sandbox above). Leave it out unless the payment code starts using it.

# --- Push (APNs, §6) ---
# Key ID of the APNs auth key; its .p8 is the APNS_AUTH_KEY secret. Empty = no push.
APNS_KEY_ID=
# "true" only after Apple grants the Critical Alerts entitlement (docs/critical-alerts-entitlement-application.md).
CRITICAL_ALERTS_ENABLED=false

# --- Public URL of the `api` function ---
# Leave empty to use https://us-central1-sweethome-b4e82.cloudfunctions.net/api. Set it only
# when Twilio must reach the API through another host (custom domain / Hosting rewrite):
# Twilio webhook signatures are checked against this exact URL.
PUBLIC_API_BASE_URL=
```

| Key | Type | Read by | If unset |
|---|---|---|---|
| `TWILIO_FROM_NUMBER` | `defineString` | `services/twilio.ts`, `services/sms.ts` | No calls; no SMS unless `TWILIO_SMS_FROM` is set |
| `TWILIO_SMS_FROM` | `defineString` | `services/sms.ts` | SMS sent from `TWILIO_FROM_NUMBER` |
| `APPLE_APP_ID` | `process.env` | `services/payment.ts` | Production App Store notifications answered 401 (Apple retries) |
| `APPLE_ALLOW_SANDBOX` | `process.env` | `services/payment.ts` | `true` |
| `APPLE_ENVIRONMENT` | — | not read (see above) | — |
| `APNS_KEY_ID` | `defineString` | `services/apns.ts` | No push notifications (SOS: SMS + calls only) |
| `APPLE_TEAM_ID` | `defineString` | `services/apns.ts`, `services/appleSignIn.ts` | `B98QT5LTWZ` |
| `CRITICAL_ALERTS_ENABLED` | `process.env` | `services/fcm.ts` | Time-sensitive SOS pushes |
| `PUBLIC_API_BASE_URL` | `process.env` | `services/twilio.ts`, `services/escalation.ts` | Default cloudfunctions.net URL |
| `JWT_SECRET` | `process.env` | `middleware/auth.ts`, `routes/auth.ts` | API refuses to sign/verify tokens |

## 3. Deploy and check

```bash
firebase deploy --only functions --project sweethome-b4e82
```

Then trigger a real SOS from a TestFlight build (Settings → TestFlight 开发者选项 →
真实 SOS) with a test guardian account and look for:

```bash
firebase functions:log --project sweethome-b4e82 --lines 200
```

- `[Config] … disabled — not configured: …` means a value is still missing (logged once per
  function instance). If it names `APNS_*`, no push went out and SOS used SMS / calls.
- `[Push] SOS alert sent to <guardian>: 1 success, 0 failure` means Apple accepted the push.
  `[Push] … failed (403 InvalidProviderToken)` = wrong key / key ID / team;
  `(400 DeviceTokenNotForTopic)` = the key isn't allowed for `com.shoudeng.app`;
  `[Push] removed … token` = Apple said the phone's token is dead (the app re-registers on next launch).
- `[Twilio] Call CA… placed` / `[SMS] SOS SMS sent` mean Twilio works. The SOS document's
  `escalationLog` shows each channel (`push`, `sms_fallback`, `voice`, `push_voice_unavailable`, …).

## 4. Sign in with Apple

Sign-in itself needs no secret: the server checks Apple's signed token against Apple's public
keys (`services/appleSignIn.ts`). What needs setting up:

1. **App ID capability** — Apple Developer → Certificates, IDs & Profiles → Identifiers →
   `com.shoudeng.app` → tick **Sign in with Apple** → Save. (Or open the project in Xcode once,
   signed in: Signing & Capabilities picks up the new entitlement.) Without it the build
   can't be signed with the `com.apple.developer.applesignin` entitlement.
2. **Key for revocation** — Keys → **+** → name it, tick **Sign in with Apple** → Configure →
   primary App ID `com.shoudeng.app` → Register → download `AuthKey_<KEYID>.p8` (once only).
   ```bash
   firebase functions:secrets:set APPLE_SIWA_PRIVATE_KEY --data-file AuthKey_KEYID.p8 --project sweethome-b4e82
   ```
   and in `functions/.env`: `APPLE_SIWA_KEY_ID=<KEYID>` (team: `APPLE_TEAM_ID`, default `B98QT5LTWZ`).

## 5. Sign in with Alipay (支付宝登录)

Off until all three values are set; `GET /v1/auth/providers` then reports `alipay: true` and the
app shows the button. Needs an Alipay Open Platform (支付宝开放平台) account with enterprise
verification.

1. open.alipay.com → create an app (网页/移动应用), add the product **获取会员信息** (user info),
   and submit it for review.
2. 开发设置 → 接口加签方式: **公钥** mode, RSA2. Generate a key pair with Alipay's key tool, upload
   the app public key, and copy **支付宝公钥** (Alipay's public key).
3. 开发设置 → 授权回调地址: `https://us-central1-sweethome-b4e82.cloudfunctions.net/api/v1/auth/alipay/callback`
   (or set `ALIPAY_REDIRECT_URI` if you serve the API from another domain).
4. Secret: `firebase functions:secrets:set ALIPAY_PRIVATE_KEY --project sweethome-b4e82` (paste
   the app private key — bare base64 or PEM, PKCS#8 or PKCS#1). `functions/.env`:
   `ALIPAY_APP_ID=<APPID>` and `ALIPAY_PUBLIC_KEY=<支付宝公钥>`.

**Mainland China:** the Alipay page sends the person back to this API's callback, and the app
talks to this API; both are Google addresses, blocked on mainland networks. Alipay sign-in
works for people outside the mainland (or roaming) until the API is reachable from China.

## 6. Push notifications (APNs)

The app registers its raw APNs device token (`POST /v1/device/token`; it has no Firebase
Messaging), so the backend sends straight to Apple over HTTP/2 with token auth
(`services/apns.ts`). Firebase Cloud Messaging is not used: it can't deliver to raw APNs
tokens, and it is blocked on mainland-China networks while APNs is not.

1. Apple Developer → Certificates, IDs & Profiles → **Keys** → **+** → name it (e.g.
   "Lantern APNs"), tick **Apple Push Notifications service (APNs)** → Configure →
   environment **Sandbox & Production**, key restriction **Team Scoped (All Topics)** or the
   topic `com.shoudeng.app` → Save → Continue → Register → **Download** `AuthKey_<KEYID>.p8`
   (Apple lets you download it once; keep it somewhere safe, outside the repo). Note the Key ID.
   (A key that already has Sign in with Apple can also get APNs ticked — then the same `.p8`
   and Key ID are used for both.)
2. Store the key and its ID:
   ```bash
   firebase functions:secrets:set APNS_AUTH_KEY --data-file AuthKey_KEYID.p8 --project sweethome-b4e82
   ```
   and in `functions/.env`: `APNS_KEY_ID=<KEYID>` (team: `APPLE_TEAM_ID`, default `B98QT5LTWZ`).
3. Deploy, then raise a real SOS from a TestFlight build to a guardian's phone and check the
   log lines in §3.

Environments: the app sends `environment: "development"` from Xcode debug builds (APNs
sandbox) and `"production"` from TestFlight / App Store builds. If Apple answers
`BadDeviceToken`, the other environment is tried once and the stored value corrected. Tokens
Apple reports as `Unregistered` (410), or bad on both hosts, are deleted.

## Behaviour when something is missing

Nothing throws. Without `APNS_AUTH_KEY` / `APNS_KEY_ID` no push is sent and SOS counts as
"push failed", so guardians get the SMS fallback and calls. SMS returns "not sent" (push is the primary channel; SMS is only the fallback
when push fails or a guardian has no app), each voice round is replaced by an SOS push reminder
(`push_voice_unavailable`), emergency contacts without the app get no text, and addresses are
left out of geocoded views. One `[Config]` error per instance names the missing keys.

## Not done here (optional hardening)

`JWT_SECRET` is still a plain `.env` value. Moving it to Secret Manager would mean
`defineSecret("JWT_SECRET")`, binding it to `api`, setting the **same** value with
`firebase functions:secrets:set JWT_SECRET` (a new value logs everyone out), and removing the
line from `.env` in the same deploy (a key can't be both a secret and an env var).
