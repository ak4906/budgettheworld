# BudgetTheWorld — Access Control Policy

_Owner: BudgetTheWorld maintainer · Last reviewed: 2026-06-05 · Review cadence: at least annually_

Controls that limit access to production assets (virtual) and sensitive data.

## Defined & documented policy
- This Access Control Policy and the Information Security Policy define how access is granted,
  restricted, and reviewed. Both are reviewed at least annually and on major changes.

## Least privilege & accounts
- A single owner operates the system; there are no shared accounts, and credentials are unique.
- Multi-factor authentication (MFA) is enabled on every system that handles financial data or
  production infrastructure: the Plaid Dashboard, the backend host (Cloudflare), Apple ID /
  App Store Connect, and the source-code host (GitHub).

## Non-human authentication
- The app authenticates to the backend with a bearer auth token (OAuth-style) over TLS.
- The backend authenticates to Plaid with its client ID + secret over TLS.
- Unauthenticated requests are rejected. Secrets are stored as encrypted environment secrets and are
  never committed to source control or shipped in the app binary.

## Periodic access reviews
- Account access and MFA status across the systems above are reviewed at least annually, and access
  is revoked promptly when it is no longer needed.

## Sensitive-data access
- The Plaid access token is stored encrypted at rest in the backend key-value store; transaction
  data lives only on the user's device (the system of record).
- All data in transit uses HTTPS (TLS 1.2 or higher).
