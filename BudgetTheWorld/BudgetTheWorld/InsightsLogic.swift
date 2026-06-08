//
//  InsightsLogic.swift
//  BudgetTheWorld
//
//  Observed-spending analysis: category totals and a 50/30/20 fit against take-home income.
//

import Foundation

enum InsightPeriod: String, CaseIterable, Identifiable {
    case thisPayPeriod, thisMonth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .thisPayPeriod: "Pay period"
        case .thisMonth: "This month"
        }
    }
    func bounds(settings: AppSettings, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: .now)
        switch self {
        case .thisPayPeriod:
            let p = BudgetMath.payPeriod(containing: .now, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            return (p.start, p.lastDay)
        case .thisMonth:
            if let i = calendar.dateInterval(of: .month, for: today) {
                return (i.start, calendar.date(byAdding: .day, value: -1, to: i.end) ?? today)
            }
            return (today, today)
        }
    }
}

struct CategorySpend: Identifiable {
    let category: SpendCategory
    let amount: Double
    var id: String { category.rawValue }
}

/// Per-merchant price stats for an item ("where is boba cheapest?").
struct MerchantPriceStat: Identifiable {
    let merchant: String
    let count: Int
    let total: Double
    let min: Double
    let max: Double
    var avg: Double { count > 0 ? total / Double(count) : 0 }
    var id: String { merchant }
}

/// One matching purchase, for the price-over-time chart.
struct PricePoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
    let merchant: String
}

enum InsightsLogic {
    static func spendingByCategory(_ entries: [LedgerEntry], start: Date, end: Date, calendar: Calendar = .current) -> [CategorySpend] {
        let lo = calendar.startOfDay(for: start)
        let hi = calendar.startOfDay(for: end)
        var totals: [SpendCategory: Double] = [:]
        for e in entries where e.amount < 0 && !e.isCardPayment {
            let d = calendar.startOfDay(for: e.date)
            if d >= lo && d <= hi { totals[e.category, default: 0] += -e.amount }
        }
        return totals.map { CategorySpend(category: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    /// Take-home income for the window: projected paychecks + logged income transactions.
    static func income(settings: AppSettings, paychecks: [Paycheck], workDays: [WorkDay], entries: [LedgerEntry], start: Date, end: Date, calendar: Calendar = .current) -> Double {
        let beforeStart = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        // When the bank is the source of truth, PAST paychecks are real synced deposits (counted in
        // `logged` below). Only PROJECT pay that is still in the future, or past pay double-counts.
        let bankIsTruth = UserDefaults.standard.bool(forKey: "bankSyncIsSourceOfTruth")
        let projectAfter = bankIsTruth ? max(beforeStart, calendar.startOfDay(for: .now)) : beforeStart
        let pay = ProjectionEngine.projectedPay(settings: settings, paychecks: paychecks, workDays: workDays, after: projectAfter, through: end, calendar: calendar)
        let lo = calendar.startOfDay(for: start)
        let hi = calendar.startOfDay(for: end)
        let logged = entries.filter { e in
            let d = calendar.startOfDay(for: e.date)
            return e.amount > 0 && d >= lo && d <= hi
        }.reduce(0.0) { $0 + $1.amount }
        return pay + logged
    }

    /// A category's 50/30/20 class, honoring the user's custom overrides.
    static func classification(for category: SpendCategory, overrides: [String: String]) -> String {
        overrides[category.rawValue] ?? category.needsWantsSavings
    }

    static func needsWantsSavings(_ cats: [CategorySpend], income: Double, overrides: [String: String] = [:]) -> (needs: Double, wants: Double, savings: Double) {
        var needs = 0.0
        var wants = 0.0
        for c in cats {
            switch classification(for: c.category, overrides: overrides) {
            case "Needs": needs += c.amount
            case "Wants": wants += c.amount
            default: break
            }
        }
        return (needs, wants, max(income - needs - wants, 0))
    }

    /// A single entry's 50/30/20 class, honoring its per-transaction need/want override.
    static func entryClass(_ e: LedgerEntry, overrides: [String: String]) -> String {
        if let ess = e.essential { return ess ? "Needs" : "Wants" }
        return classification(for: e.category, overrides: overrides)
    }

    /// 50/30/20 from RAW entries (so per-transaction need/want overrides are respected).
    static func needsWantsSavings(entries: [LedgerEntry], income: Double, start: Date, end: Date, overrides: [String: String], calendar: Calendar = .current) -> (needs: Double, wants: Double, savings: Double) {
        let lo = calendar.startOfDay(for: start), hi = calendar.startOfDay(for: end)
        var needs = 0.0, wants = 0.0
        for e in entries where e.amount < 0 && !e.isCardPayment {
            let d = calendar.startOfDay(for: e.date)
            guard d >= lo && d <= hi else { continue }
            let cls = entryClass(e, overrides: overrides)
            if cls == "Needs" { needs += -e.amount } else if cls == "Wants" { wants += -e.amount }
        }
        return (needs, wants, max(income - needs - wants, 0))
    }

    /// Categories (with totals) that fall into a 50/30/20 bucket — for the drill-down.
    static func bucketCategories(_ bucket: String, entries: [LedgerEntry], start: Date, end: Date, overrides: [String: String], calendar: Calendar = .current) -> [(label: String, amount: Double)] {
        let lo = calendar.startOfDay(for: start), hi = calendar.startOfDay(for: end)
        var totals: [String: Double] = [:]
        for e in entries where e.amount < 0 && !e.isCardPayment {
            let d = calendar.startOfDay(for: e.date)
            guard d >= lo && d <= hi, entryClass(e, overrides: overrides) == bucket else { continue }
            let label = e.subcategory.map { "\(e.category.displayName) · \($0)" } ?? e.category.displayName
            totals[label, default: 0] += -e.amount
        }
        return totals.map { (label: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }

    /// Sum of expenses in a period whose name/subcategory/place/category contains `query`.
    static func total(matching query: String, entries: [LedgerEntry], start: Date, end: Date, calendar: Calendar = .current) -> (total: Double, count: Int) {
        let q = query.lowercased()
        let lo = calendar.startOfDay(for: start), hi = calendar.startOfDay(for: end)
        var sum = 0.0, n = 0
        for e in entries where e.amount < 0 && !e.isCardPayment {
            let d = calendar.startOfDay(for: e.date)
            guard d >= lo && d <= hi else { continue }
            let hay = "\(e.rawDescription) \(e.subcategory ?? "") \(e.merchant ?? "") \(e.category.displayName)".lowercased()
            if hay.contains(q) { sum += -e.amount; n += 1 }
        }
        return (sum, n)
    }

    /// Whether an entry matches a free-text query (name / subcategory / place / category).
    static func matchesQuery(_ e: LedgerEntry, _ q: String) -> Bool {
        let hay = "\(e.rawDescription) \(e.subcategory ?? "") \(e.merchant ?? "") \(e.category.displayName)".lowercased()
        return hay.contains(q)
    }

    private static func merchantName(_ e: LedgerEntry) -> String {
        (e.merchant?.isEmpty == false) ? e.merchant! : "Unknown"
    }

    /// Per-merchant price stats for everything matching `query`, ALL-TIME, cheapest average first.
    /// Matches whole transactions; if a transaction doesn't match but has a matching LINE ITEM,
    /// that item's price is used instead — so "apples" finds the cheapest store for apples.
    static func priceStats(matching query: String, entries: [LedgerEntry]) -> [MerchantPriceStat] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var byMerchant: [String: (count: Int, total: Double, min: Double, max: Double)] = [:]
        func add(_ price: Double, _ m: String) {
            var cur = byMerchant[m] ?? (0, 0, price, price)
            cur.count += 1; cur.total += price
            cur.min = Swift.min(cur.min, price); cur.max = Swift.max(cur.max, price)
            byMerchant[m] = cur
        }
        for e in entries where e.amount < 0 && !e.isCardPayment {
            let m = merchantName(e)
            if matchesQuery(e, q) {
                add(-e.amount, m)
            } else {
                for li in e.lineItems where li.name.lowercased().contains(q) { add(li.amount, m) }
            }
        }
        return byMerchant
            .map { MerchantPriceStat(merchant: $0.key, count: $0.value.count, total: $0.value.total, min: $0.value.min, max: $0.value.max) }
            .sorted { $0.avg < $1.avg }
    }

    /// Each matching purchase (or matching line item) over time, for the price-trend chart, ALL-TIME.
    static func priceSeries(matching query: String, entries: [LedgerEntry]) -> [PricePoint] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        var out: [PricePoint] = []
        for e in entries where e.amount < 0 && !e.isCardPayment {
            let m = merchantName(e)
            if matchesQuery(e, q) {
                out.append(PricePoint(date: e.date, price: -e.amount, merchant: m))
            } else {
                for li in e.lineItems where li.name.lowercased().contains(q) {
                    out.append(PricePoint(date: e.date, price: li.amount, merchant: m))
                }
            }
        }
        return out.sorted { $0.date < $1.date }
    }

    /// A category's expenses grouped by a key (subcategory or place) for the drill-down.
    static func grouped(category: SpendCategory, by key: (LedgerEntry) -> String, entries: [LedgerEntry], start: Date, end: Date, calendar: Calendar = .current) -> [(label: String, amount: Double)] {
        let lo = calendar.startOfDay(for: start), hi = calendar.startOfDay(for: end)
        var totals: [String: Double] = [:]
        for e in entries where e.category == category && e.amount < 0 && !e.isCardPayment {
            let d = calendar.startOfDay(for: e.date)
            guard d >= lo && d <= hi else { continue }
            totals[key(e), default: 0] += -e.amount
        }
        return totals.map { (label: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }
}
