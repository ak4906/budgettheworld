# BudgetTheWorld — Information Security Policy

_Owner: BudgetTheWorld maintainer · Last reviewed: 2026-06-05 · Review cadence: at least annually and on major changes_

This is the operational security policy for BudgetTheWorld, a single-developer personal finance app
that connects to a user's bank via Plaid (read-only Transactions).

## 1. Governance
- A single accountable owner (the maintainer) is responsible for information security.
- This policy is reviewed at least annually and whenever the architecture changes.
- Risks are identified, mitigated, and monitored on an ongoing basis at the scope below.

## 2. Identity & access management
- **Least privilege:** only the owner has access to production assets. No shared accounts.
- **MFA is enabled** on every account that touches financial data or production infrastructure:
  the Plaid Dashboard, the backend host (Cloudflare), Apple ID/App Store Connect, and the source
  code host (GitHub).
- **Secrets management:** the Plaid `client_id`/`secret` and the app shared secret are stored as
  encrypted environment secrets on the backend host. They are **never** committed to source control
  and **never** shipped in the mobile app binary.
- **Non-human authentication:** the app authenticates to the backend with a bearer auth token over
  TLS; unauthenticated requests are rejected.
- **Application authentication:** the app supports a required device-level lock (Face ID / Touch ID /
  device passcode via Apple's LocalAuthentication) before financial data is shown, and re-locks when
  backgrounded. There are no shared or multi-user accounts.
- **Access reviews:** account access and MFA status across the systems above are reviewed at least
  annually (sole operator).

## 3. Infrastructure & network security
- **In transit:** all traffic (app ⇄ backend ⇄ Plaid) uses HTTPS with TLS 1.2 or higher.
- **At rest:** local data on the device is encrypted by iOS device protection. The backend stores
  only the Plaid access token + sync cursor, encrypted at rest by the host's key-value store.
- **Data minimization:** the backend does not persist transaction history; it relays data to the
  device, which is the system of record for display.
- **Authentication:** every backend request requires a bearer secret; unauthenticated requests are
  rejected.

## 4. Development & vulnerability management
- Developer machine and OS are kept current with automatic security updates.
- Production runs on managed serverless infrastructure that is patched by the provider.
- Dependencies (Swift packages, backend packages) are kept up to date.
- **Patch SLA:** security updates to the OS, dependencies, and tooling are applied promptly —
  critical issues as soon as practical, other high-severity issues within 14 days of release.
- **End-of-life (EOL) software:** only currently-supported OS versions, SDKs, and managed services
  are used; EOL components are identified and upgraded or removed.

## 5. Privacy & consent
- Users connect accounts through Plaid Link, which obtains explicit consent before any data access.
- Data use is disclosed in the Privacy Policy (`docs/PRIVACY.md`).

## 6. Data retention & deletion
- Data is retained only while the user uses the app.
- Users can delete local data in-app, disconnect the bank (revoking the Plaid token via
  `/item/remove` and clearing it from the backend), or delete the app to remove all local data.
- This policy is reviewed periodically for compliance with applicable privacy laws.

## 7. Incident response
- On suspected compromise: rotate the backend and Plaid secrets, revoke affected Plaid items,
  and notify Plaid at security@plaid.com / building@plaid.com as applicable.
