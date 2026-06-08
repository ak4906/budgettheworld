//
//  BalanceHistoryLogic.swift
//  BudgetTheWorld
//
//  Day-by-day balance history for the Balance History graph. Reconstructs each past day's
//  balance BACKWARD from today's known balance using the actual transactions, so the graph's
//  "today" point always matches what the rest of the app shows.
//

import Foundation

enum BalanceHistoryLogic {
    struct Point: Identifiable {
        let date: Date
        let balance: Double
        var id: Date { date }
    }

    /// Checking balance for each day in [today-days, today].
    static func checkingHistory(days: Int, settings: AppSettings, entries: [LedgerEntry], calendar: Calendar = .current) -> [Point] {
        let todayBal = BalanceLogic.balance(asOf: .now, anchorAmount: settings.currentCashBalance, anchorDate: settings.balanceAnchorDate, entries: entries, calendar: calendar)
        return series(days: days, todayValue: todayBal, entries: entries, calendar: calendar) { $0.affectsChecking ? $0.amount : 0 }
    }

    /// Amount owed on a card for each day in [today-days, today].
    static func cardHistory(days: Int, card: CreditCard, entries: [LedgerEntry], calendar: Calendar = .current) -> [Point] {
        let todayOwed = CardLogic.balance(for: card, entries: entries, asOf: .now, calendar: calendar)
        return series(days: days, todayValue: todayOwed, entries: entries, calendar: calendar) {
            $0.cardName == card.name ? ($0.isCardPayment ? $0.amount : -$0.amount) : 0
        }
    }

    /// Recurring monthly statement due dates that fall within a date range (for the "due" lines).
    static func dueDates(for card: CreditCard, in range: ClosedRange<Date>, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var d = calendar.startOfDay(for: card.statementDueDate)
        var guardC = 0
        while d > range.lowerBound && guardC < 120 {
            guard let prev = calendar.date(byAdding: .month, value: -1, to: d) else { break }
            d = prev; guardC += 1
        }
        guardC = 0
        while d <= range.upperBound && guardC < 120 {
            if d >= range.lowerBound { result.append(d) }
            guard let next = calendar.date(byAdding: .month, value: 1, to: d) else { break }
            d = next; guardC += 1
        }
        return result
    }

    /// Backward reconstruction: balance(day−1) = balance(day) − (contributions dated on `day`).
    private static func series(days: Int, todayValue: Double, entries: [LedgerEntry], calendar: Calendar, contribution: (LedgerEntry) -> Double) -> [Point] {
        let today = calendar.startOfDay(for: .now)
        var byDay: [Date: Double] = [:]
        for e in entries {
            let d = calendar.startOfDay(for: e.date)
            guard d <= today else { continue }   // ignore future-dated entries
            let c = contribution(e)
            if c != 0 { byDay[d, default: 0] += c }
        }
        var points: [Point] = []
        var running = todayValue
        var day = today
        points.append(Point(date: day, balance: running))
        for _ in 0..<max(days, 1) {
            running -= byDay[day, default: 0]
            guard let prev = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
            points.append(Point(date: day, balance: running))
        }
        return points.sorted { $0.date < $1.date }
    }
}
