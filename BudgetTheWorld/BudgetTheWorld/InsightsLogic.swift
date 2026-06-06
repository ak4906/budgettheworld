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
        let pay = ProjectionEngine.projectedPay(settings: settings, paychecks: paychecks, workDays: workDays, after: beforeStart, through: end, calendar: calendar)
        let lo = calendar.startOfDay(for: start)
        let hi = calendar.startOfDay(for: end)
        let logged = entries.filter { e in
            let d = calendar.startOfDay(for: e.date)
            return e.amount > 0 && d >= lo && d <= hi
        }.reduce(0.0) { $0 + $1.amount }
        return pay + logged
    }

    static func needsWantsSavings(_ cats: [CategorySpend], income: Double) -> (needs: Double, wants: Double, savings: Double) {
        var needs = 0.0
        var wants = 0.0
        for c in cats {
            switch c.category.needsWantsSavings {
            case "Needs": needs += c.amount
            case "Wants": wants += c.amount
            default: break
            }
        }
        return (needs, wants, max(income - needs - wants, 0))
    }
}
