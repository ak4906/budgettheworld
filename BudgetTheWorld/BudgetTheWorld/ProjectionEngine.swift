//
//  ProjectionEngine.swift
//  BudgetTheWorld
//
//  Forward projection: given recurring items, one-off transactions, and upcoming paychecks,
//  estimate the checking balance at any future date. Powers the adjustable "Left to Spend" horizon.
//

import Foundation

/// A freely-adjustable time window: today, the N-th upcoming payday, end of month/year,
/// or any specific date the user picks.
enum SpendHorizon: Hashable {
    case today
    case payday(Int)         // n-th upcoming payday (1 = next)
    case endOfMonth
    case endOfYear
    case on(Date)            // a specific custom date

    func endDate(settings: AppSettings, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: .now)
        switch self {
        case .today:
            return today
        case .payday(let n):
            var period = BudgetMath.payPeriod(forPaydayOnOrAfter: .now, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            var i = 1
            while i < max(n, 1) {
                period = period.next(lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
                i += 1
            }
            return period.payday
        case .endOfMonth:
            guard let intv = calendar.dateInterval(of: .month, for: today) else { return today }
            return calendar.date(byAdding: .day, value: -1, to: intv.end) ?? today
        case .endOfYear:
            guard let intv = calendar.dateInterval(of: .year, for: today) else { return today }
            return calendar.date(byAdding: .day, value: -1, to: intv.end) ?? today
        case .on(let d):
            return calendar.startOfDay(for: d)
        }
    }

    var label: String {
        switch self {
        case .today: return "Today"
        case .payday(let n): return n <= 1 ? "Next payday" : "\(SpendHorizon.ordinal(n)) payday"
        case .endOfMonth: return "End of month"
        case .endOfYear: return "End of year"
        case .on(let d): return "By \(d.formatted(.dateTime.month().day().year()))"
        }
    }

    private static func ordinal(_ n: Int) -> String {
        switch n {
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// Compact string used to persist the chosen horizon across launches.
    var code: String {
        switch self {
        case .today: return "today"
        case .payday(let n): return "payday:\(n)"
        case .endOfMonth: return "endOfMonth"
        case .endOfYear: return "endOfYear"
        case .on(let d): return "on:\(d.timeIntervalSince1970)"
        }
    }

    init(code: String) {
        let parts = code.split(separator: ":")
        let head = String(parts.first ?? "")
        switch head {
        case "today": self = .today
        case "payday": self = .payday(parts.count > 1 ? (Int(parts[1]) ?? 1) : 1)
        case "endOfMonth": self = .endOfMonth
        case "endOfYear": self = .endOfYear
        case "on": self = .on(Date(timeIntervalSince1970: parts.count > 1 ? (Double(parts[1]) ?? 0) : 0))
        default: self = .payday(1)
        }
    }
}

/// How to express the Safe-to-Spend cushion: as a lump, or a sustainable rate.
enum RateBasis: String, CaseIterable, Identifiable {
    case total, perDay, perWeek, perMonth
    var id: String { rawValue }
    var label: String {
        switch self {
        case .total: "Total"
        case .perDay: "Day"
        case .perWeek: "Week"
        case .perMonth: "Month"
        }
    }
    var suffix: String {
        switch self {
        case .total: ""
        case .perDay: "/day"
        case .perWeek: "/week"
        case .perMonth: "/month"
        }
    }
    /// Spread the cushion evenly over the days until the horizon.
    func value(safe: Double, days: Int) -> Double {
        let d = Double(max(days, 1))
        switch self {
        case .total: return safe
        case .perDay: return safe / d
        case .perWeek: return safe / (d / 7.0)
        case .perMonth: return safe / (d / 30.0)
        }
    }
}

enum ProjectionEngine {

    /// How many times a recurring item fires strictly after `after`, through `through` (inclusive).
    static func occurrences(of r: RecurringTransaction, after: Date, through: Date, calendar: Calendar = .current) -> Int {
        guard r.isActive else { return 0 }
        let afterDay = calendar.startOfDay(for: after)
        let endDay = min(calendar.startOfDay(for: through), calendar.startOfDay(for: r.endDate))
        guard endDay > afterDay else { return 0 }
        var count = 0
        var d = calendar.startOfDay(for: r.startDate)
        var guardCount = 0
        while d <= endDay && guardCount < 4000 {
            if d > afterDay { count += 1 }
            guard let next = step(d, cadence: r.cadence, calendar: calendar), next > d else { break }
            d = next
            guardCount += 1
        }
        return count
    }

    private static func step(_ d: Date, cadence: RecurringCadence, calendar: Calendar) -> Date? {
        switch cadence {
        case .daily: return calendar.date(byAdding: .day, value: 1, to: d)
        case .weekly: return calendar.date(byAdding: .day, value: 7, to: d)
        case .biweekly: return calendar.date(byAdding: .day, value: 14, to: d)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: d)
        }
    }

    /// Net signed flow from all recurring items in (after, through].
    static func recurringFlow(_ recurrings: [RecurringTransaction], after: Date, through: Date, calendar: Calendar = .current) -> Double {
        recurrings.filter { $0.cardName == nil }.reduce(0.0) { sum, r in   // card-charged recurring goes on the card, not checking
            sum + Double(occurrences(of: r, after: after, through: through, calendar: calendar)) * r.amount
        }
    }

    /// Take-home pay for paydays landing in (after, through].
    static func projectedPay(settings: AppSettings, paychecks: [Paycheck], workDays: [WorkDay], after: Date, through: Date, calendar: Calendar = .current) -> Double {
        let netRatio = BudgetMath.averageNetRatio(paychecks, fallback: settings.defaultNetRatio)
        let afterDay = calendar.startOfDay(for: after)
        let endDay = calendar.startOfDay(for: through)
        guard endDay > afterDay else { return 0 }
        var total = 0.0
        var period = BudgetMath.payPeriod(forPaydayOnOrAfter: after, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
        var guardCount = 0
        while calendar.startOfDay(for: period.payday) <= endDay && guardCount < 60 {
            if calendar.startOfDay(for: period.payday) > afterDay {
                let hours = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays, calendar: calendar)
                total += BudgetMath.gross(hours: hours, hourlyWage: settings.hourlyWage) * netRatio
            }
            period = period.next(lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            guardCount += 1
        }
        return total
    }

    /// Projected checking balance at `future` = current balance + future one-offs + recurring + projected pay.
    static func projectedBalance(asOf future: Date, settings: AppSettings, entries: [LedgerEntry], recurrings: [RecurringTransaction], paychecks: [Paycheck], workDays: [WorkDay], calendar: Calendar = .current) -> Double {
        let base = BalanceLogic.balance(asOf: .now, anchorAmount: settings.currentCashBalance, anchorDate: settings.balanceAnchorDate, entries: entries, calendar: calendar)
        let today = calendar.startOfDay(for: .now)
        let end = calendar.startOfDay(for: future)
        guard end > today else { return base }
        let futureEntries = entries.filter {
            let d = calendar.startOfDay(for: $0.date)
            return $0.affectsChecking && d > today && d <= end
        }.reduce(0.0) { $0 + $1.amount }
        let recur = recurringFlow(recurrings, after: today, through: end, calendar: calendar)
        let pay = projectedPay(settings: settings, paychecks: paychecks, workDays: workDays, after: today, through: end, calendar: calendar)
        return base + futureEntries + recur + pay
    }

    /// Itemized inflows/outflows by `end` so the projection is fully transparent.
    static func breakdown(by end: Date, settings: AppSettings, entries: [LedgerEntry], recurrings: [RecurringTransaction], paychecks: [Paycheck], workDays: [WorkDay], rent: RentObligation?, cards: [CreditCard], essentialCategories: Set<String> = [], calendar: Calendar = .current) -> HorizonBreakdown {
        var b = HorizonBreakdown()
        let today = calendar.startOfDay(for: .now)
        let endDay = calendar.startOfDay(for: end)

        let balance = BalanceLogic.balance(asOf: .now, anchorAmount: settings.currentCashBalance, anchorDate: settings.balanceAnchorDate, entries: entries, calendar: calendar)
        b.inflows.append(ProjectionLine(label: "Balance now", amount: balance, count: 1))

        if endDay > today {
            let netRatio = BudgetMath.averageNetRatio(paychecks, fallback: settings.defaultNetRatio)
            var period = BudgetMath.payPeriod(forPaydayOnOrAfter: .now, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            var n = 1
            var guardC = 0
            while calendar.startOfDay(for: period.payday) <= endDay && guardC < 60 {
                if calendar.startOfDay(for: period.payday) > today {
                    let hrs = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays, calendar: calendar)
                    let net = BudgetMath.gross(hours: hrs, hourlyWage: settings.hourlyWage) * netRatio
                    if net > 0 {
                        b.inflows.append(ProjectionLine(label: "\(ordinalPaycheck(n)) paycheck · \(period.payday.formatted(.dateTime.month().day()))", amount: net, count: 1))
                    }
                    n += 1
                }
                period = period.next(lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
                guardC += 1
            }
        }

        for r in recurrings where r.cardName == nil {   // card-charged recurring shows up via the card balance, below
            let c = occurrences(of: r, after: today, through: end, calendar: calendar)
            guard c > 0 else { continue }
            let line = ProjectionLine(label: r.detail, amount: r.amount, count: c, isEssential: essentialCategories.contains(r.category.rawValue))
            if r.amount >= 0 { b.inflows.append(line) } else { b.outflows.append(line) }
        }

        for e in entries {
            let d = calendar.startOfDay(for: e.date)
            guard e.affectsChecking, d > today && d <= endDay else { continue }   // card charges show up via the card balance, not here
            let line = ProjectionLine(label: e.rawDescription, amount: e.amount, count: 1, isEssential: essentialCategories.contains(e.category.rawValue))
            if e.amount >= 0 { b.inflows.append(line) } else { b.outflows.append(line) }
        }

        if let rent, calendar.startOfDay(for: rent.dueDate) <= endDay {
            b.outflows.append(ProjectionLine(label: "Rent", amount: -rent.amount, count: 1, isEssential: essentialCategories.contains(SpendCategory.rent.rawValue)))
        }
        for card in cards where calendar.startOfDay(for: card.nextDueDate) <= endDay {
            let owed = CardLogic.balance(for: card, entries: entries, recurrings: recurrings, asOf: end, calendar: calendar)
            b.outflows.append(ProjectionLine(label: card.name, amount: -owed, count: 1, isEssential: true))
        }
        return b
    }

    private static func ordinalPaycheck(_ n: Int) -> String {
        switch n {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(n)th"
        }
    }

    /// Whether a recurring item fires on a given day.
    static func occursOn(_ r: RecurringTransaction, day: Date, calendar: Calendar = .current) -> Bool {
        guard r.isActive else { return false }
        let d = calendar.startOfDay(for: day)
        let start = calendar.startOfDay(for: r.startDate)
        let end = calendar.startOfDay(for: r.endDate)
        guard d >= start, d <= end else { return false }
        switch r.cadence {
        case .daily: return true
        case .weekly: return ((calendar.dateComponents([.day], from: start, to: d).day ?? 0) % 7) == 0
        case .biweekly: return ((calendar.dateComponents([.day], from: start, to: d).day ?? 0) % 14) == 0
        case .monthly: return calendar.component(.day, from: d) == calendar.component(.day, from: start)
        }
    }

    /// Day-by-day checking-balance simulation including EVERY known flow:
    /// paychecks, recurring (checking + card charges), one-off transactions, rent paid monthly
    /// on its due day, and each card paid in full on its monthly due day. Returns one entry per day.
    static func dailyBalances(days: Int, settings: AppSettings, entries: [LedgerEntry], recurrings: [RecurringTransaction], paychecks: [Paycheck], workDays: [WorkDay], rent: RentObligation?, cards: [CreditCard], calendar: Calendar = .current) -> [(date: Date, balance: Double)] {
        let today = calendar.startOfDay(for: .now)
        let endDate = calendar.date(byAdding: .day, value: max(days, 1), to: today) ?? today

        var checking = BalanceLogic.balance(asOf: .now, anchorAmount: settings.currentCashBalance, anchorDate: settings.balanceAnchorDate, entries: entries, calendar: calendar)
        var cardOwed: [String: Double] = [:]
        for c in cards { cardOwed[c.name] = CardLogic.balance(for: c, entries: entries, asOf: .now, calendar: calendar) }

        let netRatio = BudgetMath.averageNetRatio(paychecks, fallback: settings.defaultNetRatio)

        // Paydays → net pay
        var paydayNet: [Date: Double] = [:]
        var period = BudgetMath.payPeriod(forPaydayOnOrAfter: today, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
        var guardP = 0
        while calendar.startOfDay(for: period.payday) <= endDate, guardP < 80 {
            let pday = calendar.startOfDay(for: period.payday)
            if pday > today {
                let hrs = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays, calendar: calendar)
                paydayNet[pday, default: 0] += BudgetMath.gross(hours: hrs, hourlyWage: settings.hourlyWage) * netRatio
            }
            period = period.next(lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            guardP += 1
        }

        // Future one-off entries grouped by day
        var entriesByDay: [Date: [LedgerEntry]] = [:]
        for e in entries {
            let d = calendar.startOfDay(for: e.date)
            if d > today, d <= endDate { entriesByDay[d, default: []].append(e) }
        }

        let rentDueDay = rent.map { calendar.component(.day, from: $0.dueDate) }
        let cardDueDay: [String: Int] = Dictionary(uniqueKeysWithValues: cards.map { ($0.name, calendar.component(.day, from: $0.statementDueDate)) })

        var result: [(date: Date, balance: Double)] = [(today, checking)]
        for offset in 1...max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            let dom = calendar.component(.day, from: day)

            if let net = paydayNet[day] { checking += net }

            for r in recurrings where occursOn(r, day: day, calendar: calendar) {
                if let cn = r.cardName {
                    if r.amount < 0 { cardOwed[cn, default: 0] += -r.amount } else { checking += r.amount }
                } else {
                    checking += r.amount
                }
            }

            if let dayEntries = entriesByDay[day] {
                for e in dayEntries {
                    if e.affectsChecking { checking += e.amount }
                    if let cn = e.cardName { cardOwed[cn, default: 0] += e.isCardPayment ? e.amount : -e.amount }
                }
            }

            if let rentDueDay, dom == rentDueDay, let amt = rent?.amount { checking -= amt }

            for c in cards where cardDueDay[c.name] == dom {
                let owed = cardOwed[c.name] ?? 0
                if owed > 0 { checking -= owed; cardOwed[c.name] = 0 }
            }

            result.append((day, checking))
        }
        return result
    }

    /// Forward simulation returning a GROSS line (cards paid on their due dates) and a NET line
    /// (all card debt subtracted immediately — the "honest" view), plus labeled events.
    /// Rent and each card recur monthly from their *actual* next due date (not day-of-month from today).
    static func simulate(days: Int, settings: AppSettings, entries: [LedgerEntry], recurrings: [RecurringTransaction], paychecks: [Paycheck], workDays: [WorkDay], rent: RentObligation?, cards: [CreditCard], calendar: Calendar = .current) -> (balances: [DayBalance], events: [ChartEvent]) {
        let today = calendar.startOfDay(for: .now)
        let endDate = calendar.date(byAdding: .day, value: max(days, 1), to: today) ?? today
        var checking = BalanceLogic.balance(asOf: .now, anchorAmount: settings.currentCashBalance, anchorDate: settings.balanceAnchorDate, entries: entries, calendar: calendar)
        var cardOwed: [String: Double] = [:]
        for c in cards { cardOwed[c.name] = CardLogic.balance(for: c, entries: entries, asOf: .now, calendar: calendar) }
        let netRatio = BudgetMath.averageNetRatio(paychecks, fallback: settings.defaultNetRatio)

        var events: [ChartEvent] = []

        var paydayNet: [Date: Double] = [:]
        var period = BudgetMath.payPeriod(forPaydayOnOrAfter: today, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
        var guardP = 0
        while calendar.startOfDay(for: period.payday) <= endDate, guardP < 80 {
            let pday = calendar.startOfDay(for: period.payday)
            if pday > today {
                let hrs = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays, calendar: calendar)
                paydayNet[pday, default: 0] += BudgetMath.gross(hours: hrs, hourlyWage: settings.hourlyWage) * netRatio
                events.append(ChartEvent(date: pday, label: "Payday", kind: .payday))
            }
            period = period.next(lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            guardP += 1
        }

        var rentDueSet: Set<Date> = []
        if let rent {
            var d = calendar.startOfDay(for: rent.dueDate)
            while d < today { d = calendar.date(byAdding: .month, value: 1, to: d) ?? endDate.addingTimeInterval(1) }
            while d <= endDate {
                rentDueSet.insert(d)
                events.append(ChartEvent(date: d, label: "Rent", kind: .rent))
                d = calendar.date(byAdding: .month, value: 1, to: d) ?? endDate.addingTimeInterval(1)
            }
        }

        var cardDueByDay: [Date: [String]] = [:]
        for c in cards {
            var d = calendar.startOfDay(for: c.nextDueDate)
            while d < today { d = calendar.date(byAdding: .month, value: 1, to: d) ?? endDate.addingTimeInterval(1) }
            while d <= endDate {
                cardDueByDay[d, default: []].append(c.name)
                events.append(ChartEvent(date: d, label: c.name, kind: .card))
                d = calendar.date(byAdding: .month, value: 1, to: d) ?? endDate.addingTimeInterval(1)
            }
        }

        var entriesByDay: [Date: [LedgerEntry]] = [:]
        for e in entries {
            let d = calendar.startOfDay(for: e.date)
            if d > today, d <= endDate { entriesByDay[d, default: []].append(e) }
        }

        func totalOwed() -> Double { cardOwed.values.reduce(0, +) }
        var balances: [DayBalance] = [DayBalance(date: today, gross: checking, net: checking - totalOwed())]

        for offset in 1...max(days, 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { break }
            if let net = paydayNet[day] { checking += net }
            for r in recurrings where occursOn(r, day: day, calendar: calendar) {
                if let cn = r.cardName {
                    if r.amount < 0 { cardOwed[cn, default: 0] += -r.amount } else { checking += r.amount }
                } else {
                    checking += r.amount
                }
            }
            if let dayEntries = entriesByDay[day] {
                for e in dayEntries {
                    if e.affectsChecking { checking += e.amount }
                    if let cn = e.cardName { cardOwed[cn, default: 0] += e.isCardPayment ? e.amount : -e.amount }
                }
            }
            if rentDueSet.contains(day), let amt = rent?.amount { checking -= amt }
            if let names = cardDueByDay[day] {
                for n in names {
                    let owed = cardOwed[n] ?? 0
                    if owed > 0 { checking -= owed; cardOwed[n] = 0 }
                }
            }
            balances.append(DayBalance(date: day, gross: checking, net: checking - totalOwed()))
        }
        return (balances, events)
    }
}

struct DayBalance: Identifiable {
    let id = UUID()
    let date: Date
    let gross: Double   // cards paid on their due dates
    let net: Double     // all outstanding card debt subtracted immediately ("honest")
}

enum ChartEventKind { case payday, rent, card }

struct ChartEvent: Identifiable {
    let id = UUID()
    let date: Date
    let label: String
    let kind: ChartEventKind
}

struct ProjectionLine: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double      // signed, per occurrence
    let count: Int
    var isEssential: Bool = true
    var total: Double { amount * Double(count) }
}

struct HorizonBreakdown {
    var inflows: [ProjectionLine] = []
    var outflows: [ProjectionLine] = []
    var inflowTotal: Double { inflows.reduce(0) { $0 + $1.total } }
    var outflowTotal: Double { outflows.reduce(0) { $0 + $1.total } }   // <= 0
    var essentialOutflowTotal: Double { outflows.filter { $0.isEssential }.reduce(0) { $0 + $1.total } }
    var safe: Double { inflowTotal + outflowTotal }
    /// What's left for non-essentials ("fun") after covering essentials through the horizon.
    var freeToSpend: Double { inflowTotal + essentialOutflowTotal }
}
