//
//  ForecastView.swift
//  BudgetTheWorld
//
//  Interactive projection of checking balance over the next year — a full day-by-day simulation
//  (paychecks, recurring, one-offs, rent + card payoffs on their due dates). Tap/drag to scrub,
//  pinch to zoom both axes (or pick a span), toggle Gross vs Net, overlay what-if scenarios,
//  ask "when will I have $X?", and see labeled event lines for paydays / rent / card due dates.
//

import SwiftUI
import SwiftData
import Charts

enum ForecastSpan: String, CaseIterable, Identifiable {
    case oneWeek, twoWeeks, oneMonth, threeMonths, sixMonths, oneYear
    var id: String { rawValue }
    var label: String {
        switch self {
        case .oneWeek: "1W"
        case .twoWeeks: "2W"
        case .oneMonth: "1M"
        case .threeMonths: "3M"
        case .sixMonths: "6M"
        case .oneYear: "1Y"
        }
    }
    var days: Int {
        switch self {
        case .oneWeek: 7
        case .twoWeeks: 14
        case .oneMonth: 31
        case .threeMonths: 92
        case .sixMonths: 183
        case .oneYear: 366
        }
    }
    var visibleSeconds: TimeInterval { Double(days) * 86_400 }
}

struct WhatIfItem: Identifiable {
    let id = UUID()
    var label: String
    var amount: Double           // positive magnitude
    var isExpense: Bool          // true = a purchase/cost, false = income/bonus
    var date: Date               // first (or only) occurrence
    var installments: Int        // 1 = one-time; N = number of equal payments
    var cadence: RecurringCadence // spacing between installments
    var enabled: Bool
}

struct ForecastView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query private var recurrings: [RecurringTransaction]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query(sort: \WorkDay.date, order: .reverse) private var workDays: [WorkDay]
    @Query private var rents: [RentObligation]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]

    @State private var sim: [DayBalance] = []
    @State private var events: [ChartEvent] = []
    @State private var points: [Point] = []
    @State private var span: ForecastSpan = .oneMonth
    @State private var visibleSeconds: Double = ForecastSpan.oneMonth.visibleSeconds
    @State private var baseSeconds: Double = ForecastSpan.oneMonth.visibleSeconds
    @State private var scrollX: Date = Calendar.current.startOfDay(for: .now)
    @State private var selectedDate: Date?
    @State private var netMode = false
    @State private var yZoom: Double = 1
    @State private var baseYZoom: Double = 1
    @State private var whenTarget: Double = 0
    @State private var scenarios: [WhatIfItem] = []
    @State private var showAddScenario = false

    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let balance: Double
    }

    private var rent: RentObligation? { rents.first }

    var body: some View {
        ScrollView {
            if let settings = settingsList.first {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Span", selection: $span) {
                        ForEach(ForecastSpan.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: span) { _, newValue in
                        visibleSeconds = newValue.visibleSeconds
                        baseSeconds = newValue.visibleSeconds
                        yZoom = 1
                        baseYZoom = 1
                    }

                    Picker("View", selection: $netMode) {
                        Text("By due date").tag(false)
                        Text("Net (after debt)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: netMode) { _, _ in rebuildPoints() }

                    readout

                    if points.isEmpty {
                        ProgressView().frame(height: 280).frame(maxWidth: .infinity)
                    } else {
                        chart.frame(height: 280)
                        legend
                    }

                    scenariosSection
                    summary
                    trendCard
                    whenCard

                    Text(netMode
                         ? "Net view: every card charge is subtracted the day it happens, so this is what you truly have after debt."
                         : "By-due-date view: cards and rent are assumed paid in full on their due dates. Toggle Net to subtract card debt immediately.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .padding()
                .task(id: signature(settings)) {
                    let r = ProjectionEngine.simulate(days: 366, settings: settings, entries: ledger, recurrings: recurrings, paychecks: paychecks, workDays: workDays, rent: rent, cards: cards)
                    sim = r.balances
                    events = r.events
                    rebuildPoints()
                }
            } else {
                ContentUnavailableView("No data yet", systemImage: "chart.xyaxis.line").padding(.top, 80)
            }
        }
        .background(Color.btwBackground)
        .navigationTitle("Forecast")
        .keyboardDoneButton()
        .sheet(isPresented: $showAddScenario) { AddScenarioSheet { scenarios.append($0) } }
    }

    private func rebuildPoints() {
        points = sim.map { Point(date: $0.date, balance: netMode ? $0.net : $0.gross) }
    }

    // MARK: Derived

    private var selectedPoint: Point? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var enabledScenarios: [WhatIfItem] { scenarios.filter { $0.enabled } }

    private var adjustedPoints: [Point] {
        guard !enabledScenarios.isEmpty else { return [] }
        let cal = Calendar.current
        return points.map { p in
            var delta = 0.0
            for s in enabledScenarios {
                let per = s.amount / Double(max(s.installments, 1))
                for k in 0..<max(s.installments, 1) {
                    let inst: Date
                    switch s.cadence {
                    case .daily: inst = cal.date(byAdding: .day, value: k, to: s.date) ?? s.date
                    case .weekly: inst = cal.date(byAdding: .day, value: k * 7, to: s.date) ?? s.date
                    case .biweekly: inst = cal.date(byAdding: .day, value: k * 14, to: s.date) ?? s.date
                    case .monthly: inst = cal.date(byAdding: .month, value: k, to: s.date) ?? s.date
                    }
                    if cal.startOfDay(for: inst) <= cal.startOfDay(for: p.date) {
                        delta += s.isExpense ? -per : per
                    }
                }
            }
            return Point(date: p.date, balance: p.balance + delta)
        }
    }

    private var selectedAdjustedBalance: Double? {
        guard let sel = selectedPoint, !enabledScenarios.isEmpty else { return nil }
        return adjustedPoints.first { $0.date == sel.date }?.balance
    }

    private func eventColor(_ kind: ChartEventKind) -> Color {
        switch kind {
        case .payday: .green
        case .rent: .orange
        case .card: .red
        }
    }

    /// Points within the currently-visible window (for the dynamic Outlook).
    private var visiblePoints: [Point] {
        let lo = scrollX
        let hi = scrollX.addingTimeInterval(visibleSeconds)
        let v = points.filter { $0.date >= lo && $0.date <= hi }
        return v.isEmpty ? points : v
    }

    /// Y-axis fit anchored at $0 (the x-axis): both bounds scale toward 0 as you pinch, so the
    /// $0 line always stays in view and zooming magnifies the region around your balance —
    /// instead of focusing on an empty band off the line.
    private var visibleYDomain: ClosedRange<Double> {
        let vals = points.map(\.balance) + adjustedPoints.map(\.balance)
        if vals.isEmpty { return -100...100 }
        let dataMin = vals.min() ?? 0
        let dataMax = vals.max() ?? 0
        var top = Swift.max(dataMax, 0)
        var bottom = Swift.min(dataMin, 0)
        if top == bottom { top += 100 }            // flat-line guard
        let pad = (top - bottom) * 0.08
        top += pad
        if bottom < 0 { bottom -= pad }            // a little room below a dip into the negative
        // Anchor $0 and zoom toward it: both ends move proportionally toward 0, keeping it in view.
        let z = Swift.max(yZoom, 0.0001)
        return (bottom / z) ... (top / z)
    }

    // MARK: Chart

    private var chart: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Zero", 0), yEnd: .value("Balance", p.balance))
                    .foregroundStyle(p.balance >= 0 ? Color.green.opacity(0.16) : Color.red.opacity(0.16))
            }
            ForEach(points) { p in
                LineMark(x: .value("Date", p.date), y: .value("Balance", p.balance), series: .value("Line", "Projected"))
                    .foregroundStyle(.green)
                    .interpolationMethod(.monotone)
            }
            ForEach(adjustedPoints) { p in
                LineMark(x: .value("Date", p.date), y: .value("Balance", p.balance), series: .value("Line", "With what-if"))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    .interpolationMethod(.monotone)
            }
            ForEach(trendLine) { p in
                LineMark(x: .value("Date", p.date), y: .value("Balance", p.balance), series: .value("Line", "Trend"))
                    .foregroundStyle(.gray.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
            ForEach(events) { ev in
                RuleMark(x: .value("Event", ev.date))
                    .foregroundStyle(eventColor(ev.kind).opacity(0.30))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.primary)
                .lineStyle(StrokeStyle(lineWidth: 2))
            if let sel = selectedPoint {
                RuleMark(x: .value("Selected", sel.date)).foregroundStyle(.secondary.opacity(0.6))
                PointMark(x: .value("Selected", sel.date), y: .value("Balance", sel.balance))
                    .foregroundStyle(sel.balance < 0 ? .red : .green)
                    .symbolSize(90)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartScrollableAxes(.horizontal)
        .chartScrollPosition(x: $scrollX)
        .chartXVisibleDomain(length: visibleSeconds)
        .chartYScale(domain: visibleYDomain)
        .chartYAxis { AxisMarks(format: .currency(code: "USD").precision(.fractionLength(0))) }
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    let m = Double(value.magnification)
                    visibleSeconds = min(max(baseSeconds / m, 3 * 86_400), 366 * 86_400)
                    yZoom = min(max(baseYZoom * m, 1), 60)
                }
                .onEnded { _ in baseSeconds = visibleSeconds; baseYZoom = yZoom }
        )
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendDot(.green, "Payday")
            legendDot(.orange, "Rent")
            legendDot(.red, "Card due")
            legendDot(.gray, "Trend")
            Spacer()
            Text("Pinch to zoom · keeps $0").foregroundStyle(.tertiary)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    // MARK: Readout / scenarios / summary

    private var readout: some View {
        Group {
            if let sel = selectedPoint {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(sel.date.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(sel.balance, format: .currency(code: "USD"))
                            .font(.headline).foregroundStyle(sel.balance < 0 ? .red : .primary)
                    }
                    if let adj = selectedAdjustedBalance {
                        HStack {
                            Text("with what-if").font(.caption).foregroundStyle(.blue)
                            Spacer()
                            Text(adj, format: .currency(code: "USD"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(adj < 0 ? .red : .blue)
                        }
                    }
                }
            } else {
                Text("Tap or drag the graph to read any day. Pinch to zoom.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var scenariosSection: some View {
        Card(title: "What if…", systemImage: "wand.and.stars", tint: .blue) {
            if scenarios.isEmpty {
                Text("Add a hypothetical purchase or windfall to see its effect (the blue dashed line).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach($scenarios) { $s in
                    HStack {
                        Toggle("", isOn: $s.enabled).labelsHidden()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.label.isEmpty ? (s.isExpense ? "Purchase" : "Income") : s.label).font(.subheadline)
                            Text("\(s.isExpense ? "−" : "+")\(s.amount.formatted(.currency(code: "USD")))\(s.installments > 1 ? " · \(s.installments)× \(s.cadence.displayName.lowercased())" : " · one-time") · from \(s.date.formatted(.dateTime.month().day()))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { scenarios.removeAll { $0.id == s.id } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }
            Button { showAddScenario = true } label: { Label("Add what-if", systemImage: "plus") }
                .font(.subheadline).padding(.top, 2)
        }
    }

    /// Reflects only the time span currently visible in the chart.
    private var summary: some View {
        let vis = visiblePoints
        let lowest = vis.min { $0.balance < $1.balance }
        let firstNegative = vis.first { $0.balance < 0 }
        let startIsToday = vis.first.map { Calendar.current.isDateInToday($0.date) } ?? false
        let rangeLabel: String = {
            guard let f = vis.first, let l = vis.last else { return "" }
            return "\(f.date.formatted(.dateTime.month().day())) – \(l.date.formatted(.dateTime.month().day()))"
        }()
        return Card(title: "Outlook · \(rangeLabel)", systemImage: "chart.xyaxis.line", tint: firstNegative == nil ? .green : .red) {
            HStack {
                stat(startIsToday ? "Now" : "Start", vis.first?.balance ?? 0)
                Divider().frame(height: 30)
                stat("Lowest", lowest?.balance ?? 0)
                Divider().frame(height: 30)
                stat("End", vis.last?.balance ?? 0)
            }
            if let firstNegative {
                Text("⚠️ Below $0 around \(firstNegative.date.formatted(.dateTime.month().day().year()))")
                    .font(.caption).foregroundStyle(.red)
            } else if let lowest {
                Text("Lowest in view: \(lowest.balance.formatted(.currency(code: "USD"))) on \(lowest.date.formatted(.dateTime.month().day()))")
                    .font(.caption).foregroundStyle(.green)
            }
        }
    }

    // MARK: Trend & earn rate (#22)

    private func regression(_ pts: [Point]) -> (slopePerDay: Double, intercept: Double)? {
        guard pts.count >= 2, let first = pts.first else { return nil }
        let xs = pts.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = pts.map(\.balance)
        let n = Double(pts.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard denom != 0 else { return nil }
        let slope = (n * sumXY - sumX * sumY) / denom
        let intercept = (sumY - slope * sumX) / n
        return (slope, intercept)
    }

    /// A straight regression line across the visible window — the dashed gray "trend".
    private var trendLine: [Point] {
        let vis = visiblePoints
        guard let reg = regression(vis), let first = vis.first, let last = vis.last, last.date > first.date else { return [] }
        let lastDays = last.date.timeIntervalSince(first.date) / 86_400
        return [
            Point(date: first.date, balance: reg.intercept),
            Point(date: last.date, balance: reg.intercept + reg.slopePerDay * lastDays)
        ]
    }

    private var trendCard: some View {
        let vis = visiblePoints
        let perDay = regression(vis)?.slopePerDay ?? 0
        let perWeek = perDay * 7
        let perMonth = perDay * 30.4
        let up = perDay >= 0
        return Card(title: "Trend & earn rate", systemImage: up ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill", tint: up ? .green : .red) {
            HStack {
                stat("Per week", perWeek)
                Divider().frame(height: 30)
                stat("Per month", perMonth)
            }
            ForEach(forecastTips(vis: vis, perDay: perDay), id: \.self) { tip in
                Label(tip, systemImage: "lightbulb.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Trend = the dashed straight line: your average direction over the visible window, smoothing out payday spikes.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func forecastTips(vis: [Point], perDay: Double) -> [String] {
        var out: [String] = []
        guard let lowest = vis.min(by: { $0.balance < $1.balance }) else { return out }
        let perWeek = perDay * 7
        let cal = Calendar.current
        let firstNeg = vis.first { $0.balance < 0 }
        if let firstNeg, lowest.balance < 0 {
            let daysToLow = max(cal.dateComponents([.day], from: cal.startOfDay(for: .now), to: lowest.date).day ?? 1, 1)
            let perDayCut = (-lowest.balance) / Double(daysToLow)
            out.append("Dips below $0 around \(firstNeg.date.formatted(.dateTime.month().day())). Trimming ~\(perDayCut.formatted(.currency(code: "USD")))/day (or adding income) keeps you above water.")
        } else if perWeek < 0 {
            out.append("Spending outpaces income by ~\(abs(perWeek).formatted(.currency(code: "USD")))/week here — positive for now, but trending down.")
        } else if perWeek > 0 {
            out.append("You're netting ~\(perWeek.formatted(.currency(code: "USD")))/week. Move some to savings or a goal so it doesn't quietly get spent.")
        }
        if firstNeg == nil {
            out.append("Lowest you'll dip to in view: \(lowest.balance.formatted(.currency(code: "USD"))) on \(lowest.date.formatted(.dateTime.month().day())).")
        }
        return out
    }

    // MARK: When will I have $X?

    private var whenCard: some View {
        Card(title: "When will I have…?", systemImage: "target", tint: .indigo) {
            LabeledContent("Target amount") {
                TextField("$0", value: $whenTarget, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if whenTarget > 0 {
                Text(whenResult)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Finds the first day your projected balance reaches this and stays at or above it — not a brief spike that dips back below. Reflects your what-if scenarios.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    /// Earliest date the balance reaches `whenTarget` and stays at/above it from then on.
    private var whenResult: String {
        guard whenTarget > 0, !points.isEmpty else { return "" }
        let series = enabledScenarios.isEmpty ? points : adjustedPoints
        if let lastBelow = series.lastIndex(where: { $0.balance < whenTarget }) {
            if lastBelow >= series.count - 1 {
                return "Not within the next year at this rate — try trimming expenses or add a what-if (more hours, a raise)."
            }
            let d = series[lastBelow + 1].date
            if Calendar.current.isDateInToday(d) { return "As of today — and it stays there." }
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: d).day ?? 0
            return "Around \(d.formatted(.dateTime.weekday(.abbreviated).month().day().year())) (~\(days) days) — and it stays at or above from then on."
        } else {
            return "You're already at or above this the whole time. 🎉"
        }
    }

    private func stat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .currency(code: "USD"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(value < 0 ? .red : .primary)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func signature(_ s: AppSettings) -> String {
        "\(ledger.count)-\(recurrings.count)-\(paychecks.count)-\(workDays.count)-\(cards.count)-\(rents.count)-\(s.currentCashBalance)-\(s.hourlyWage)-\(rent?.amount ?? 0)-\(s.balanceAnchorDate.timeIntervalSince1970)"
    }
}

private struct AddScenarioSheet: View {
    var onAdd: (WhatIfItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var amount = 0.0
    @State private var isExpense = true
    @State private var date = Date()
    @State private var isInstallment = false
    @State private var count = 3
    @State private var cadence: RecurringCadence = .monthly

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label (e.g. Air conditioner)", text: $label)
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Type", selection: $isExpense) {
                        Text("Expense").tag(true)
                        Text("Income / bonus").tag(false)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                Section {
                    Toggle("Pay over time (installments)", isOn: $isInstallment)
                    if isInstallment {
                        Stepper("\(count) payments", value: $count, in: 2...60)
                        Picker("Every", selection: $cadence) {
                            Text("Week").tag(RecurringCadence.weekly)
                            Text("2 weeks").tag(RecurringCadence.biweekly)
                            Text("Month").tag(RecurringCadence.monthly)
                        }
                    }
                } footer: {
                    Text(isInstallment
                         ? "Splits the amount into \(count) equal payments, one every \(cadence.displayName.lowercased()), starting on the date."
                         : "A one-time amount on the date.")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("What If…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(WhatIfItem(label: label, amount: amount, isExpense: isExpense, date: date,
                                         installments: isInstallment ? count : 1, cadence: cadence, enabled: true))
                        dismiss()
                    }
                    .disabled(amount <= 0)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { ForecastView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, PersonalDebt.self], inMemory: true)
}
