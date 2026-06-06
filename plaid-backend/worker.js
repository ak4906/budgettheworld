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
      if (request.method !== "POST") return json({ error: "POST only" }, 405);
      if ((request.headers.get("Authorization") || "") !== `Bearer ${env.APP_SECRET}`) {
        return json({ error: "unauthorized" }, 401);
      }
      const path = new URL(request.url).pathname;
      const host = PLAID_HOSTS[env.PLAID_ENV || "sandbox"] || PLAID_HOSTS.sandbox;

      switch (path) {
        case "/link_token": return await createLinkToken(env, host);
        case "/exchange": return await exchange(request, env, host);
        case "/sandbox_seed": return await sandboxSeed(env, host);
        case "/sync": return await sync(env, host);
        case "/disconnect": return await disconnect(env, host);
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
  const data = await plaid(host, "/link/token/create", env, {
    user: { client_user_id: "budgettheworld-user" },
    client_name: "BudgetTheWorld",
    products: ["transactions"],
    transactions: { days_requested: 730 }, // pull up to ~24 months of history on connect
    country_codes: ["US"],
    language: "en",
  });
  return json({ link_token: data.link_token });
}

async function exchange(request, env, host) {
  const { public_token } = await request.json();
  if (!public_token) return json({ error: "missing public_token" }, 400);
  const data = await plaid(host, "/item/public_token/exchange", env, { public_token });
  await env.BTW_KV.put("access_token", data.access_token);
  await env.BTW_KV.delete("cursor");
  return json({ ok: true });
}

async function sandboxSeed(env, host) {
  const pt = await plaid(host, "/sandbox/public_token/create", env, {
    institution_id: "ins_109508", // First Platypus Bank (sandbox)
    initial_products: ["transactions"],
  });
  const data = await plaid(host, "/item/public_token/exchange", env, { public_token: pt.public_token });
  await env.BTW_KV.put("access_token", data.access_token);
  await env.BTW_KV.delete("cursor");
  return json({ ok: true });
}

async function sync(env, host) {
  const access_token = await env.BTW_KV.get("access_token");
  if (!access_token) return json({ error: "No bank connected yet — run /sandbox_seed or /exchange first." }, 400);

  let cursor = (await env.BTW_KV.get("cursor")) || undefined;
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
  if (cursor) await env.BTW_KV.put("cursor", cursor);

  const slim = (t) => ({
    transaction_id: t.transaction_id,
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
  return json({ added: added.map(slim), modified: modified.map(slim), removed, accounts: accounts.map(slimAccount) });
}

async function disconnect(env, host) {
  const access_token = await env.BTW_KV.get("access_token");
  if (access_token) {
    try {
      await plaid(host, "/item/remove", env, { access_token }); // revoke the Item at Plaid
    } catch (e) {
      // Item may already be gone/invalid — clearing local state below is what matters.
    }
  }
  await env.BTW_KV.delete("access_token");
  await env.BTW_KV.delete("cursor");
  return json({ ok: true });
}
