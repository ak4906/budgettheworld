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
        let amount: Double
        let date: String
        let name: String
        let merchant_name: String?
    }
    private struct Account: Decodable {
        let name: String?
        let type: String?
        let subtype: String?
        let current: Double?
        let available: Double?
    }

    /// Test hook: provisions a Plaid Sandbox item on the backend so /sync returns fake transactions.
    static func seedSandbox(baseURL: String, appSecret: String) async throws {
        _ = try await post(baseURL: baseURL, path: "/sandbox_seed", appSecret: appSecret)
    }

    /// Pull the latest delta from the backend and upsert it into the ledger.
    @MainActor
    static func sync(baseURL: String, appSecret: String, context: ModelContext) async throws -> SyncResult {
        let data = try await post(baseURL: baseURL, path: "/sync", appSecret: appSecret)
        let decoded = try JSONDecoder().decode(Response.self, from: data)

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
                // Keep the user's category edits; only refresh the bank-owned fields.
                e.date = date
                e.amount = amount
                e.rawDescription = desc
                e.merchant = t.merchant_name
                result.updated += 1
            } else {
                let e = LedgerEntry(date: date, amount: amount, rawDescription: desc,
                                    category: Categorizer.category(for: t.name), source: .plaid,
                                    merchant: t.merchant_name, plaidID: t.transaction_id)
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

        // When the bank is the source of truth, anchor the REAL checking balance from Plaid:
        // set the anchor to now + Plaid's current balance, so the live balance matches the bank.
        if UserDefaults.standard.bool(forKey: "bankSyncIsSourceOfTruth"), let accounts = decoded.accounts {
            let checking = accounts.first { $0.subtype == "checking" }
                ?? accounts.first { $0.type == "depository" }
            if let balance = checking?.current ?? checking?.available,
               let settings = try? context.fetch(FetchDescriptor<AppSettings>()).first {
                settings.currentCashBalance = balance
                settings.balanceAnchorDate = .now
            }
        }

        try? context.save()
        return result
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

    private static func post(baseURL: String, path: String, appSecret: String) async throws -> Data {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !appSecret.isEmpty, let url = URL(string: trimmed + path) else {
            throw SyncError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(appSecret)", forHTTPHeaderField: "Authorization")
        req.httpBody = Data("{}".utf8)
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
