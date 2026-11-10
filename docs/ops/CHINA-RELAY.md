# Hong Kong relay for mainland-China networks

Mainland-China networks block `*.cloudfunctions.net` and every other Google address, so people
there cannot sign in or send an SOS through the backend (`us-central1`, project
`sweethome-b4e82`). Until there is a China-region deployment (a Chinese company, an ICP filing,
PIPL work), a small **reverse proxy in Hong Kong** gives them a path to the same backend:

```
iPhone (mainland) ──TLS──▶ https://api.<domain>/…  (HK server, Caddy or nginx)
                                   │
                                   └──TLS──▶ https://us-central1-sweethome-b4e82.cloudfunctions.net/api/…
```

Hong Kong servers need no ICP licence. The relay only forwards requests. Data is still stored
in the US, and the app already asks for consent to US storage.

What is in the code (branch `feat/china-relay`):

| Part | What it does |
|---|---|
| App: `BaseURLFailover` + `APIClient` | Keeps the primary URL. If the primary fails **in transit** (DNS, connect, TLS, timeout; never on an HTTP error) and the relay answers, the app uses the relay for 24 h. While on the relay it re-checks the primary at most once an hour (in the background) and goes back as soon as the primary answers. |
| App: SOS (`postSOS`) | Never waits for a slow primary. The preferred route starts at once, and the other route starts after 2.5 s, or immediately if the first fails in transit. The first 2xx wins. The server keeps one active SOS per person and de-duplicates by `clientSOSId`, so sending on both routes is safe. |
| App: offline queue | Queued items are flushed through whichever route works. |
| App: login screen | When the country is +86, or the app is on the relay, a note recommends Sign in with Apple / Alipay. Firebase phone codes need `identitytoolkit.googleapis.com`, which is blocked on mainland networks. |
| Backend: `trust proxy` (`src/config/relay.ts`) | `req.ip` is the phone's address, not the relay's. Otherwise everyone in China shares one rate-limit bucket, and the 5/min sign-in limit locks them all out together. Clients cannot spoof it (see §6). |
| Backend: `PUBLIC_LINK_BASE_URL` | Links people open (evidence share, incident-report verification) use the relay domain so they also open on mainland networks. |

---

## 1. Rent the server (you)

Any small Linux server in **Hong Kong** works. It forwards a few KB per request and stores
nothing.

- **Alibaba Cloud**: ECS or Simple Application Server (轻量应用服务器), region *China (Hong Kong)*.
- **Tencent Cloud**: Lighthouse (轻量应用服务器), region *Hong Kong*.
- Size: 1 vCPU / 1 GB RAM is plenty. Image: **Ubuntu 24.04** or Debian 12.
- Give it a **fixed public IPv4** (an EIP on ECS; Lighthouse IPs are fixed). Write it down: it
  goes into `TRUSTED_RELAY_IPS`.
- Security group / firewall: allow inbound **TCP 22, 80, 443** only.

Harden it (it decrypts TLS, so it can read the traffic in memory):

```bash
sudo apt update && sudo apt -y upgrade && sudo apt -y install unattended-upgrades ufw
```

```bash
sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw --force enable
```

Log in with an SSH key only (`PasswordAuthentication no` in `/etc/ssh/sshd_config`). Install
nothing else on this server.

Find the address Google will see. This is the server's **egress** address; usually it is the same
as the public IP:

```bash
curl -4 -s https://ifconfig.me; echo; curl -6 -s --max-time 5 https://ifconfig.me; echo
```

If the second command prints an IPv6 address, the server can reach Google over IPv6. With
Caddy, list that address too (§5). The nginx config below forces IPv4.

## 2. Domain and DNS (you)

`shoudeng.app` has no DNS yet. Pick the domain you want, for example `api.shoudeng.app` or a
separate domain kept just for the relay. **Choose one you will keep**: the relay URL is built
into the app (Info.plist `API_RELAY_URL`), so changing it means a new app build.

- Create an **A record** `api.<domain>` → the server's IPv4 (and an AAAA record only if you
  want to serve IPv6 to phones). Use a TTL of 600 s.
- Use a DNS provider that mainland resolvers reach reliably: **Alibaba Cloud DNS (云解析)** or
  **DNSPod (Tencent)**. Cloudflare also works, but only as **DNS only (grey cloud)**. Do not turn
  on Cloudflare's proxy (orange cloud): its addresses are often slow or blocked in China, and it
  would add a party that decrypts the traffic.
- Check that the record resolves: `dig +short api.<domain>`.

In the examples below, replace `api.example.com` with your relay hostname.

## 3. Reverse proxy: choose A (Caddy, simplest) or B (nginx)

Both configs:

- forward `https://api.<domain>/<path>` → `https://us-central1-sweethome-b4e82.cloudfunctions.net/api/<path>`;
- pass all request headers through, including `Authorization`, and set `Host` to the
  cloudfunctions host;
- **overwrite** `X-Forwarded-For` with the address the relay saw, so whatever the client sent is
  dropped;
- write **no access log**: no URLs, no IPs, and never request bodies (neither server logs bodies
  by default);
- accept bodies up to 10 MB (family photos are up to 8 MB of JSON);
- answer `GET /relay-health` themselves, without contacting the backend.

### A. Caddy (automatic HTTPS certificates)

```bash
sudo apt -y install debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt -y install caddy
```

`/etc/caddy/Caddyfile`:

```caddy
{
	# Let's Encrypt account e-mail (expiry notices)
	email ops@example.com
}

api.example.com {
	# No `log` directive = no access log. Caddy logs only its own errors, never bodies.

	# The relay itself is up (does not touch the backend)
	handle /relay-health {
		respond "ok" 200
	}

	handle {
		request_body {
			max_size 10MB
		}
		# Google serves the function under /api
		rewrite * /api{uri}
		reverse_proxy https://us-central1-sweethome-b4e82.cloudfunctions.net {
			header_up Host {upstream_hostport}
			# Only the address Caddy saw; a client-supplied X-Forwarded-For is dropped
			header_up X-Forwarded-For {remote_host}
			transport http {
				dial_timeout 10s
			}
		}
	}
}
```

```bash
sudo caddy validate --config /etc/caddy/Caddyfile && sudo systemctl reload caddy
```

Caddy gets and renews the Let's Encrypt certificate on its own. Port 80 must be open, and DNS
must already point at the server.

### B. nginx + certbot

```bash
sudo apt -y install nginx certbot
sudo mkdir -p /var/www/certbot
```

1. Serve the ACME challenge on port 80 first. Create `/etc/nginx/conf.d/shoudeng-relay.conf` with
   **only** the port-80 server block from step 3, reload nginx, then get the certificate:

   ```bash
   sudo certbot certonly --webroot -w /var/www/certbot -d api.example.com -m ops@example.com --agree-tos -n
   ```

2. Remove the default site so it cannot answer for this name:

   ```bash
   sudo rm -f /etc/nginx/sites-enabled/default
   ```

3. Write the full `/etc/nginx/conf.d/shoudeng-relay.conf`:

```nginx
# Google rotates its front-end addresses: resolve at runtime (needs a variable in
# proxy_pass), not once at start-up. IPv4 only, so TRUSTED_RELAY_IPS is one address.
resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
resolver_timeout 5s;

server {
    listen 80;
    listen [::]:80;
    server_name api.example.com;
    access_log off;

    location /.well-known/acme-challenge/ { root /var/www/certbot; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;                      # nginx < 1.25.1: remove this line, use "listen 443 ssl http2;"
    server_name api.example.com;

    ssl_certificate     /etc/letsencrypt/live/api.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:relay_tls:10m;

    # No access log (no URLs, no IPs). nginx never logs request bodies.
    access_log off;
    error_log /var/log/nginx/relay-error.log warn;

    client_max_body_size 10m;      # family photos (backend JSON limit 8 MB)

    # The relay itself is up (does not touch the backend)
    location = /relay-health {
        default_type text/plain;
        return 200 "ok\n";
    }

    location / {
        set $upstream us-central1-sweethome-b4e82.cloudfunctions.net;
        proxy_pass https://$upstream/api$request_uri;

        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $upstream;
        # Overwrite: only the address nginx saw. A client-supplied X-Forwarded-For is dropped.
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto https;
        # Authorization and all other client headers pass through unchanged.

        proxy_ssl_server_name on;
        proxy_ssl_name $upstream;
        proxy_ssl_verify on;
        proxy_ssl_verify_depth 4;
        proxy_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;

        # Stream bodies both ways: nothing is written to temp files on disk
        proxy_request_buffering off;
        proxy_buffering off;

        proxy_connect_timeout 10s;
        proxy_send_timeout 75s;
        proxy_read_timeout 75s;
    }
}
```

```bash
sudo nginx -t && sudo systemctl reload nginx
```

Renewal: the certbot package installs a systemd timer. Add a deploy hook so nginx picks up the
new certificate:

```bash
echo -e '#!/bin/sh\nsystemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh && sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

## 4. Health checks

From anywhere:

```bash
curl -sS https://api.example.com/relay-health
```

→ `ok` (the relay is up and its certificate is valid).

```bash
curl -sS https://api.example.com/health
```

→ `{"status":"ok","service":"shoudeng-backend",…}`: the full path to the backend works. The app
uses this same URL for its background route checks.

```bash
curl -sS https://api.example.com/v1/auth/providers
```

→ `{"phone":true,"apple":true,"alipay":…}`: real API routes come through, including path and
query.

From **inside the mainland**:

- Ask someone on a mainland mobile network (China Mobile / Unicom / Telecom) to open
  `https://api.<domain>/health` in Safari, or
- use an online multi-node HTTP test with mainland probes (for example ITDOG or 17CE HTTP
  tests) against `https://api.<domain>/health`.

Ongoing monitoring: point Alibaba CloudMonitor site monitoring (站点监控), Tencent Cloud
monitoring, or Uptime Kuma at `https://api.<domain>/health` every 1–5 minutes, with alerts to
you. If `/relay-health` is fine but `/health` fails, the HK → Google leg is down. If both fail,
the server or its address is unreachable.

## 5. Backend settings (you, then deploy)

In `shoudeng-backend/functions/.env` (git-ignored; template in `.env.example`):

```bash
# The relay's egress address(es), as printed by ifconfig.me in §1. Add the IPv6 one
# only if you use Caddy and the server has IPv6. Comma-separated.
TRUSTED_RELAY_IPS=203.0.113.10

# Links people open (evidence share, incident-report verification): through the relay
PUBLIC_LINK_BASE_URL=https://api.example.com

# Alipay sends people back here after they agree (must match 授权回调地址 below)
ALIPAY_REDIRECT_URI=https://api.example.com/v1/auth/alipay/callback

# Leave EMPTY: Twilio (US) keeps calling Google directly; see the note below
PUBLIC_API_BASE_URL=
```

**Why `PUBLIC_API_BASE_URL` stays empty.** That URL is where Twilio sends SOS voice callbacks
(the guardian pressing 1 to acknowledge) and call-status webhooks, and Twilio signatures are
checked against it. Twilio is in the US, so pointing it at the relay would only make SOS calls
depend on one small HK server. The new `PUBLIC_LINK_BASE_URL` moves just the links people open.
If you do want Twilio to use the relay as well, set `PUBLIC_API_BASE_URL` to the relay URL too:
signatures still match, because they are computed over the same base.

**Alipay Open Platform (支付宝开放平台)** → your app → 开发设置 → **授权回调地址**: set it to
`https://api.<domain>/v1/auth/alipay/callback`, the same as `ALIPAY_REDIRECT_URI`. Alipay
checks that the two match. Alipay's console may require the callback domain to be verified, and
in some cases ICP-filed. If it refuses a non-ICP domain, Sign in with Alipay on mainland networks
has to wait for the China deployment. Sign in with Apple is unaffected.

Then deploy (you):

```bash
cd shoudeng-backend && firebase deploy --only functions --project sweethome-b4e82
```

## 6. Why X-Forwarded-For cannot be spoofed

Google's front end appends the address it saw to `X-Forwarded-For`. Express walks the list from
the right (`trustProxy` in `src/config/relay.ts`):

| Situation | X-Forwarded-For arriving at the function | `req.ip` |
|---|---|---|
| Phone → Google directly | `<phone>` | `<phone>` |
| Phone → relay → Google | `<phone>, <relay>` (relay overwrote the client's header) | `<phone>` |
| Attacker → Google, header `1.2.3.4, <relay>` | `1.2.3.4, <relay>, <attacker>` | `<attacker>` |
| Relay configured to append instead of overwrite | `<junk>, <phone>, <relay>` | `<phone>` |
| `TRUSTED_RELAY_IPS` empty | `<phone>, <relay>` | `<relay>` (old behaviour) |

The relay is trusted only as the **second** hop, and only if its address is listed. Nothing
further left is ever trusted. `src/__tests__/relay.test.ts` covers each row, plus the sign-in
rate limit behind the relay.

## 7. App settings (you, next build)

Set Info.plist **`API_RELAY_URL`** to `https://api.<domain>` (no `/api`, no trailing slash).
Empty means relay off, and the app behaves exactly as before. Then build and upload as usual.
Remember that `CFBundleVersion` lives in both `project.pbxproj` and `Info.plist`.

Debug builds can point at a local stub with the launch argument
`-apiRelayURL http://127.0.0.1:PORT`.

How the app picks a route, for support questions:

- **GET/PUT/DELETE** that fail in transit are retried at once on the other route.
- **POST** is retried on the other route only if it certainly never left the phone (DNS, connect,
  TLS failure). A POST that timed out may already have been applied (a token refresh, for
  example), so it is not resent. The app checks both routes in the background instead, and the
  next request goes the right way.
- **Queued items** (check-ins, locations, offline SOS) are retried on the other route: the queue
  delivers them at least once anyway.
- Being offline never switches routes: the preference changes only when the other route actually
  answered. A relay `502/503/504` does not count as answering.
- The choice is stored (`api.relayPreferredUntil` in UserDefaults) and survives restarts for 24 h.
  It is renewed while the primary stays unreachable.

## 8. What you must do: checklist

1. Rent a HK server (§1), harden it, and note its egress IP.
2. Pick the domain and create the DNS record (§2).
3. Install Caddy (§3A) or nginx + certbot (§3B), replacing `api.example.com` and the e-mail.
4. Run the health checks (§4), including one from inside the mainland, and set up monitoring.
5. Set `TRUSTED_RELAY_IPS`, `PUBLIC_LINK_BASE_URL` and `ALIPAY_REDIRECT_URI` in
   `functions/.env`, and set the Alipay 授权回调地址 (§5). Deploy functions.
6. Set `API_RELAY_URL` in Info.plist (§7) and ship a new TestFlight build.
7. Test from a mainland network: Sign in with Apple, a check-in, an SOS (in a Beta build with
   simulated SOS, or with a guardian who knows it's a test). Also try a phone sign-in with +86 to
   see the hint.

## 9. Known limits

- **Reliable most of the time, never guaranteed.** The Great Firewall can slow down or block any
  foreign IP or domain without notice, especially when traffic grows. If the relay's IP gets
  blocked, attach a new EIP and update DNS and `TRUSTED_RELAY_IPS`. If the domain itself gets
  blocked, you need a new domain and a new app build. A second relay hostname (and the SOS text
  fallback, which needs no server) are the backstops.
- **Data stays in the US.** The relay stores nothing, but every request passes through Hong Kong
  to Google us-central1. The app already asks for consent to cross-border (US) storage. The HK
  server decrypts TLS, so it is a point of trust: keep it patched, use SSH keys only, run nothing
  else on it.
- **The China App Store needs an ICP filing.** Until then the app is not on the China storefront,
  and mainland users need an Apple ID from another region (Hong Kong, for example) to install it.
- **Still blocked on mainland networks, even with the relay:**
  - *Phone sign-in*: Firebase phone auth (`identitytoolkit.googleapis.com`). The login screen
    points to Apple / Alipay instead.
  - *Push notifications*: the app cannot get an FCM token (`fcmregistrations.googleapis.com`). The
    separate "push straight to APNs" task fixes this. Until then, guardians in China see alerts
    only when they open the app.
  - *Photos, voice notes, evidence files*: these are served from `storage.googleapis.com` signed
    URLs.
  - *Crash reports and analytics* (Firebase) from mainland devices are lost.
  - *Twilio SMS and calls to +86 numbers* are delivered unreliably (carrier filtering), separate
    from the relay.
- **SOS may cross Hong Kong outside China too.** If Google does not answer within 2.5 s (for
  example a cold start), the SOS also goes out through the relay. The server keeps only one, but
  that copy did pass through Hong Kong.
- **The first request on a newly blocked network can be slow.** A silently dropped connection
  takes up to the 30 s request timeout before failing over (SOS: 2.5 s). After that the relay is
  remembered.

## 10. Later steps (not built)

- **Server-side SMS sign-in codes for +86** through Alibaba Cloud SMS or Tencent Cloud SMS.
  Sending to mainland numbers needs a registered sender signature (短信签名) and approved
  templates (短信模板), which generally need a Chinese business entity. Not built now. When
  added, it would sit behind `/v1/auth/send-code`, and the app would use it for +86 instead of
  Firebase.
- **A `files.<domain>` relay for Cloud Storage**: proxy to `storage.googleapis.com` with
  `Host: storage.googleapis.com` (V4 signed URLs sign that host, so signatures still verify), and
  have the app rewrite signed-URL hosts while on the relay.
- **Push straight to APNs** (separate task).
- **A second relay** (another provider or region) and an IP-rotation runbook.
- **Real China deployment**: a Chinese company, an ICP filing, PIPL (personal information
  protection assessment, data localisation), and mainland hosting such as Alibaba Cloud
  Shanghai. At that point the relay becomes unnecessary.
