BudgetTheWorld — Privacy Policy
Last updated: 2026-06-05

BudgetTheWorld ("the app") is a personal budgeting and cash-flow app created and operated by the BudgetTheWorld maintainer ("we", "I"). This policy explains what data the app handles and how.

Who this is for
The app is a single-user personal finance tool. The only user is the account owner who installs it on their own device and connects their own financial accounts.

What data we access
When you choose to connect a bank account, we use Plaid to access, on a read-only basis:

your transactions (date, amount, description, merchant, category), and
your account balances.
We do not have your banking login credentials — you enter those directly with Plaid, never with this app. We do not move money; access is read-only.

How the data is used
Your financial data is used only to power features inside the app you are using: showing your balance, spending, budgets, forecasts, and related insights. We do not sell your data, and we do not share it with advertisers or any third party other than Plaid (our data provider) and the infrastructure used to deliver the app to you.

Where the data is stored
On your device: transactions and balances are stored locally on your iPhone using Apple's on-device storage, which is encrypted at rest by iOS device protection.
On our backend: a minimal server (a serverless function) stores only the Plaid access token and a sync cursor needed to fetch your data. These are stored encrypted at rest. We do not store your transaction history on the backend; it passes through to your device.
In transit: all communication uses HTTPS (TLS 1.2 or higher).
Plaid
Connections are provided by Plaid Inc. Plaid's handling of your data is governed by Plaid's end-user privacy policy: https://plaid.com/legal/#end-user-privacy-policy

Your choices, retention, and deletion
We keep your data only as long as you use the app:

You can delete individual transactions or all local data within the app at any time.
You can disconnect your bank, which revokes the Plaid access token and removes it from the backend (via Plaid's /item/remove).
Deleting the app from your device removes all locally stored data.
Children
The app is not directed to children under 13 and does not knowingly collect their data.

Changes
This policy may be updated; the "Last updated" date will change accordingly.

Contact
Questions or data requests: alexander.knue@gmail.com
