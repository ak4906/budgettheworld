// worker.js — BudgetTheWorld Plaid backend (Cloudflare Worker)
//
// Holds your Plaid secret (never shipped in the app) and exposes a tiny API the app calls:
//   POST /link_token     -> { link_token }        (Stage 2: open Plaid Link in the app)
//   POST /exchange       <- { public_token }       (Stage 2: store the access_token)
//   POST /sandbox_seed   -> { ok: true }           (Stage 1: provision a fake bank to test with)
//   POST /sync           -> { added, modified, removed }   (the delta since last sync)
//
// All requests must send  Authorization: Bearer <APP_SECRET>.
// State (access_token + sync cursor) lives in a KV namespace bound as BTW_KV.

const PLAID_HOSTS = {
  sandbox: "https://sandbox.plaid.com",
  development: "https://development.plaid.com",
  production: "https://production.plaid.com",
};

export default {
  async fetch(request, env) {
    try {
      const url = new URL(request.url);

      // Public, no auth: universal-link association file so iOS opens the app on the OAuth redirect.
      if (url.pathname === "/.well-known/apple-app-site-association") {
        return new Response(JSON.stringify({
          applinks: { apps: [], details: [{ appID: "SELN5644JH.cometzfly.BudgetTheWorld", paths: ["/plaid-oauth*"] }] }
        }), { headers: { "Content-Type": "application/json" } });
      }
      // OAuth landing page (the universal link normally opens the app; this is the visible fallback).
      if (url.pathname === "/plaid-oauth") {
        return new Response(
          "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'><body style='font-family:-apple-system;text-align:center;padding:3rem'>Return to BudgetTheWorld to finish connecting your bank.</body>",
          { headers: { "Content-Type": "text/html" } }
        );
      }

      if (request.method !== "POST") return json({ error: "POST only" }, 405);
      // Multi-user: APP_SECRET is a comma-separated allow-list (one secret per person sharing this
      // worker). We namespace all stored state by a hash of the caller's secret, so two people who
      // connect their banks never see each other's data.
      const authHeader = request.headers.get("Authorization") || "";
      const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
      if (!token || !allowedSecrets(env).includes(token)) {
        return json({ error: "unauthorized" }, 401);
      }
      const userKey = await sha256hex(token);
      const path = url.pathname;
      const host = PLAID_HOSTS[env.PLAID_ENV || "sandbox"] || PLAID_HOSTS.sandbox;

      switch (path) {
        case "/link_token": return await createLinkToken(env, host);
        case "/exchange": return await exchange(request, env, host, userKey);
        case "/sandbox_seed": return await sandboxSeed(env, host, userKey);
        case "/sync": return await sync(env, host, userKey);
        case "/disconnect": return await disconnect(env, host, userKey);
        case "/resync": return await resync(env, userKey);
        default: return json({ error: "not found" }, 404);
      }
    } catch (e) {
      return json({ error: String(e && e.message ? e.message : e) }, 500);
    }
  },
};

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Comma-separated allow-list of app secrets — one per person sharing this worker.
function allowedSecrets(env) {
  return (env.APP_SECRET || "").split(",").map((s) => s.trim()).filter(Boolean);
}

// Per-user namespace derived from the secret, so each person's token + cursor stay isolated.
async function sha256hex(s) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
const tokenKey = (u) => `access_token:${u}`;
const cursorKey = (u) => `cursor:${u}`;

async function plaid(host, path, env, body) {
  const res = await fetch(host + path, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ client_id: env.PLAID_CLIENT_ID, secret: env.PLAID_SECRET, ...body }),
  });
  const data = await res.json();
  if (!res.ok) throw new Error(data.error_message || data.error_code || JSON.stringify(data));
  return data;
}

async function createLinkToken(env, host) {
  const body = {
    user: { client_user_id: "budgettheworld-user" },
    client_name: "BudgetTheWorld",
    products: ["transactions"],
    transactions: { days_requested: 730 }, // pull up to ~24 months of history on connect
    country_codes: ["US"],
    language: "en",
  };
  // Required for OAuth banks (e.g. Bank of America). Set PLAID_REDIRECT_URI only AFTER registering
  // the same URL in the Plaid dashboard's "Allowed redirect URIs".
  if (env.PLAID_REDIRECT_URI) body.redirect_uri = env.PLAID_REDIRECT_URI;
  const data = await plaid(host, "/link/token/create", env, body);
  return json({ link_token: data.link_token });
}

async function exchange(request, env, host, userKey) {
  const { public_token } = await request.json();
  if (!public_token) return json({ error: "missing public_token" }, 400);
  const data = await plaid(host, "/item/public_token/exchange", env, { public_token });
  await env.BTW_KV.put(tokenKey(userKey), data.access_token);
  await env.BTW_KV.delete(cursorKey(userKey));
  return json({ ok: true });
}

async function sandboxSeed(env, host, userKey) {
  const pt = await plaid(host, "/sandbox/public_token/create", env, {
    institution_id: "ins_109508", // First Platypus Bank (sandbox)
    initial_products: ["transactions"],
  });
  const data = await plaid(host, "/item/public_token/exchange", env, { public_token: pt.public_token });
  await env.BTW_KV.put(tokenKey(userKey), data.access_token);
  await env.BTW_KV.delete(cursorKey(userKey));
  return json({ ok: true });
}

async function sync(env, host, userKey) {
  const access_token = await env.BTW_KV.get(tokenKey(userKey));
  if (!access_token) return json({ error: "No bank connected yet — run /sandbox_seed or /exchange first." }, 400);

  let cursor = (await env.BTW_KV.get(cursorKey(userKey))) || undefined;
  let added = [], modified = [], removed = [], accounts = [];
  let hasMore = true, guard = 0;

  while (hasMore && guard < 50) {
    const data = await plaid(host, "/transactions/sync", env, { access_token, cursor, count: 500 });
    added = added.concat(data.added || []);
    modified = modified.concat(data.modified || []);
    removed = removed.concat((data.removed || []).map((r) => r.transaction_id));
    if (data.accounts) accounts = data.accounts; // latest balances ride along with the sync response
    cursor = data.next_cursor;
    hasMore = data.has_more;
    guard++;
  }
  if (cursor) await env.BTW_KV.put(cursorKey(userKey), cursor);

  // /transactions/sync's `accounts` only lists accounts that had activity in this response,
  // so a low-traffic account (e.g. savings) can be missing. Pull the authoritative list of
  // ALL accounts on the item (with balances) from /accounts/get.
  let allAccounts = accounts;
  try {
    const acctData = await plaid(host, "/accounts/get", env, { access_token });
    if (acctData.accounts && acctData.accounts.length) allAccounts = acctData.accounts;
  } catch (e) {
    // keep the accounts that rode along with the sync response
  }

  const slim = (t) => ({
    transaction_id: t.transaction_id,
    account_id: t.account_id,
    amount: t.amount,
    date: t.date,
    name: t.name,
    merchant_name: t.merchant_name || null,
  });
  const slimAccount = (a) => ({
    account_id: a.account_id,
    name: a.name,
    type: a.type,
    subtype: a.subtype,
    current: a.balances ? a.balances.current : null,
    available: a.balances ? a.balances.available : null,
  });
  return json({ added: added.map(slim), modified: modified.map(slim), removed, accounts: allAccounts.map(slimAccount) });
}

async function disconnect(env, host, userKey) {
  const access_token = await env.BTW_KV.get(tokenKey(userKey));
  if (access_token) {
    try {
      await plaid(host, "/item/remove", env, { access_token }); // revoke the Item at Plaid
    } catch (e) {
      // Item may already be gone/invalid — clearing local state below is what matters.
    }
  }
  await env.BTW_KV.delete(tokenKey(userKey));
  await env.BTW_KV.delete(cursorKey(userKey));
  return json({ ok: true });
}

async function resync(env, userKey) {
  // Forget the cursor so the next /sync re-pulls all transactions (re-tags accounts; labels preserved).
  await env.BTW_KV.delete(cursorKey(userKey));
  return json({ ok: true });
}
