# BudgetTheWorld — Plaid backend

A tiny Cloudflare Worker that holds your Plaid secret and feeds real transactions to the app.
Free tier is plenty for one person. ~10 minutes to set up.

## 0. Prerequisites
- A Plaid account (you have one): https://dashboard.plaid.com → **Team Settings → Keys**. Copy your
  **client_id** and your **Sandbox secret** (use Sandbox first; Production later).
- Node.js installed (`node -v`). Cloudflare's CLI (`wrangler`) is pulled in via npx — no global install needed.
- A free Cloudflare account (https://dash.cloudflare.com).

## 1. Get the code ready
```bash
cd plaid-backend
npm install
npx wrangler login          # opens a browser to authorize Cloudflare
```

## 2. Create the KV store (holds the access token + sync cursor)
```bash
npx wrangler kv namespace create BTW_KV
```
Copy the printed `id = "..."` into **wrangler.toml** (replace `REPLACE_WITH_KV_ID`).

## 3. Set your secrets (never committed, never in the app)
```bash
npx wrangler secret put PLAID_CLIENT_ID     # paste your Plaid client_id
npx wrangler secret put PLAID_SECRET        # paste your Plaid SANDBOX secret
npx wrangler secret put APP_SECRET          # invent a long random string; you'll paste this into the app too
```
(`PLAID_ENV` stays `sandbox` in wrangler.toml for now.)

## 4. Deploy
```bash
npx wrangler deploy
```
You'll get a URL like `https://budgettheworld-plaid.<you>.workers.dev`. That's your **Backend URL**.

## 5. Test it without the app (optional but reassuring)
Replace URL + APP_SECRET below:
```bash
# link a fake sandbox bank
curl -s -X POST https://budgettheworld-plaid.<you>.workers.dev/sandbox_seed \
  -H "Authorization: Bearer YOUR_APP_SECRET"
# -> {"ok":true}

# pull transactions (run twice if the first returns empty — sandbox needs a moment)
curl -s -X POST https://budgettheworld-plaid.<you>.workers.dev/sync \
  -H "Authorization: Bearer YOUR_APP_SECRET"
# -> {"added":[...],"modified":[],"removed":[]}
```

## 6. Hook up the app
In the app: **Settings → Bank Sync → Connect & sync (Plaid)**
- **Backend URL**: your `…workers.dev` URL
- **App secret**: the `APP_SECRET` you set
- Tap **Set up sandbox test data**, then **Sync now** — fake transactions flow into Spending.

## 7. Going live with Bank of America (Stage 2 — later)
1. Flip `PLAID_ENV = "production"` in wrangler.toml and set your **Production** secret
   (`npx wrangler secret put PLAID_SECRET`), then `npx wrangler deploy`.
2. The app needs **Plaid Link** added (Swift package `LinkKit`) to connect a real bank via OAuth —
   that's the next build step. The `/link_token` and `/exchange` endpoints are already here for it.

## Endpoints
| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/link_token` | — | `{ link_token }` (for Plaid Link, Stage 2) |
| POST | `/exchange` | `{ public_token }` | `{ ok }` — stores the access token |
| POST | `/sandbox_seed` | — | `{ ok }` — links a fake sandbox bank |
| POST | `/sync` | — | `{ added, modified, removed }` since last call |

All require header `Authorization: Bearer <APP_SECRET>`.
