//
//  PlaidSyncService.swift
//  BudgetTheWorld
//
//  Talks to the BudgetTheWorld Plaid backend (see the repo's plaid-backend/ folder) and folds the
//  returned transactions into the local SwiftData ledger. The Plaid secret never touches the app —
//  the backend holds it and exposes only /sync (and /sandbox_seed, /link_token, /exchange).
//
//  Sign convention: Plaid reports a positive `amount` when money LEAVES a depository account, so a
//  ledger amount (negative = money out) is the negation of Plaid's amount.
//

import Foundation
import SwiftData

enum PlaidSyncService {
    struct SyncResult { var added = 0; var updated = 0; var removed = 0 }

    enum SyncError: LocalizedError {
        case notConfigured
        case server(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Set the backend URL and app secret first."
            case .server(let m): m
            }
        }
    }

    private struct Response: Decodable {
        let added: [Txn]
        let modified: [Txn]
        let removed: [String]
        let accounts: [Account]?
    }
    private struct Txn: Decodable {
        let transaction_id: String
        let account_id: String?
        let amount: Double
        let date: String
        let name: String
        let merchant_name: String?
    }
    private struct Account: Decodable {
        let account_id: String?
        let name: String?
        let type: String?
        let subtype: String?
        let current: Double?
        let available: Double?
    }
    private struct LinkTokenResponse: Decodable { let link_token: String }

    /// Test hook: provisions a Plaid Sandbox item on the backend so /sync returns fake transactions.
    static func seedSandbox(baseURL: String, appSecret: String) async throws {
        _ = try await post(baseURL: baseURL, path: "/sandbox_seed", appSecret: appSecret)
    }

    /// Ask the backend for a Plaid Link token, used to open Plaid Link in the app.
    static func createLinkToken(baseURL: String, appSecret: String) async throws -> String {
        let data = try await post(baseURL: baseURL, path: "/link_token", appSecret: appSecret)
        return try JSONDecoder().decode(LinkTokenResponse.self, from: data).link_token
    }

    /// Hand Plaid Link's public token to the backend, which exchanges + stores the access token.
    static func exchange(baseURL: String, appSecret: String, publicToken: String) async throws {
        _ = try await post(baseURL: baseURL, path: "/exchange", appSecret: appSecret, body: ["public_token": publicToken])
    }

    /// Pull the latest delta from the backend and upsert it into the ledger, routing each transaction
    /// to its real account (checking / savings / credit) and refreshing per-account balances.
    @MainActor
    static func sync(baseURL: String, appSecret: String, context: ModelContext) async throws -> SyncResult {
        let data = try await post(baseURL: baseURL, path: "/sync", appSecret: appSecret)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

        let accounts = decoded.accounts ?? []
        let sourceOfTruth = UserDefaults.standard.bool(forKey: "bankSyncIsSourceOfTruth")
        let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first
        let existingCards = (try? context.fetch(FetchDescriptor<CreditCard>())) ?? []

        // Map each Plaid account → display name + kind, ensure a CreditCard exists per credit account,
        // and (when the bank is the source of truth) refresh the real balances.
        var nameByAccount: [String: String] = [:]
        var kindByAccount: [String: String] = [:]   // "checking" / "savings" / "credit" / "other"
        var cardNameByAccount: [String: String] = [:]

        for a in accounts {
            guard let id = a.account_id else { continue }
            let kind = accountKind(a)
            nameByAccount[id] = a.name ?? kind.capitalized
            kindByAccount[id] = kind

            switch kind {
            case "credit":
                let card = existingCards.first { $0.plaidAccountID == id }
                    ?? existingCards.first { $0.plaidAccountID == nil && $0.name == (a.name ?? "") }
                if let card {
                    card.plaidAccountID = id
                    if sourceOfTruth, let bal = a.current { card.currentBalance = bal; card.balanceAnchorDate = .now }
                    cardNameByAccount[id] = card.name
                } else {
                    let newCard = CreditCard(name: a.name ?? "Credit Card",
                                             currentBalance: a.current ?? 0,
                                             statementBalance: a.current ?? 0,
                                             balanceAnchorDate: .now,
                                             plaidAccountID: id)
                    context.insert(newCard)
                    cardNameByAccount[id] = newCard.name
                }
            case "savings":
                if sourceOfTruth, let s = settings, let bal = a.current { s.savingsBalance = bal; s.savingsAnchorDate = .now }
            default: // "checking" / "other"
                if sourceOfTruth, let s = settings, let bal = a.current ?? a.available { s.currentCashBalance = bal; s.balanceAnchorDate = .now }
            }
        }

        // Record what accounts the sync actually saw (shown on the Bank Sync screen for debugging).
        let summary = accounts.compactMap { a -> String? in
            guard let id = a.account_id else { return nil }
            let bal = a.current ?? a.available
            let balStr = bal.map { String(format: "$%.2f", $0) } ?? "—"
            return "\(a.name ?? "Account") · \(kindByAccount[id] ?? "?") · \(balStr)"
        }.joined(separator: "\n")
        UserDefaults.standard.set(summary, forKey: "bankSyncAccountsSummary")

        // Saved label rules → auto-apply to new transactions by description.
        let rules = (try? context.fetch(FetchDescriptor<LabelRule>())) ?? []
        var rulesByMatch: [String: [LabelRule]] = [:]
        for r in rules { rulesByMatch[r.match.lowercased(), default: []].append(r) }
        // For a description + amount, prefer an amount-specific rule, else the amount-agnostic one.
        func bestRule(_ desc: String, _ amt: Double) -> LabelRule? {
            guard let candidates = rulesByMatch[desc.lowercased()] else { return nil }
            if let exact = candidates.first(where: { $0.amount.map { abs($0 - abs(amt)) < 0.01 } ?? false }) { return exact }
            return candidates.first { $0.amount == nil }
        }

        let existing = (try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []
        var byID: [String: LedgerEntry] = [:]
        for e in existing where e.plaidID != nil { byID[e.plaidID!] = e }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = .current
        df.locale = Locale(identifier: "en_US_POSIX")

        var result = SyncResult()

        func upsert(_ t: Txn) {
            let date = df.date(from: t.date) ?? .now
            let amount = -t.amount
            let desc = (t.merchant_name?.isEmpty == false) ? t.merchant_name! : t.name
            if let e = byID[t.transaction_id] {
                // Preserve the user's labels; only refresh the financial facts that change.
                e.amount = amount
                e.date = date
                // Backfill account info on rows synced before multi-account support (never overwrite).
                if e.accountID == nil, let acctID = t.account_id {
                    e.accountID = acctID
                    e.accountName = nameByAccount[acctID]
                    if e.cardName == nil, kindByAccount[acctID] == "credit" {
                        e.cardName = cardNameByAccount[acctID]
                    }
                }
                result.updated += 1
            } else {
                let acctID = t.account_id
                let acctName = acctID.flatMap { nameByAccount[$0] }
                let isCredit = acctID.flatMap { kindByAccount[$0] } == "credit"
                let card = isCredit ? acctID.flatMap { cardNameByAccount[$0] } : nil
                var cat = Categorizer.category(for: t.name)
                var subc: String? = nil
                var merch: String? = t.merchant_name
                var purp: TxnPurpose? = nil
                if let rule = bestRule(desc, amount) {
                    cat = rule.category
                    subc = rule.subcategory
                    merch = rule.merchant ?? merch
                    purp = rule.purpose
                }
                let e = LedgerEntry(date: date, amount: amount, rawDescription: desc,
                                    category: cat, source: .plaid, cardName: card,
                                    subcategory: subc, merchant: merch, purpose: purp,
                                    plaidID: t.transaction_id, accountID: acctID, accountName: acctName)
                context.insert(e)
                byID[t.transaction_id] = e
                result.added += 1
            }
        }

        for t in decoded.added { upsert(t) }
        for t in decoded.modified { upsert(t) }
        for id in decoded.removed where byID[id] != nil {
            context.delete(byID[id]!)
            result.removed += 1
        }

        try? context.save()
        return result
    }

    /// Classify a Plaid account into the app's buckets.
    private static func accountKind(_ a: Account) -> String {
        let type = (a.type ?? "").lowercased()
        let sub = (a.subtype ?? "").lowercased()
        if type == "credit" { return "credit" }
        if type == "depository" { return sub == "savings" ? "savings" : "checking" }
        return "other"
    }

    /// Forget the backend cursor and re-pull ALL transactions — re-tags accounts on rows already
    /// present (without deleting them), so your labels are preserved.
    @MainActor
    static func resyncAll(baseURL: String, appSecret: String, context: ModelContext) async throws -> SyncResult {
        _ = try await post(baseURL: baseURL, path: "/resync", appSecret: appSecret)
        return try await sync(baseURL: baseURL, appSecret: appSecret, context: context)
    }

    /// Revoke the bank connection on the backend (Plaid /item/remove) and delete locally synced rows.
    @MainActor
    static func disconnect(baseURL: String, appSecret: String, context: ModelContext) async throws -> Int {
        _ = try await post(baseURL: baseURL, path: "/disconnect", appSecret: appSecret)
        let synced = ((try? context.fetch(FetchDescriptor<LedgerEntry>())) ?? []).filter { $0.source == .plaid }
        for e in synced { context.delete(e) }
        try? context.save()
        return synced.count
    }

    private static func post(baseURL: String, path: String, appSecret: String, body: [String: String] = [:]) async throws -> Data {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appSecret.isEmpty, let url = URL(string: trimmed + path) else {
            throw SyncError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(appSecret)", forHTTPHeaderField: "Authorization")
        req.httpBody = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw SyncError.server("No response") }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SyncError.server(msg)
        }
        return data
    }
}
