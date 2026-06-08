//
//  BalanceCalendar.swift
//  BudgetTheWorld
//
//  A month calendar for the selected account: each day shows its end-of-day balance and a dot
//  if anything happened (blue = real transactions) or is planned (orange = future recurring).
//  Tap a day to see — and edit — that day's transactions. Used as the "Calendar" mode of
//  Balance History.
//

import SwiftUI
import SwiftData

enum CalMode: String, CaseIterable, Identifiable { case balance = "Balance", spending = "Activity"; var id: String { rawValue } }

struct BalanceCalendar: View {
    let selectedID: String        // "checking" or a card's name
    let card: CreditCard?

    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query private var recurrings: [RecurringTransaction]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query(sort: \WorkDay.date, order: .reverse) private var workDays: [WorkDay]
    @Query private var rents: [RentObligation]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]

    @State private var monthAnchor: Date = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
    @State private var balanceByDay: [Date: Double] = [:]
    @State private var selectedDay: DayRef?
    @State private var calMode: CalMode = .balance

    private let cal = Calendar.current
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            Picker("Show", selection: $calMode) {
                ForEach(CalMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            header
            weekdayRow
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(gridDays, id: \.self) { cell($0) }
            }
            legend
            footer
        }
        .padding()
        .background(Color.btwCard, in: RoundedRectangle(cornerRadius: 16))
        .task(id: taskKey) { recompute() }
        .sheet(item: $selectedDay) { ref in
            DayDetailView(day: ref.date, card: card, balance: balanceByDay[cal.startOfDay(for: ref.date)])
        }
    }

    private var taskKey: String {
        "\(selectedID)-\(monthAnchor.timeIntervalSince1970)-\(ledger.count)-\(recurrings.count)"
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                    .font(.headline)
                Spacer()
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
            }
            if !cal.isDate(monthAnchor, equalTo: .now, toGranularity: .month) {
                Button("Jump to today") {
                    monthAnchor = cal.dateInterval(of: .month, for: .now)?.start ?? .now
                }
                .font(.caption)
            }
        }
    }

    private var weekdayRow: some View {
        HStack(spacing: 2) {
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 3) { Circle().fill(.blue).frame(width: 6, height: 6); Text("happened") }
            HStack(spacing: 3) { Circle().fill(.orange).frame(width: 6, height: 6); Text("planned") }
            Spacer()
            Text(calMode == .spending ? (card != nil ? "charged" : "in / out") : (card != nil ? "amount owed" : "balance")).foregroundStyle(.tertiary)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    // MARK: Cell

    private func cell(_ day: Date) -> some View {
        let inMonth = cal.isDate(day, equalTo: monthAnchor, toGranularity: .month)
        let isToday = cal.isDateInToday(day)
        let bal = balanceByDay[cal.startOfDay(for: day)]
        let real = realEntries(on: day)
        let proj = projected(on: day)
        return Button {
            selectedDay = DayRef(date: day)
        } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: day))")
                    .font(.caption2)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isToday ? Color.accentColor : .primary)
                if calMode == .balance {
                    if let bal {
                        Text(abbrev(bal))
                            .font(.system(size: 9))
                            .foregroundStyle(balanceColor(bal))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                } else if card != nil {
                    let spend = daySpending(on: day)
                    if spend > 0 {
                        Text(abbrev(spend))
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                } else {
                    let net = dayNet(on: day)
                    if net != 0 {
                        Text((net > 0 ? "+" : "") + abbrev(net))
                            .font(.system(size: 9))
                            .foregroundStyle(net >= 0 ? .green : .red)
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }
                }
                Circle()
                    .fill(!real.isEmpty ? Color.blue : (!proj.isEmpty ? Color.orange : Color.clear))
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.vertical, 2)
            .background(isToday ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .opacity(inMonth ? 1 : 0.28)
        }
        .buttonStyle(.plain)
        .disabled(!inMonth)
    }

    private func balanceColor(_ v: Double) -> Color {
        if card != nil { return v > 0 ? .red : .green }   // owed: red when you owe, green at $0
        return v < 0 ? .red : .secondary
    }

    // MARK: Data

    private func realEntries(on day: Date) -> [LedgerEntry] {
        ledger.filter { e in
            guard cal.isDate(e.date, inSameDayAs: day) else { return false }
            if let card { return e.cardName == card.name }
            return e.affectsChecking
        }
    }

    private func projected(on day: Date) -> [RecurringTransaction] {
        guard cal.startOfDay(for: day) > cal.startOfDay(for: .now) else { return [] }
        return recurrings.filter { r in
            ProjectionEngine.occursOn(r, day: day) && (card == nil ? r.cardName == nil : r.cardName == card?.name)
        }
    }

    private func daySpending(on day: Date) -> Double {
        var total = 0.0
        for e in realEntries(on: day) where e.amount < 0 { total += -e.amount }
        for r in projected(on: day) where r.amount < 0 { total += -r.amount }
        return total
    }

    private func dayIncome(on day: Date) -> Double {
        var total = 0.0
        for e in realEntries(on: day) where e.amount > 0 { total += e.amount }
        for r in projected(on: day) where r.amount > 0 { total += r.amount }
        return total
    }
    private func dayNet(on day: Date) -> Double { dayIncome(on: day) - daySpending(on: day) }
    private var monthIncome: Double { inMonthDays.reduce(0) { $0 + dayIncome(on: $1) } }

    private var inMonthDays: [Date] { gridDays.filter { cal.isDate($0, equalTo: monthAnchor, toGranularity: .month) } }
    private var monthSpending: Double { inMonthDays.reduce(0) { $0 + daySpending(on: $1) } }
    private var monthTxnCount: Int {
        inMonthDays.reduce(0) { acc, d in
            acc + realEntries(on: d).filter { $0.amount < 0 }.count + projected(on: d).filter { $0.amount < 0 }.count
        }
    }
    private var endOfMonthBalance: Double? {
        guard let last = inMonthDays.last else { return nil }
        return balanceByDay[cal.startOfDay(for: last)]
    }

    private var footer: some View {
        HStack {
            if calMode == .spending {
                if card != nil {
                    Text("\(monthTxnCount) charge\(monthTxnCount == 1 ? "" : "s") this month")
                    Spacer()
                    Text(monthSpending, format: .currency(code: "USD")).fontWeight(.semibold).foregroundStyle(.red)
                } else {
                    Text("In \(monthIncome.formatted(.currency(code: "USD")))").foregroundStyle(.green)
                    Spacer()
                    Text("Spent \(monthSpending.formatted(.currency(code: "USD")))").foregroundStyle(.red)
                }
            } else {
                Text(card != nil ? "End-of-month owed" : "End-of-month balance")
                Spacer()
                if let eom = endOfMonthBalance {
                    Text(eom, format: .currency(code: "USD"))
                        .fontWeight(.semibold)
                        .foregroundStyle(balanceColor(eom))
                }
            }
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func recompute() {
        let days = gridDays
        var map: [Date: Double] = [:]
        if let card {
            let today = cal.startOfDay(for: .now)
            // Past: reconstruct backward from today's owed (same as the graph). CardLogic.balance(asOf:)
            // clamps to the anchor for dates before it, which made every past day read the same.
            let firstDay = cal.startOfDay(for: days.first ?? today)
            let span = max((cal.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 2, 1)
            var past: [Date: Double] = [:]
            for p in BalanceHistoryLogic.cardHistory(days: span, card: card, entries: ledger, calendar: cal) {
                past[cal.startOfDay(for: p.date)] = p.balance
            }
            for d in days {
                let key = cal.startOfDay(for: d)
                map[key] = key <= today ? past[key] : CardLogic.balance(for: card, entries: ledger, recurrings: recurrings, asOf: d, calendar: cal)
            }
        } else if let settings = settingsList.first {
            let today = cal.startOfDay(for: .now)
            // Future: forward simulation (paychecks + recurring + rent/cards on due dates).
            let sim = ProjectionEngine.simulate(days: 400, settings: settings, entries: ledger, recurrings: recurrings,
                                                paychecks: paychecks, workDays: workDays, rent: rents.first, cards: cards).balances
            var future: [Date: Double] = [:]
            for db in sim { future[cal.startOfDay(for: db.date)] = db.gross }
            // Past: reconstruct backward from today's balance.
            let firstDay = cal.startOfDay(for: days.first ?? today)
            let span = max((cal.dateComponents([.day], from: firstDay, to: today).day ?? 0) + 2, 1)
            var past: [Date: Double] = [:]
            for p in BalanceHistoryLogic.checkingHistory(days: span, settings: settings, entries: ledger, calendar: cal) {
                past[cal.startOfDay(for: p.date)] = p.balance
            }
            for d in days {
                let key = cal.startOfDay(for: d)
                map[key] = key <= today ? past[key] : future[key]
            }
        }
        balanceByDay = map
    }

    // MARK: Calendar math

    private func shiftMonth(_ delta: Int) {
        if let d = cal.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = cal.dateInterval(of: .month, for: d)?.start ?? d
        }
    }

    private var weekdaySymbols: [String] {
        let syms = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(syms[shift...] + syms[..<shift])
    }

    /// 6 weeks (42 cells) covering the month, with leading/trailing days from adjacent months.
    private var gridDays: [Date] {
        guard let monthInterval = cal.dateInterval(of: .month, for: monthAnchor) else { return [] }
        let firstOfMonth = monthInterval.start
        let weekdayOfFirst = cal.component(.weekday, from: firstOfMonth)
        let leading = (weekdayOfFirst - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -leading, to: firstOfMonth) ?? firstOfMonth
        var days: [Date] = []
        var d = cal.startOfDay(for: start)
        for _ in 0..<42 {
            days.append(d)
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return days
    }

    private func abbrev(_ v: Double) -> String {
        let a = abs(v)
        let sign = v < 0 ? "-" : ""
        if a >= 1000 { return String(format: "%@$%.1fk", sign, a / 1000) }
        return String(format: "%@$%.0f", sign, a)
    }
}

private struct DayRef: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

// MARK: - Day detail

private struct DayDetailView: View {
    let day: Date
    let card: CreditCard?
    let balance: Double?

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query private var recurrings: [RecurringTransaction]
    @State private var editingEntry: LedgerEntry?

    private let cal = Calendar.current

    private var real: [LedgerEntry] {
        ledger.filter { e in
            guard cal.isDate(e.date, inSameDayAs: day) else { return false }
            if let card { return e.cardName == card.name }
            return e.affectsChecking
        }
    }
    private var planned: [RecurringTransaction] {
        guard cal.startOfDay(for: day) > cal.startOfDay(for: .now) else { return [] }
        return recurrings.filter { r in
            ProjectionEngine.occursOn(r, day: day) && (card == nil ? r.cardName == nil : r.cardName == card?.name)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let balance {
                    Section {
                        LabeledContent(card != nil ? "Amount owed (end of day)" : "Balance (end of day)",
                                       value: balance.formatted(.currency(code: "USD")))
                            .font(.headline)
                    }
                }
                Section("Transactions") {
                    if real.isEmpty {
                        Text(planned.isEmpty ? "Nothing on this day." : "No real transactions yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(real) { e in
                            Button { editingEntry = e } label: { dayRow(e) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !planned.isEmpty {
                    Section {
                        ForEach(planned) { r in
                            HStack {
                                Image(systemName: "repeat").font(.caption).foregroundStyle(.orange)
                                Text(r.detail)
                                Spacer()
                                Text(r.amount, format: .currency(code: "USD")).foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Planned (recurring)")
                    } footer: {
                        Text("Projected from your recurring items — not yet real transactions.")
                    }
                }
            }
            .navigationTitle(day.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingEntry) { TransactionSheet(entry: $0, template: nil) }
        }
    }

    private func dayRow(_ e: LedgerEntry) -> some View {
        let subtitle = e.category.displayName + (e.subcategory.map { " · \($0)" } ?? "")
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.rawDescription).foregroundStyle(.primary)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(e.amount, format: .currency(code: "USD"))
                .foregroundStyle(e.amount < 0 ? Color.primary : Color.green)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
    }
}
