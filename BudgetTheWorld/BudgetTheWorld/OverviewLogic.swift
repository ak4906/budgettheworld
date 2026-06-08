//
//  OverviewLogic.swift
//  BudgetTheWorld
//
//  Computes the eight "core" personal-finance metrics for the Overview screen, reusing the
//  existing engines (income, balance, cards, retirement) so the numbers match the rest of the app.
//

import Foundation

struct CoreMetrics {
    var ficoScore: Int          // 0 = unset
    var vantageScore: Int       // 0 = unset
    var monthlyIncome: Double   // take-home, this month
    var monthlyExpenses: Double // rent + recurring (monthly-equivalent)
    var cashFlow: Double        // income − expenses
    var savingsRate: Double     // fraction of income kept
    var debtBalance: Double     // cards + the informal debts you opt to count
    var netWorth: Double        // assets − debts
    var retirementMonthly: Double // 401(k) user + employer match per month
    var retirementBalance: Double
    var informalCounted: Double   // informal debts currently counted
    var informalTotal: Double     // all non-forgiven informal debts
    var informalCountedCount: Int
    var informalTotalCount: Int
}

enum OverviewLogic {
    /// Average number of paychecks per month for the current cadence.
    static func paychecksPerMonth(periodLengthDays: Int) -> Double {
        guard periodLengthDays > 0 else { return 1 }
        return 365.25 / Double(periodLengthDays) / 12.0
    }

    /// Rent + every active expense recurring, expressed per month.
    static func monthlyRecurringExpense(rent: RentObligation?, recurrings: [RecurringTransaction]) -> Double {
        var total = rent?.amount ?? 0
        for r in recurrings where r.isActive && r.amount < 0 {
            switch r.cadence {
            case .daily: total += -r.amount * 30.4
            case .weekly: total += -r.amount * 4.33
            case .biweekly: total += -r.amount * 2.17
            case .monthly: total += -r.amount
            }
        }
        return total
    }

    static func creditBand(_ score: Int) -> String {
        switch score {
        case 800...: "Exceptional"
        case 740..<800: "Very good"
        case 670..<740: "Good"
        case 580..<670: "Fair"
        default: "Poor"
        }
    }

    static func compute(settings: AppSettings,
                        ledger: [LedgerEntry],
                        recurrings: [RecurringTransaction],
                        paychecks: [Paycheck],
                        workDays: [WorkDay],
                        rent: RentObligation?,
                        cards: [CreditCard],
                        buckets: [Bucket],
                        debts: [PersonalDebt],
                        calendar: Calendar = .current) -> CoreMetrics {
        let now = Date.now

        // Income (take-home) for the current calendar month — projects the month's paychecks + logged income.
        let bounds = InsightPeriod.thisMonth.bounds(settings: settings, calendar: calendar)
        let monthlyIncome = InsightsLogic.income(settings: settings, paychecks: paychecks, workDays: workDays,
                                                  entries: ledger, start: bounds.start, end: bounds.end, calendar: calendar)

        // Expenses (rent + recurring), cash flow, savings rate.
        let monthlyExpenses = monthlyRecurringExpense(rent: rent, recurrings: recurrings)
        let cashFlow = monthlyIncome - monthlyExpenses
        let savingsRate = monthlyIncome > 0 ? cashFlow / monthlyIncome : 0

        // Balances → net worth & debt.
        let checking = BalanceLogic.balance(asOf: now, anchorAmount: settings.currentCashBalance,
                                            anchorDate: settings.balanceAnchorDate, entries: ledger, calendar: calendar)
        let savings = settings.savingsBalance
        let funds = buckets.reduce(0) { $0 + $1.currentAmount }
        let retireBalance = RetirementLogic.balance(settings: settings, workDays: workDays, asOf: now, calendar: calendar)
        let cardOwed = cards.reduce(0) { $0 + CardLogic.balance(for: $1, entries: ledger, recurrings: recurrings, asOf: now, calendar: calendar) }
        let nonForgiven = debts.filter { $0.status != .forgiven }
        let counted = nonForgiven.filter { $0.countInNetWorth }
        let personalCounted = counted.reduce(0) { $0 + $1.amount }
        let informalTotal = nonForgiven.reduce(0) { $0 + $1.amount }
        let debtBalance = cardOwed + personalCounted
        let netWorth = checking + savings + funds + retireBalance - debtBalance

        // Retirement: this period's contribution + match, scaled to a month.
        let period = settings.upcomingPayPeriod
        let hrs = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays, calendar: calendar)
        let gross = BudgetMath.gross(hours: hrs, hourlyWage: settings.hourlyWage)
        let c = RetirementLogic.contribution(forGross: gross, at: period.payday, settings: settings, calendar: calendar)
        let retireMonthly = (c.user + c.match) * paychecksPerMonth(periodLengthDays: settings.periodLengthDays)

        return CoreMetrics(ficoScore: settings.ficoScore,
                           vantageScore: settings.vantageScore,
                           monthlyIncome: monthlyIncome,
                           monthlyExpenses: monthlyExpenses,
                           cashFlow: cashFlow,
                           savingsRate: savingsRate,
                           debtBalance: debtBalance,
                           netWorth: netWorth,
                           retirementMonthly: retireMonthly,
                           retirementBalance: retireBalance,
                           informalCounted: personalCounted,
                           informalTotal: informalTotal,
                           informalCountedCount: counted.count,
                           informalTotalCount: nonForgiven.count)
    }
}
