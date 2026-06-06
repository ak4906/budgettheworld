//
//  BudgetSeed.swift
//  BudgetTheWorld
//
//  First-launch EXAMPLE defaults so the dashboard is meaningful on day one. These are generic
//  placeholders — not anyone's real data — and only seed into an empty store. Your real numbers
//  live in SwiftData on your device; edit everything in the in-app Settings screen.
//

import Foundation
import SwiftData

enum BudgetSeed {
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<AppSettings>())
        guard (existing?.isEmpty ?? true) else { return }

        let calendar = Calendar.current

        // Example bi-weekly pay period + employment start (placeholders; set yours in Settings).
        let periodStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 4)) ?? .now
        let employmentStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? .now

        // Example 401(k): 5% contribution, 100% match up to 5%, +1%/yr auto-increase, cap 75%.
        let increaseStart = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1)) ?? .now

        let settings = AppSettings(
            hourlyWage: 20.00,
            firstPaydayAnchor: periodStart,            // legacy field, no longer used
            currentCashBalance: 1500,                  // placeholder; set your real balance in Settings
            periodAnchorStart: periodStart,
            payLagDays: 6,
            employmentStartDate: employmentStart,
            retirementPercent: 0.05,
            employerMatchPercent: 0.05,
            annualIncreasePercent: 0.01,
            annualIncreaseStartDate: increaseStart,
            annualIncreaseCap: 0.75
        )
        context.insert(settings)

        // Example rent, due the 1st of next month.
        context.insert(RentObligation(amount: 1200, dueDate: firstOfNextMonth(after: .now, calendar: calendar)))

        // Example sinking funds (amounts are placeholders to show the progress bars).
        let buckets: [Bucket] = [
            Bucket(name: "Rent Reserve",    kind: .rentReserve, targetAmount: 1200, currentAmount: 600, monthlyContribution: 1200, sortIndex: 0),
            Bucket(name: "Emergency Fund",  kind: .emergency,   targetAmount: 1000, currentAmount: 250, monthlyContribution: 300,  sortIndex: 1),
            Bucket(name: "Goal Fund",       kind: .medSchool,   targetAmount: 5000, currentAmount: 800, monthlyContribution: 150,  sortIndex: 2),
            Bucket(name: "Apartment Setup", kind: .apartment,   targetAmount: 800,  currentAmount: 160, monthlyContribution: 150,  sortIndex: 3),
        ]
        buckets.forEach { context.insert($0) }

        // A starter credit card (fresh installs only — edit in Settings).
        let cardDue = calendar.date(from: DateComponents(year: 2026, month: 2, day: 5)) ?? .now
        context.insert(CreditCard(name: "Credit Card", currentBalance: 0, statementBalance: 0, minimumPayment: 0, statementDueDate: cardDue))

        try? context.save()
    }

    private static func firstOfNextMonth(after date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let firstOfThisMonth = calendar.date(from: comps) ?? date
        return calendar.date(byAdding: .month, value: 1, to: firstOfThisMonth) ?? date
    }
}
