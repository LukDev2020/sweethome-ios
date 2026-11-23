# Per-person pricing (seats)

From build 63, what the app sells is priced per person. Single / Family (and their
lifetime purchases) keep working for the people who bought them; they are no longer
shown to anyone else.

## Prices (USD list)

| Seat | Monthly | Yearly |
|---|---|---|
| Each person looked after (protected) | $1.99 | $19.99 |
| First person looking after (guardian) | $2.99 | $29.99 |
| Each further guardian (brother, sister) | +$1.00 | +$9.99 |
| "I'm looked after too" (the payer has both roles) | +$1.00 | +$9.99 |

Charged up to 4 people looked after and 3 looking after; beyond that people are free and
there is no limit. SOS, silent SOS, duress code, tracker detection, check-in and SMS /
call escalation stay free on every plan.

| Family | Seats | Monthly | Yearly |
|---|---|---|---|
| 1 child + 1 parent | 1 + 1 | $4.99 | $49.99 |
| 1 child + 2 parents | 2 + 1 | $6.99 | $69.99 |
| 2 children + 2 parents | 2 + 2 | $7.99 | $79.99 |
| 1v2, payer looked after too | 2 + 1 + both roles | $7.99 | $79.99 |

The per-person plan includes everything Family included (180-day history, PDF reports,
duty schedule, family dashboard, location history export).

## How it is sold

The App Store can't sell a quantity of a subscription, so the products are **price
levels**. The app works out the price of the seats chosen, buys the cheapest level at
or above it, then tells the server the seats (`PUT /v1/payment/seats`). The server keeps
them if the level pays for them, and uses them as the family's limits (an invite past
the seats is refused, and the payer is offered "add a seat"). Changing seats later is an
App Store upgrade / downgrade between levels (Apple prorates); seats can't go below the
people already in the family.

Prices live in one place on the server (`shoudeng-backend/functions/src/services/seats.ts`,
served by `GET /v1/payment/seats/pricing`). They can change without new products as long
as every total still lands on a level.

## App Store Connect: products to create

Put all 20 in the **existing subscription group "ShouDeng Subscriptions"** (22593050),
so that someone on Single / Family who switches is moved over (upgrade / crossgrade)
instead of paying twice. **Family Sharing: off** (a seat is one family's, not shared
with the buyer's Apple family). No free trial.

Level ordering in the group (set 2026-11-23, one product per level, highest first):
yearly 139.99, monthly 13.99, yearly 129.99, monthly 12.99, … yearly 49.99, monthly 4.99
(levels 1–20), then Family Monthly, Family Yearly, Essential Monthly, Essential Yearly
(21–24). Each yearly sits just above the monthly for the same seats, so adding people is
always an upgrade (immediate, prorated), monthly → yearly for the same seats is an
upgrade, and yearly → monthly or fewer people is a downgrade (at renewal). In the App
Store Connect level editor, dropping a row onto another row puts both in one level; drop
into the thin strip between rows to make a new level.

| Product ID | Reference name | Duration | US price |
|---|---|---|---|
| com.shoudeng.app.seats.monthly.499 | Seats Monthly 4.99 | 1 month | $4.99 |
| com.shoudeng.app.seats.monthly.599 | Seats Monthly 5.99 | 1 month | $5.99 |
| com.shoudeng.app.seats.monthly.699 | Seats Monthly 6.99 | 1 month | $6.99 |
| com.shoudeng.app.seats.monthly.799 | Seats Monthly 7.99 | 1 month | $7.99 |
| com.shoudeng.app.seats.monthly.899 | Seats Monthly 8.99 | 1 month | $8.99 |
| com.shoudeng.app.seats.monthly.999 | Seats Monthly 9.99 | 1 month | $9.99 |
| com.shoudeng.app.seats.monthly.1099 | Seats Monthly 10.99 | 1 month | $10.99 |
| com.shoudeng.app.seats.monthly.1199 | Seats Monthly 11.99 | 1 month | $11.99 |
| com.shoudeng.app.seats.monthly.1299 | Seats Monthly 12.99 | 1 month | $12.99 |
| com.shoudeng.app.seats.monthly.1399 | Seats Monthly 13.99 | 1 month | $13.99 |
| com.shoudeng.app.seats.yearly.4999 | Seats Yearly 49.99 | 1 year | $49.99 |
| com.shoudeng.app.seats.yearly.5999 | Seats Yearly 59.99 | 1 year | $59.99 |
| com.shoudeng.app.seats.yearly.6999 | Seats Yearly 69.99 | 1 year | $69.99 |
| com.shoudeng.app.seats.yearly.7999 | Seats Yearly 79.99 | 1 year | $79.99 |
| com.shoudeng.app.seats.yearly.8999 | Seats Yearly 89.99 | 1 year | $89.99 |
| com.shoudeng.app.seats.yearly.9999 | Seats Yearly 99.99 | 1 year | $99.99 |
| com.shoudeng.app.seats.yearly.10999 | Seats Yearly 109.99 | 1 year | $109.99 |
| com.shoudeng.app.seats.yearly.11999 | Seats Yearly 119.99 | 1 year | $119.99 |
| com.shoudeng.app.seats.yearly.12999 | Seats Yearly 129.99 | 1 year | $129.99 |
| com.shoudeng.app.seats.yearly.13999 | Seats Yearly 139.99 | 1 year | $139.99 |

Display name / description (per localization), for example:

- en: "Family seats" / "Pay per person: the family you look after and the people looking after them."
- zh-Hans: "按人数守护" / "按人数付费：被守护的家人和守护的人。"
- zh-Hant: "按人數守護" / "按人數付費：被守護的家人和守護的人。"
- fr: "Places famille" / "Payez par personne : les proches suivis et ceux qui veillent sur eux."
- ja: "人数プラン" / "人数分のお支払い：見守られる家族と見守る人。"

Each product needs the review screenshot (the paywall) and the same review note:
"Price levels of one per-person plan. The app picks the level from the number of people
the user chooses on the paywall (Settings → Plan)."

**China storefront:** suggested ¥12 per guardian and ¥6 per person looked after, i.e.
levels of about ¥18 / ¥24 / ¥30 … — set the CNY price of each level by hand.

## Before build 63 ships

1. Create the 20 products above (status "Ready to Submit"), submitted with build 63.
2. Deploy the backend (adds the `seats` plan, `GET /v1/payment/seats/pricing`,
   `PUT /v1/payment/seats`). Safe to deploy before: older apps don't use it.
3. Until the products exist, the paywall shows "Couldn't load plans" with Retry.
