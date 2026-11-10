/**
 * The Hong Kong relay (docs/ops/CHINA-RELAY.md): a reverse proxy that people on
 * mainland-China networks reach instead of cloudfunctions.net.
 *
 * Request path:  phone → relay (HK) → Google front end → this function.
 * Google's front end appends the address it saw to X-Forwarded-For, so a request
 * through the relay arrives with  X-Forwarded-For: <phone>, <relay>.
 *
 * `trust proxy` must therefore trust one hop (Google) always, and a second hop only
 * when that hop is one of OUR relays — otherwise everybody in China shares the
 * relay's address and the 5/min sign-in limit locks them all out together. An entry
 * further left is never trusted, so a client cannot choose its own req.ip: going
 * direct, Google appends the client's real address (not a relay → stop there);
 * through the relay, the relay overwrites X-Forwarded-For with the address it saw.
 *
 * TRUSTED_RELAY_IPS: comma-separated public egress addresses of the relay
 * (IPv4 and, if the server has one, IPv6). Empty = no relay, one hop as before.
 */

/** "::ffff:1.2.3.4" (IPv4-mapped) → "1.2.3.4"; lower-case IPv6. */
export function normalizeIp(addr: string): string {
  const a = addr.trim().toLowerCase();
  return a.startsWith("::ffff:") && a.includes(".") ? a.slice(7) : a;
}

let cachedRaw: string | undefined;
let cachedSet = new Set<string>();

/** Parsed TRUSTED_RELAY_IPS (re-parsed only when the value changes). */
export function trustedRelayIps(raw = process.env.TRUSTED_RELAY_IPS ?? ""): Set<string> {
  if (raw !== cachedRaw) {
    cachedRaw = raw;
    cachedSet = new Set(raw.split(/[\s,]+/).map(normalizeIp).filter(Boolean));
  }
  return cachedSet;
}

/**
 * Express `trust proxy` function. proxy-addr calls it with the socket peer first
 * (i = 0, Google's front end), then X-Forwarded-For entries right to left, and
 * stops at the first untrusted one: that address becomes req.ip.
 */
export function trustProxy(addr: string, i: number): boolean {
  if (i === 0) return true;
  return i === 1 && trustedRelayIps().has(normalizeIp(addr));
}

