//
//  RecurringMaterializer.swift
//  BudgetTheWorld
//
//  Turns recurring items into real, individual LedgerEntry rows (tagged source: .recurring) from
//  each series' start date up to today — so they appear in Spending, are tappable/editable, and
//  move account & card balances. Runs at launch (idempotent via `lastMaterializedDate`).
//
//  Safe against double-counting: every forward projection in ProjectionEngine counts recurrences
//  strictly AFTER today, while this only ever materializes occurrences dated today-or-earlier.
//

import Foundation
import SwiftData

enum RecurringMaterializer {
    static func catchUp(context: ModelContext, calendar: Calendar = .current) {
        // If real bank data is the source of truth, don't fabricate past recurring rows — they'd
        // duplicate the synced transactions. Recurring then only feeds the forward forecast.
        if UserDefaults.standard.bool(forKey: "bankSyncIsSourceOfTruth") { return }
        let today = calendar.startOfDay(for: .now)
        guard let recurrings = try? context.fetch(FetchDescriptor<RecurringTransaction>()) else { return }

        var changed = false
        for r in recurrings where r.isActive {
            let lastDone = calendar.startOfDay(for: r.lastMaterializedDate)
            let seriesEnd = calendar.startOfDay(for: r.endDate)

            // Walk occurrences from the series start (so cadence alignment is exact), materializing
            // any that fall in (lastDone, today] and on/before the series end date.
            var d = calendar.startOfDay(for: r.startDate)
            var guardCount = 0
            while d <= today && d <= seriesEnd && guardCount < 4000 {
                if d > lastDone {
                    context.insert(LedgerEntry(date: d,
                                               amount: r.amount,
                                               rawDescription: r.detail,
                                               category: r.category,
                                               source: .recurring,
                                               cardName: r.cardName))
                    changed = true
                }
                guard let next = step(d, cadence: r.cadence, calendar: calendar), next > d else { break }
                d = next
                guardCount += 1
            }

            if today > lastDone {
                r.lastMaterializedDate = today
                changed = true
            }
        }

        if changed { try? context.save() }
    }

    private static func step(_ d: Date, cadence: RecurringCadence, calendar: Calendar) -> Date? {
        switch cadence {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: d)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: d)
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: d)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: d)
        }
    }
}
