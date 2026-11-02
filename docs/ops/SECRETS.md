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

| Secret | Value | Used by |
|---|---|---|
| `TWILIO_ACCOUNT_SID` | Twilio Console → Account Info → Account SID (`AC…`) | SOS SMS, SOS voice calls |
| `TWILIO_AUTH_TOKEN` | Twilio Console → Account Info → Auth Token | Same, plus verifying Twilio's webhook signatures (`/v1/voice-callback`, `/v1/webhooks/twilio/call-status`) |
| `GOOGLE_MAPS_API_KEY` | Google Cloud Console → APIs & Services → Credentials; key restricted to the **Geocoding API** | Reverse-geocoding addresses for guardians / evidence |

Which functions bind them (`firebase deploy` grants each function's service account
`secretAccessor` automatically):

| Function | Secrets |
|---|---|
| `api` | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `GOOGLE_MAPS_API_KEY` |
| `onSOSCreated` (Firestore trigger) | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` |
| `advanceEscalations` (every minute) | `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` |

`firebase deploy` **refuses to deploy** (or, in an interactive terminal, asks for the value)
while a bound secret doesn't exist in Secret Manager. If you don't have a Google Maps key yet
and want geocoding off, store the word `disabled` — the code treats it as "not configured":

```bash
printf disabled | firebase functions:secrets:set GOOGLE_MAPS_API_KEY --data-file - --project sweethome-b4e82
```

(The same works for the Twilio secrets, but then SOS reaches guardians by push only.)

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

# --- Push ---
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
  function instance; SOS still went out by push).
- `[Twilio] Call CA… placed` / `[SMS] SOS SMS sent` mean Twilio works. The SOS document's
  `escalationLog` shows each channel (`push`, `sms_fallback`, `voice`, `push_voice_unavailable`, …).

## Behaviour when something is missing

Nothing throws. SMS returns "not sent" (push is the primary channel; SMS is only the fallback
when push fails or a guardian has no app), each voice round is replaced by an SOS push reminder
(`push_voice_unavailable`), emergency contacts without the app get no text, and addresses are
left out of geocoded views. One `[Config]` error per instance names the missing keys.

## Not done here (optional hardening)

`JWT_SECRET` is still a plain `.env` value. Moving it to Secret Manager would mean
`defineSecret("JWT_SECRET")`, binding it to `api`, setting the **same** value with
`firebase functions:secrets:set JWT_SECRET` (a new value logs everyone out), and removing the
line from `.env` in the same deploy (a key can't be both a secret and an env var).
