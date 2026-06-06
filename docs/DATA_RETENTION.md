# BudgetTheWorld — Data Retention & Deletion Policy

_Owner: BudgetTheWorld maintainer · Last reviewed: 2026-06-05 · Review cadence: at least annually_

## Scope
Personal financial data accessed read-only via Plaid (transactions, account balances) and any
data the user enters manually.

## Retention
- Financial data is retained **only while the user actively uses the app**.
- The backend persists **only** the Plaid access token and a sync cursor (no transaction history).
- Transaction and balance data live on the user's device as the system of record.

## Deletion (user-initiated, honored promptly)
- **In-app:** the user can delete individual transactions or clear local data at any time.
- **Disconnect bank:** a single action revokes the Plaid connection (Plaid `/item/remove`) and
  removes the stored access token + cursor from the backend, then deletes bank-synced records on
  the device.
- **Delete app:** removing the app deletes all locally stored data.

## Compliance & review
- The policy is designed to comply with applicable consumer data-privacy laws, honoring
  user-initiated access-revocation and deletion requests promptly.
- This policy is reviewed at least annually and whenever the data architecture changes.

## Contact
Data requests: **[your-contact-email]**
