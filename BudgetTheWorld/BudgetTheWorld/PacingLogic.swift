//
//  PacingLogic.swift
//  BudgetTheWorld
//
//  "Can I spend today?" pacing: turns the Free-to-Spend cushion into a daily/weekly/monthly
//  allowance and compares it against what you've actually spent on non-essentials in that window.
//

import Foundation

enum PacingBasis: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
    var unit: String {
        switch self {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        }
    }
    /// How many days this period represents, to scale the daily allowance.
    var perDayMultiple: Double {
        switch self {
        case .day: 1
        case .week: 7
        case .month: 30.4
        }
    }
    func currentInterval(_ calendar: Calendar = .current, now: Date = .now) -> DateInterval {
        switch self {
        case .day:
            let s = calendar.startOfDay(for: now)
            return DateInterval(start: s, end: calendar.date(byAdding: .day, value: 1, to: s) ?? s)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 0)
        case .month:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
        }
    }
}

enum PacingLogic {
    /// Sum of non-essential ("free to spend") expenses within an interval.
    static func discretionarySpent(entries: [LedgerEntry], essentialCodes: Set<String>, interval: DateInterval) -> Double {
        var total = 0.0
        for e in entries where e.amount < 0 && !e.isCardPayment {
            guard interval.contains(e.date) else { continue }
            let isEssential = e.essential ?? essentialCodes.contains(e.category.rawValue)
            if !isEssential { total += -e.amount }
        }
        return total
    }
}
