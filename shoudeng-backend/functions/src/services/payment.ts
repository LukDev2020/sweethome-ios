import * as admin from "firebase-admin";
import * as fs from "fs";
import * as path from "path";
import {
  SignedDataVerifier, Environment, VerificationException, VerificationStatus,
} from "@apple/app-store-server-library";
import { v5 as uuidv5 } from "uuid";
import { insertConsentAudit } from "./bigquery";

const db = admin.firestore();

// Apple App Store Server API configuration
// Must equal PRODUCT_BUNDLE_IDENTIFIER of the ShouDeng target in project.yml.
export const APPLE_BUNDLE_ID = "com.shoudeng.app";

/**
 * Numeric Apple ID of the app (App Store Connect → App Information → Apple ID).
 * Set APPLE_APP_ID in functions/.env (see .env.example / README).
 *
 * TODO(owner): set APPLE_APP_ID before App Store release. Without it, Production
 * transactions still verify (the library only compares the app ID on notifications),
 * but Production Server Notifications are rejected with 401 and Apple retries them
 * until the value is configured.
 */
function configuredAppleAppId(): number | undefined {
  const raw = (process.env.APPLE_APP_ID || "").trim();
  const n = Number(raw);
  return raw && Number.isSafeInteger(n) && n > 0 ? n : undefined;
}

/** Sandbox (TestFlight, App Review, sandbox testers) is accepted unless APPLE_ALLOW_SANDBOX=false. */
function sandboxAllowed(): boolean {
  return process.env.APPLE_ALLOW_SANDBOX !== "false";
}

/** Unverified payload decoding is only ever allowed under jest or the emulator. */
function isLocalDev(): boolean {
  return process.env.FUNCTIONS_EMULATOR === "true" || !!process.env.JEST_WORKER_ID;
}

// Load Apple Root CA certificates (DER-encoded) for JWS signature verification.
// Downloaded from https://www.apple.com/certificateauthority/
function loadAppleRootCerts(): Buffer[] {
  const certsDir = path.join(__dirname, "..", "..", "certs");
  const certFiles = [
    "AppleIncRootCertificate.cer",
    "AppleRootCA-G2.cer",
    "AppleRootCA-G3.cer",
  ];
  const certs: Buffer[] = [];
  for (const file of certFiles) {
    const fullPath = path.join(certsDir, file);
    if (fs.existsSync(fullPath)) {
      certs.push(fs.readFileSync(fullPath));
    }
  }
  return certs;
}

interface AppleVerifiers {
  production: SignedDataVerifier;
  sandbox: SignedDataVerifier | null;
}

// Built lazily (env is read at first use) and reused across requests.
let _verifiers: AppleVerifiers | null | undefined;

function getVerifiers(): AppleVerifiers | null {
  if (_verifiers !== undefined) return _verifiers;
  const certs = loadAppleRootCerts();
  if (certs.length === 0) {
    console.error("[Payment] Apple root certs not found — signature verification unavailable");
    _verifiers = null;
    return null;
  }
  const appId = configuredAppleAppId();
  if (appId === undefined && !isLocalDev()) {
    console.error("[Payment] APPLE_APP_ID is not set — Production App Store notifications will be rejected until it is");
  }
  _verifiers = {
    // Production first (Apple's recommended order), Sandbox as the fallback.
    // appAppleId 0 when unset: the library only compares it on notifications.
    production: new SignedDataVerifier(certs, true, Environment.PRODUCTION, APPLE_BUNDLE_ID, appId ?? 0),
    sandbox: sandboxAllowed()
      ? new SignedDataVerifier(certs, true, Environment.SANDBOX, APPLE_BUNDLE_ID)
      : null,
  };
  return _verifiers;
}

/** Tests: re-read APPLE_APP_ID / APPLE_ALLOW_SANDBOX and rebuild the verifiers. */
export function resetAppleVerifiersForTests(): void {
  _verifiers = undefined;
}

/** Thrown when Apple-signed data can't be verified. `retryable` = Apple's OCSP/network check failed. */
export class AppleVerificationError extends Error {
  constructor(message: string, public readonly retryable = false) {
    super(message);
    this.name = "AppleVerificationError";
  }
}

function isWrongEnvironment(error: unknown): boolean {
  return error instanceof VerificationException &&
    (error.status === VerificationStatus.INVALID_ENVIRONMENT ||
     // Sandbox notifications carry no appAppleId, so the Production check fails on the app ID
     error.status === VerificationStatus.INVALID_APP_IDENTIFIER);
}

/**
 * Verify with the Production verifier, then (if the data says it's from another
 * environment) with Sandbox. Returns the decoded value and the environment it verified in.
 */
async function verifyWithFallback<T>(
  label: string,
  verify: (v: SignedDataVerifier) => Promise<T>,
  only?: Environment,
): Promise<{ value: T; environment: Environment }> {
  const verifiers = getVerifiers();
  if (!verifiers) throw new AppleVerificationError("Apple root certificates unavailable");
  const attempts: [Environment, SignedDataVerifier | null][] = [
    [Environment.PRODUCTION, verifiers.production],
    [Environment.SANDBOX, verifiers.sandbox],
  ];
  let lastError: unknown;
  for (const [environment, verifier] of attempts) {
    if (!verifier || (only && only !== environment)) continue;
    try {
      return { value: await verify(verifier), environment };
    } catch (error) {
      lastError = error;
      if (isWrongEnvironment(error)) continue;
      break;
    }
  }
  const retryable = lastError instanceof VerificationException &&
    lastError.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE;
  const status = lastError instanceof VerificationException ? ` (status ${lastError.status})` : "";
  console.warn(`[Payment] ${label} verification failed${status}`);
  throw new AppleVerificationError(`${label} verification failed`, retryable);
}

/** Decode a JWS payload WITHOUT verifying it — jest / emulator only. */
function decodeUnverified<T>(jws: string): T {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppleVerificationError("Invalid JWS format");
  return JSON.parse(Buffer.from(parts[1], "base64url").toString("utf-8")) as T;
}

/** Fields of a JWSTransactionDecodedPayload the backend uses. */
export interface AppleTransaction {
  bundleId?: string;
  productId?: string;
  originalTransactionId?: string;
  transactionId?: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: string;
}

/** Fields of a JWSRenewalInfoDecodedPayload the backend uses. */
interface AppleRenewalInfo {
  autoRenewProductId?: string;
  autoRenewStatus?: number;
  gracePeriodExpiresDate?: number;
}

async function decodeTransaction(jws: string, only?: Environment): Promise<{ tx: AppleTransaction; environment: string }> {
  if (getVerifiers() === null) {
    if (!isLocalDev()) throw new AppleVerificationError("Apple root certificates unavailable");
    console.warn("[Payment] Using payload-only verification (no cert chain)");
    const tx = decodeUnverified<AppleTransaction>(jws);
    if (tx.bundleId !== APPLE_BUNDLE_ID) throw new AppleVerificationError("Bundle ID mismatch");
    return { tx, environment: tx.environment || "Sandbox" };
  }
  const { value, environment } = await verifyWithFallback(
    "Transaction", (v) => v.verifyAndDecodeTransaction(jws), only);
  return { tx: value as unknown as AppleTransaction, environment };
}

async function decodeRenewalInfo(jws: string, only?: Environment): Promise<AppleRenewalInfo> {
  if (getVerifiers() === null) return decodeUnverified<AppleRenewalInfo>(jws);
  const { value } = await verifyWithFallback("Renewal info", (v) => v.verifyAndDecodeRenewalInfo(jws), only);
  return value as unknown as AppleRenewalInfo;
}

// ---------------------------------------------------------------------------
// Account binding (appAccountToken)
// ---------------------------------------------------------------------------

/**
 * Namespace of the per-user appAccountToken (UUID v5 of the uid). The iOS app derives
 * the same value (StoreKitManager.appAccountToken(for:)) — never change one without the other.
 */
export const APP_ACCOUNT_TOKEN_NAMESPACE = "8c5e3f7a-2b1d-4e6f-9a0c-3d7b5e1f4a28";

/** The appAccountToken the app sets on purchases made by this user. */
export function appAccountTokenFor(uid: string): string {
  return uuidv5(uid, APP_ACCOUNT_TOKEN_NAMESPACE);
}

/** Store the user's appAccountToken on the user doc (lets notifications find the user). */
export async function ensureAppAccountToken(uid: string): Promise<string> {
  const token = appAccountTokenFor(uid);
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (snap.exists && snap.data()?.appAccountToken !== token) {
    await ref.update({ appAccountToken: token });
  }
  return token;
}

/** Existing user whose appAccountToken this is, or null. */
export async function userForAppAccountToken(token: string | undefined): Promise<string | null> {
  if (!token) return null;
  const normalized = token.toLowerCase();
  const snap = await db.collection("users").where("appAccountToken", "==", normalized).limit(5).get();
  // The stored field is server-written, but re-derive to be sure it is that user's token
  const match = snap.docs.find((d) => appAccountTokenFor(d.id) === normalized);
  return match ? match.id : null;
}

/** originalTransactionId → owning uid. One Apple subscription unlocks one account. */
export const SUBSCRIPTION_OWNERS = "apple_subscription_owners";

export type ClaimResult = { ok: true } | { ok: false; reason: "OWNED_BY_OTHER_ACCOUNT" };

/**
 * Bind the transaction's subscription to `uid`, or refuse if it belongs to another
 * existing account:
 *  - appAccountToken set → it must be this user's (or a deleted account's).
 *  - no token → the originalTransactionId must not already be bound to another user.
 * A purchase made with this user's token takes over a binding made without one.
 */
export async function claimSubscription(uid: string, tx: AppleTransaction): Promise<ClaimResult> {
  const otid = tx.originalTransactionId;
  if (!otid) return { ok: true };
  const token = tx.appAccountToken?.toLowerCase();
  const tokenIsMine = !!token && token === appAccountTokenFor(uid);
  if (token && !tokenIsMine) {
    const owner = await userForAppAccountToken(token);
    if (owner && owner !== uid) return { ok: false, reason: "OWNED_BY_OTHER_ACCOUNT" };
  }

  const ownerRef = db.collection(SUBSCRIPTION_OWNERS).doc(otid);
  return db.runTransaction(async (t) => {
    const snap = await t.get(ownerRef);
    const previous = snap.exists ? (snap.data()?.uid as string | undefined) : undefined;
    let oldSub: FirebaseFirestore.DocumentSnapshot | null = null;
    if (previous && previous !== uid) {
      const previousUser = await t.get(db.collection("users").doc(previous));
      if (previousUser.exists) {
        if (!tokenIsMine) return { ok: false, reason: "OWNED_BY_OTHER_ACCOUNT" } as ClaimResult;
        oldSub = await t.get(db.collection("subscriptions").doc(previous));
      }
    }
    // (all reads above, writes below — Firestore transaction rule)
    const now = admin.firestore.Timestamp.now();
    t.set(ownerRef, { uid, appAccountToken: token ?? null, updatedAt: now });
    if (oldSub?.exists && oldSub.data()?.appleOriginalTransactionId === otid) {
      // Same Apple subscription, now bought into another account with its own token
      t.update(oldSub.ref, { status: "transferred", updatedAt: now });
    }
    return { ok: true } as ClaimResult;
  });
}

/** uid that owns this originalTransactionId, if known. */
async function ownerOfSubscription(otid: string): Promise<string | null> {
  const owner = await db.collection(SUBSCRIPTION_OWNERS).doc(otid).get();
  if (owner.exists && owner.data()?.uid) return owner.data()!.uid as string;
  const subs = await db.collection("subscriptions").where("appleOriginalTransactionId", "==", otid).limit(1).get();
  return subs.empty ? null : subs.docs[0].id;
}

// Subscription plan definitions — single source of truth for plan IDs.
// Product IDs must match App Store Connect and StoreKitManager.productIds (iOS).
// Prices are reference values only; App Store Connect pricing is authoritative.
export const PLANS = {
  free: {
    id: "free",
    name: "免费版",
    prices: { monthly: { CNY: 0, USD: 0 }, yearly: { CNY: 0, USD: 0 } },
    ttlDays: { heartbeat: 7, location: 7, checkin: 30 },
    maxGuardians: 1,
    maxProtected: 1,
    features: ["basic_sos", "1_guardian", "24h_timeline", "checkin"],
  },
  single: {
    id: "single",
    name: "单人关注版",
    prices: { monthly: { CNY: 10, USD: 1.49 }, yearly: { CNY: 96, USD: 14.99 } },
    appleProductIds: [
      "com.shoudeng.app.single.monthly",
      "com.shoudeng.app.single.yearly",
    ],
    ttlDays: { heartbeat: 90, location: 90, checkin: -1 },
    maxGuardians: 3,
    maxProtected: 1,
    features: [
      "basic_sos", "checkin", "3_guardians", "90d_timeline",
      "duty_schedule", "voice_call_escalation", "export_pdf",
    ],
  },
  family: {
    id: "family",
    name: "家庭版",
    prices: { monthly: { CNY: 30, USD: 4.99 }, yearly: { CNY: 288, USD: 49.99 } },
    appleProductIds: [
      "com.shoudeng.app.family.monthly",
      "com.shoudeng.app.family.yearly",
    ],
    ttlDays: { heartbeat: 180, location: 180, checkin: -1 },
    maxGuardians: -1,
    maxProtected: 4,
    features: [
      "basic_sos", "checkin", "unlimited_guardians", "180d_timeline",
      "duty_schedule", "voice_call_escalation", "sms_fallback",
      "export_pdf", "family_dashboard", "location_history_export",
    ],
  },
  ultimate: {
    id: "ultimate",
    name: "企业版",
    prices: { monthly: { CNY: 128, USD: 19.99 }, yearly: { CNY: 1228, USD: 199.99 } },
    appleProductIds: [
      "com.shoudeng.app.ultimate.monthly",
      "com.shoudeng.app.ultimate.yearly",
    ],
    ttlDays: { heartbeat: 365, location: 365, checkin: -1 },
    maxGuardians: -1,
    maxProtected: -1,
    features: [
      "basic_sos", "checkin", "unlimited_guardians", "unlimited_protected",
      "365d_timeline", "duty_schedule", "voice_call_escalation", "sms_fallback",
      "export_pdf", "family_dashboard", "location_history_export",
      "priority_support",
    ],
  },
} as const;

export type PlanId = keyof typeof PLANS;

/**
 * Map an App Store product ID to its plan. Returns null for unknown products.
 */
export function mapProductToPlan(productId: string | undefined): PlanId | null {
  if (!productId) return null;
  for (const [planId, plan] of Object.entries(PLANS)) {
    if ("appleProductIds" in plan && (plan.appleProductIds as readonly string[]).includes(productId)) {
      return planId as PlanId;
    }
  }
  return null;
}

export type SubscriptionStatus =
  | "active" | "expired" | "cancelled" | "grace_period" | "billing_retry" | "transferred";

export interface SubscriptionDoc {
  userId: string;
  planId: PlanId;
  appleOriginalTransactionId: string | null;
  appleProductId: string | null;
  appAccountToken?: string | null;
  environment?: string | null;
  /** "cancelled" = refunded or revoked; "transferred" = the Apple subscription moved to another account */
  status: SubscriptionStatus;
  currentPeriodStart: FirebaseFirestore.Timestamp;
  currentPeriodEnd: FirebaseFirestore.Timestamp;
  gracePeriodEnd?: FirebaseFirestore.Timestamp | null;
  /** Plan of a pending downgrade (takes effect at the next renewal) */
  pendingPlanId?: PlanId | null;
  /** purchaseDate of the newest transaction applied — older ones don't overwrite it */
  latestPurchaseDate?: FirebaseFirestore.Timestamp | null;
  cancelledAt: FirebaseFirestore.Timestamp | null;
  autoRenew: boolean;
  createdAt: FirebaseFirestore.Timestamp;
  updatedAt: FirebaseFirestore.Timestamp;
}

function toDate(v: unknown): Date | null {
  const d = (v as { toDate?: () => Date } | null | undefined)?.toDate?.();
  return d instanceof Date ? d : null;
}

/**
 * Whether a subscription doc grants its paid plan right now. Refunded/revoked
 * ("cancelled"), expired, billing-retry (no grace period) and transferred
 * subscriptions don't; a billing grace period does until it ends.
 */
export function hasPaidAccess(
  data: Partial<SubscriptionDoc> | FirebaseFirestore.DocumentData | undefined,
  now: Date = new Date(),
): boolean {
  if (!data || data.planId === "free" || !(data.planId in PLANS)) return false;
  switch (data.status) {
    case "active": {
      const end = toDate(data.currentPeriodEnd);
      return !end || end > now;
    }
    case "grace_period": {
      const graceEnd = toDate(data.gracePeriodEnd);
      return !graceEnd || graceEnd > now;
    }
    default:
      return false;
  }
}

export interface VerifiedReceipt {
  valid: boolean;
  productId?: string;
  originalTransactionId?: string;
  expiresDate?: Date;
  revocationDate?: Date;
  appAccountToken?: string;
  environment?: string;
  transaction?: AppleTransaction;
  error?: string;
  /** Apple's online certificate check failed — the client should try again later */
  retryable?: boolean;
}

/**
 * Verify an Apple App Store signed transaction (JWS): certificate chain, signature,
 * bundle ID and environment (Production first, then Sandbox).
 * Payload-only decoding is used only under jest / the emulator when certs are absent.
 */
export async function verifyAppleReceipt(signedTransaction: string): Promise<VerifiedReceipt> {
  if (typeof signedTransaction !== "string" || signedTransaction.split(".").length !== 3) {
    return { valid: false, error: "Invalid JWS format" };
  }
  try {
    const { tx, environment } = await decodeTransaction(signedTransaction);
    return {
      valid: true,
      productId: tx.productId,
      originalTransactionId: tx.originalTransactionId,
      expiresDate: tx.expiresDate ? new Date(tx.expiresDate) : undefined,
      revocationDate: tx.revocationDate ? new Date(tx.revocationDate) : undefined,
      appAccountToken: tx.appAccountToken,
      environment,
      transaction: tx,
    };
  } catch (error) {
    if (error instanceof AppleVerificationError) {
      return { valid: false, error: error.message === "Bundle ID mismatch" ? error.message : "Failed to verify receipt", retryable: error.retryable };
    }
    console.error("[Payment] Receipt verification failed:", error);
    return { valid: false, error: "Failed to verify receipt" };
  }
}

/**
 * Write the subscription described by a verified transaction to subscriptions/{uid}.
 * Status follows the transaction (revoked → cancelled, past expiry → expired).
 * A transaction older than the one already applied for the same subscription is ignored.
 */
export async function applyTransaction(params: {
  userId: string;
  transaction: AppleTransaction;
  environment?: string | null;
  renewal?: AppleRenewalInfo | null;
}): Promise<{ applied: boolean; planId: PlanId | null }> {
  const { userId, transaction: tx } = params;
  const planId = mapProductToPlan(tx.productId);
  if (!planId) return { applied: false, planId: null };

  const ref = db.collection("subscriptions").doc(userId);
  const existingSnap = await ref.get();
  const existing = existingSnap.exists ? (existingSnap.data() as SubscriptionDoc) : null;
  const sameSubscription = existing?.appleOriginalTransactionId === (tx.originalTransactionId ?? null);
  const appliedPurchase = toDate(existing?.latestPurchaseDate)?.getTime();
  if (sameSubscription && appliedPurchase && tx.purchaseDate && tx.purchaseDate < appliedPurchase) {
    return { applied: false, planId }; // stale (e.g. an old renewal replayed after an upgrade)
  }

  const nowMs = Date.now();
  const now = admin.firestore.Timestamp.now();
  const expiresMs = tx.expiresDate ?? nowMs + 30 * 24 * 60 * 60 * 1000;
  const status: SubscriptionStatus = tx.revocationDate ? "cancelled" : expiresMs <= nowMs ? "expired" : "active";
  const renewal = params.renewal;
  const pendingPlan = renewal?.autoRenewProductId ? mapProductToPlan(renewal.autoRenewProductId) : null;

  const subDoc: Partial<SubscriptionDoc> = {
    userId,
    planId,
    appleOriginalTransactionId: tx.originalTransactionId ?? null,
    appleProductId: tx.productId ?? null,
    appAccountToken: tx.appAccountToken?.toLowerCase() ?? null,
    environment: params.environment ?? tx.environment ?? null,
    status,
    currentPeriodStart: tx.purchaseDate ? admin.firestore.Timestamp.fromDate(new Date(tx.purchaseDate)) : now,
    currentPeriodEnd: admin.firestore.Timestamp.fromDate(new Date(expiresMs)),
    gracePeriodEnd: null,
    pendingPlanId: pendingPlan && pendingPlan !== planId ? pendingPlan : null,
    latestPurchaseDate: tx.purchaseDate ? admin.firestore.Timestamp.fromDate(new Date(tx.purchaseDate)) : null,
    cancelledAt: tx.revocationDate ? admin.firestore.Timestamp.fromDate(new Date(tx.revocationDate)) : null,
    autoRenew: renewal?.autoRenewStatus !== undefined
      ? renewal.autoRenewStatus === 1
      : (sameSubscription && existing ? existing.autoRenew : true),
    updatedAt: now,
    ...(existing ? {} : { createdAt: now }),
  };
  await ref.set(subDoc, { merge: true });

  if (status === "active" && !(existing && sameSubscription && hasPaidAccess(existing))) {
    await insertConsentAudit({
      userId,
      consentType: "subscription",
      action: "granted",
      grantedTo: "system",
      detail: `Subscription activated: ${planId}`,
    });
  }
  return { applied: true, planId };
}

/**
 * Get the subscription for a user.
 * Returns the plan details, or the free tier when there is no subscription or it
 * no longer grants access (expired, refunded/revoked, billing retry, transferred).
 */
export async function getSubscription(userId: string): Promise<{
  planId: PlanId;
  status: string;
  expiresAt: string | null;
  features: readonly string[];
  ttlDays: { heartbeat: number; location: number; checkin: number };
}> {
  const subDoc = await db.collection("subscriptions").doc(userId).get();

  if (!subDoc.exists) {
    return {
      planId: "free",
      status: "active",
      expiresAt: null,
      features: PLANS.free.features,
      ttlDays: PLANS.free.ttlDays,
    };
  }

  const data = subDoc.data() as SubscriptionDoc;
  const periodEnd = toDate(data.currentPeriodEnd);

  if (!hasPaidAccess(data)) {
    let status: string = data.status;
    if (data.status === "active" || data.status === "grace_period") {
      // Period (or grace period) ran out without a notification saying so
      status = "expired";
      await subDoc.ref.update({ status: "expired", updatedAt: admin.firestore.Timestamp.now() });
    }
    return {
      planId: "free",
      status,
      expiresAt: periodEnd ? periodEnd.toISOString() : null,
      features: PLANS.free.features,
      ttlDays: PLANS.free.ttlDays,
    };
  }

  const plan = PLANS[data.planId];

  return {
    planId: data.planId,
    status: data.status,
    expiresAt: periodEnd ? periodEnd.toISOString() : null,
    features: plan.features,
    ttlDays: plan.ttlDays,
  };
}

// ---------------------------------------------------------------------------
// App Store Server Notifications V2
// ---------------------------------------------------------------------------

export type NotificationOutcome = "applied" | "ignored" | "unmatched";

interface DecodedNotification {
  notificationType?: string;
  subtype?: string;
  data?: { signedTransactionInfo?: string; signedRenewalInfo?: string; environment?: string };
}

async function decodeNotification(signedPayload: string): Promise<{ payload: DecodedNotification; environment?: Environment }> {
  if (getVerifiers() === null) {
    if (!isLocalDev()) throw new AppleVerificationError("Apple root certificates unavailable");
    return { payload: decodeUnverified<DecodedNotification>(signedPayload) };
  }
  const { value, environment } = await verifyWithFallback(
    "Notification", (v) => v.verifyAndDecodeNotification(signedPayload));
  return { payload: value as unknown as DecodedNotification, environment };
}

/**
 * Handle an App Store Server Notification V2.
 * Throws AppleVerificationError when the payload can't be verified (the webhook then
 * answers non-2xx so Apple retries); returns what was done otherwise.
 */
export async function handleAppleNotification(signedPayload: string): Promise<{
  outcome: NotificationOutcome;
  notificationType?: string;
  userId?: string;
}> {
  const { payload, environment } = await decodeNotification(signedPayload);
  const notificationType = payload.notificationType ?? "";
  const subtype = payload.subtype ?? "";
  const transactionInfo = payload.data?.signedTransactionInfo;

  if (!transactionInfo) {
    // TEST, summaries (RENEWAL_EXTENSION), consumption requests…
    console.log(`[Payment] Notification ${notificationType} has no transaction — nothing to do`);
    return { outcome: "ignored", notificationType };
  }

  // Nested JWS: verified in the same environment as the notification
  const { tx } = await decodeTransaction(transactionInfo, environment);
  const renewal = payload.data?.signedRenewalInfo
    ? await decodeRenewalInfo(payload.data.signedRenewalInfo, environment)
    : null;
  const otid = tx.originalTransactionId;
  if (!otid) return { outcome: "ignored", notificationType };

  // Whose subscription is it? Known binding first, else the purchase's appAccountToken
  let userId = await ownerOfSubscription(otid);
  if (!userId) {
    userId = await userForAppAccountToken(tx.appAccountToken);
    if (!userId) {
      console.warn(`[Payment] ${notificationType}: no account for tx ${otid}`);
      return { outcome: "unmatched", notificationType };
    }
    const claim = await claimSubscription(userId, tx);
    if (!claim.ok) return { outcome: "unmatched", notificationType };
  }

  if (!(await db.collection("users").doc(userId).get()).exists) {
    console.warn(`[Payment] ${notificationType}: account of tx ${otid} was deleted`);
    return { outcome: "unmatched", notificationType };
  }

  const subRef = db.collection("subscriptions").doc(userId);
  const envName = environment ?? tx.environment ?? null;
  // Notifications can arrive before the app reports the purchase: start from the transaction
  if (!(await subRef.get()).exists) {
    await applyTransaction({ userId, transaction: tx, environment: envName, renewal });
  }
  const now = admin.firestore.Timestamp.now();
  const fromTransaction = () => applyTransaction({ userId: userId!, transaction: tx, environment: envName, renewal });
  const pendingFromRenewal = (): PlanId | null =>
    renewal?.autoRenewProductId ? mapProductToPlan(renewal.autoRenewProductId) : null;

  switch (notificationType) {
    case "SUBSCRIBED":      // INITIAL_BUY / RESUBSCRIBE
    case "DID_RENEW":
      await fromTransaction();
      break;

    case "REFUND_REVERSED": // the refunded transaction is valid again
      await applyTransaction({
        userId, transaction: { ...tx, revocationDate: undefined }, environment: envName, renewal,
      });
      break;

    case "OFFER_REDEEMED":
      if (subtype === "DOWNGRADE") {
        await subRef.update({ pendingPlanId: pendingFromRenewal(), updatedAt: now });
      } else {
        await fromTransaction();
      }
      break;

    case "DID_CHANGE_RENEWAL_PREF":
      if (subtype === "UPGRADE") {
        // Upgrades take effect immediately; the transaction is for the new product
        await fromTransaction();
      } else if (subtype === "DOWNGRADE") {
        // Takes effect at the next renewal; keep the current plan until then
        await subRef.update({ pendingPlanId: pendingFromRenewal(), updatedAt: now });
      } else {
        // No subtype: the user cancelled a pending downgrade
        await subRef.update({ pendingPlanId: null, updatedAt: now });
      }
      break;

    case "DID_CHANGE_RENEWAL_STATUS":
      await subRef.update({
        autoRenew: subtype !== "AUTO_RENEW_DISABLED",
        updatedAt: now,
      });
      break;

    case "EXPIRED":
    case "GRACE_PERIOD_EXPIRED":
      await subRef.update({ status: "expired", gracePeriodEnd: null, updatedAt: now });
      break;

    case "DID_FAIL_TO_RENEW":
      await subRef.update({
        status: subtype === "GRACE_PERIOD" ? "grace_period" : "billing_retry",
        gracePeriodEnd: subtype === "GRACE_PERIOD" && renewal?.gracePeriodExpiresDate
          ? admin.firestore.Timestamp.fromDate(new Date(renewal.gracePeriodExpiresDate))
          : null,
        updatedAt: now,
      });
      break;

    case "REFUND":
    case "REVOKE":          // Family Sharing access revoked
      await subRef.update({
        status: "cancelled",
        cancelledAt: tx.revocationDate ? admin.firestore.Timestamp.fromDate(new Date(tx.revocationDate)) : now,
        updatedAt: now,
      });
      break;

    default:
      console.log(`[Payment] Unhandled notification: ${notificationType}`);
      return { outcome: "ignored", notificationType, userId };
  }

  console.log(`[Payment] ${notificationType}${subtype ? `/${subtype}` : ""} applied for tx ${otid}`);
  return { outcome: "applied", notificationType, userId };
}
