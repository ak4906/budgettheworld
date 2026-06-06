# BudgetTheWorld

A personal iOS budgeting & cash-flow app (SwiftUI + SwiftData) built around one question:
**"Can I pay rent and still grow savings?"** — and it reframes every expense as the **work-hours**
it cost.

It models real money over time: an hourly wage with real pay periods and pay lag, a **dynamic**
checking balance, credit cards, recurring transactions, sinking funds, a day-by-day **forecast**,
a staged **emergency-fund** plan, an **8-metric** financial overview, and (in progress) **live bank
sync via Plaid**.

## Repository layout
- **`BudgetTheWorld/`** — the iOS app (Xcode project; SwiftUI + SwiftData; iOS 26).
- **`plaid-backend/`** — a tiny Cloudflare Worker that proxies Plaid. It holds the Plaid secret so
  the app never has to; exposes only `/link_token`, `/exchange`, `/sandbox_seed`, `/sync`, `/disconnect`.
- **`docs/`** — privacy policy, information-security policy, and data-retention policy.

## Features
- **Dashboard** — debt-aware "Safe to Spend" ring, "Free to Spend" pacing, next-paycheck breakdown
  (gross − taxes − 401(k) = take-home, plus employer match), rent readiness, credit cards, net worth.
- **Overview** — the eight core metrics: credit scores (FICO + Vantage), monthly income & expenses,
  cash flow, savings rate, debt balance, net worth, retirement contributions.
- **Forecast** — interactive day-by-day projection (Swift Charts), what-if scenarios, and a
  "when will I have $X?" finder.
- **Spending** — rich, editable transactions: expanded categories + free-text subcategory, merchant,
  and purpose tags, plus quick-add; recurring items materialize as individual editable rows.
- **Work** — a default schedule with per-day edits; learns your true take-home from logged paychecks.
- **Buckets** — sinking funds and a staged emergency-fund plan ($1k → 1 month → 3 months).
- **Bank sync (in progress)** — Plaid Transactions via the backend: real balance and up to 24 months
  of history; manual entry stays for one-offs. App can lock behind Face ID / passcode.

## Tech
SwiftUI · SwiftData · Swift Charts · LocalAuthentication · Cloudflare Workers + KV · Plaid (Transactions).

## Setup
- **App:** open `BudgetTheWorld/` in Xcode (iOS 26 SDK) and run.
- **Backend:** follow `plaid-backend/README.md`.

## Privacy & security
See `docs/`. Secrets are never committed or shipped in the app binary; the backend stores the Plaid
secret as an encrypted environment secret, and only an access token + sync cursor at rest.

_An open-source personal-finance project._
