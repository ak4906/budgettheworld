//
//  BalanceLogic.swift
//  BudgetTheWorld
//
//  Dynamic balance: you set a balance "as of" an anchor date, and every transaction
//  on or after that date moves it. This makes the checking balance live and projectable
//  (pass a future date to see where the balance is headed).
//

import Foundation

enum BalanceLogic {
    /// Balance as of `date` = anchor amount + signed transactions dated from the anchor day
    /// through `date` (inclusive). Spends are negative, income positive.
    static func balance(asOf date: Date, anchorAmount: Double, anchorDate: Date, entries: [LedgerEntry], calendar: Calendar = .current) -> Double {
        let lo = calendar.startOfDay(for: anchorDate)
        let hi = calendar.startOfDay(for: date)
        let delta = entries
            .filter { entry in
                let d = calendar.startOfDay(for: entry.date)
                return entry.affectsChecking && d >= lo && d <= hi
            }
            .reduce(0.0) { $0 + $1.amount }
        return anchorAmount + delta
    }
}
