// ---------------------------------------------------------------------------
// Per-person pricing ("seats", docs/pricing/SEATS.md)
// ---------------------------------------------------------------------------
//
// The payer (usually the adult child) pays by the people in the family:
//   - each person looked after ("protected" seat)    $1.99 / month   ($19.99 / year)
//   - the first person looking after (guardian seat) $2.99 / month   ($29.99 / year)
//   - each further guardian (a brother, a sister)    +$1   / month   (+$9.99 / year)
//   - "I'm looked after too" (the payer, both roles)  +$1   / month   (+$9.99 / year)
// Capped: protected seats are charged up to 4, guardian seats up to 3; more people
// beyond that cost nothing (and have no limit).
//
// The App Store can't sell a quantity of a subscription, so the products are price
// levels in one subscription group ("Family seats"): $4.99 … $13.99 a month and
// $49.99 … $139.99 a year. The app buys the cheapest level at or above the price of
// the seats chosen and tells the server the seats (PUT /v1/payment/seats); the server
// keeps them if the level covers them. Moving between levels is an App Store
// upgrade / downgrade (prorated by Apple). Changing the prices here needs no new
// products as long as a total still lands on a level.
//
// Pure functions only (no Firestore): unit-tested, and mirrored in the app
// (StoreKitManager.swift, SeatPricing) with the numbers from GET /v1/payment/seats/pricing.

export type SeatPeriod = "monthly" | "yearly";

export interface SeatConfig {
  /** People looked after */
  protected: number;
  /** People looking after, the payer included */
  guardians: number;
  /** The payer is looked after too */
  dual: boolean;
}

/** Cents (USD list prices; other storefronts use the App Store's price for the level) */
export const SEAT_PRICES: Record<SeatPeriod, { protected: number; firstGuardian: number; extraGuardian: number; dual: number }> = {
  monthly: { protected: 199, firstGuardian: 299, extraGuardian: 100, dual: 100 },
  yearly: { protected: 1999, firstGuardian: 2999, extraGuardian: 999, dual: 999 },
};

/** Charged up to these counts; beyond them, free and unlimited */
export const SEAT_CAPS = { protected: 4, guardians: 3 } as const;

/** Most people a config may name (a sanity bound, not a price rule) */
export const SEAT_MAX = { protected: 12, guardians: 8 } as const;

/** Price levels on sale, in cents */
export const SEAT_LEVELS: Record<SeatPeriod, number[]> = {
  monthly: [499, 599, 699, 799, 899, 999, 1099, 1199, 1299, 1399],
  yearly: [4999, 5999, 6999, 7999, 8999, 9999, 10999, 11999, 12999, 13999],
};

const PRODUCT_PREFIX = "com.shoudeng.app.seats";

export function seatProductId(period: SeatPeriod, cents: number): string {
  return `${PRODUCT_PREFIX}.${period}.${cents}`;
}

/** Every seat product, both periods */
export const SEAT_PRODUCT_IDS: readonly string[] = (["monthly", "yearly"] as SeatPeriod[])
  .flatMap((p) => SEAT_LEVELS[p].map((c) => seatProductId(p, c)));

/** The level a seat product sells (null: not a seat product) */
export function seatLevelOf(productId: string | null | undefined): { period: SeatPeriod; cents: number } | null {
  if (!productId || !SEAT_PRODUCT_IDS.includes(productId)) return null;
  const [period, cents] = productId.slice(PRODUCT_PREFIX.length + 1).split(".");
  return { period: period as SeatPeriod, cents: Number(cents) };
}

/** Why a config can't be used (null: fine) */
export function invalidSeatConfig(c: unknown): string | null {
  if (!c || typeof c !== "object") return "seats must be an object";
  const { protected: p, guardians: g, dual } = c as Record<string, unknown>;
  if (!Number.isInteger(p) || (p as number) < 1 || (p as number) > SEAT_MAX.protected) {
    return `protected must be a whole number from 1 to ${SEAT_MAX.protected}`;
  }
  if (!Number.isInteger(g) || (g as number) < 1 || (g as number) > SEAT_MAX.guardians) {
    return `guardians must be a whole number from 1 to ${SEAT_MAX.guardians}`;
  }
  if (typeof dual !== "boolean") return "dual must be true or false";
  return null;
}

/** List price of a config, in cents */
export function seatPriceCents(c: SeatConfig, period: SeatPeriod): number {
  const p = SEAT_PRICES[period];
  const protectedSeats = Math.min(c.protected, SEAT_CAPS.protected);
  const extraGuardians = Math.min(c.guardians, SEAT_CAPS.guardians) - 1;
  return protectedSeats * p.protected + p.firstGuardian + extraGuardians * p.extraGuardian + (c.dual ? p.dual : 0);
}

/** The cheapest level that covers a config (null: none does) */
export function seatLevelFor(c: SeatConfig, period: SeatPeriod): number | null {
  const price = seatPriceCents(c, period);
  return SEAT_LEVELS[period].find((cents) => cents >= price) ?? null;
}

export function seatProductFor(c: SeatConfig, period: SeatPeriod): string | null {
  const level = seatLevelFor(c, period);
  return level === null ? null : seatProductId(period, level);
}

/** Whether the level a product sells pays for a config */
export function productCovers(productId: string | null | undefined, c: SeatConfig): boolean {
  const level = seatLevelOf(productId);
  return !!level && seatPriceCents(c, level.period) <= level.cents;
}

/**
 * The config a level actually pays for: the one chosen, trimmed when the level is lower
 * (an App Store downgrade took effect): extra guardians first, then "looked after too",
 * then people looked after, down to 1 + 1.
 */
export function fitSeats(c: SeatConfig, productId: string | null | undefined): SeatConfig {
  const level = seatLevelOf(productId);
  if (!level) return { protected: 1, guardians: 1, dual: false };
  const fitted = { ...c };
  while (seatPriceCents(fitted, level.period) > level.cents) {
    if (Math.min(fitted.guardians, SEAT_CAPS.guardians) > 1) fitted.guardians = Math.min(fitted.guardians, SEAT_CAPS.guardians) - 1;
    else if (fitted.dual) fitted.dual = false;
    else if (Math.min(fitted.protected, SEAT_CAPS.protected) > 1) fitted.protected = Math.min(fitted.protected, SEAT_CAPS.protected) - 1;
    else break;
  }
  return fitted;
}

/** Household limits for a config (-1: no limit, at or above the cap) */
export function seatLimits(c: SeatConfig): { maxProtected: number; maxGuardians: number } {
  return {
    maxProtected: c.protected >= SEAT_CAPS.protected ? -1 : c.protected,
    maxGuardians: c.guardians >= SEAT_CAPS.guardians ? -1 : c.guardians,
  };
}

/** Until the app reports the seats chosen: the least a level could be for */
export const DEFAULT_SEATS: SeatConfig = { protected: 1, guardians: 1, dual: false };

/** What the app needs to price seats (GET /v1/payment/seats/pricing) */
export function seatPricing() {
  return {
    prices: SEAT_PRICES,
    caps: SEAT_CAPS,
    max: SEAT_MAX,
    levels: SEAT_LEVELS,
    productIds: SEAT_PRODUCT_IDS,
  };
}
