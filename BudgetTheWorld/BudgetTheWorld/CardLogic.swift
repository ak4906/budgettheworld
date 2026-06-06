//
//  CardLogic.swift
//  BudgetTheWorld
//
//  Dynamic credit card balance: the anchor amount plus charges (transactions marked
//  "paid with this card") minus payments, up to a given date — the same pattern as the
//  dynamic checking balance, applied to debt.
//

import Foundation

enum CardLogic {
    /// Balance owed on a card as of `reference` = anchor + charges − payments since the anchor date.
    static func balance(for card: CreditCard, entries: [LedgerEntry], recurrings: [RecurringTransaction] = [], asOf reference: Date = .now, calendar: Calendar = .current) -> Double {
        let lo = calendar.startOfDay(for: card.balanceAnchorDate)
        let hi = calendar.startOfDay(for: reference)
        var owed = card.currentBalance
        for e in entries where e.cardName == card.name {
            let d = calendar.startOfDay(for: e.date)
            guard d >= lo && d <= hi else { continue }
            if e.isCardPayment {
                owed += e.amount      // payment amount is negative → reduces what's owed
            } else {
                owed += -e.amount     // charge amount is negative → increases what's owed
            }
        }
        // Projected future recurring charges to this card (now → reference).
        for r in recurrings where r.cardName == card.name && r.amount < 0 {
            let c = ProjectionEngine.occurrences(of: r, after: .now, through: reference, calendar: calendar)
            owed += Double(c) * (-r.amount)
        }
        return owed
    }
}
