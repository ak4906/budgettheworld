//
//  BalanceHistoryView.swift
//  BudgetTheWorld
//
//  Balance over time: pick checking or a credit card, see the day-by-day history,
//  with monthly statement-due markers on cards. Reached from the Dashboard toolbar.
//

import SwiftUI
import SwiftData
import Charts

enum HistMode: String, CaseIterable, Identifiable { case graph = "Graph", calendar = "Calendar"; var id: String { rawValue } }

struct BalanceHistoryView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]

    @State private var selectedID: String = "checking"
    @State private var rangeDays: Int = 90
    @State private var mode: HistMode = .graph
    @State private var selectedDate: Date?

    private let ranges: [(label: String, days: Int)] = [("1M", 30), ("3M", 90), ("6M", 180), ("1Y", 365)]

    private var selectedCard: CreditCard? { cards.first { $0.name == selectedID } }
    private var isCard: Bool { selectedCard != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let settings = settingsList.first {
                    accountPicker
                    Picker("Mode", selection: $mode) {
                        ForEach(HistMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .graph {
                        let points = series(settings: settings)
                        rangePicker
                        chartCard(points)
                        statsCard(points)
                    } else {
                        BalanceCalendar(selectedID: selectedID, card: selectedCard)
                    }
                } else {
                    ContentUnavailableView("No data yet", systemImage: "chart.bar.xaxis").padding(.top, 60)
                }
            }
            .padding()
        }
        .background(Color.btwBackground)
        .navigationTitle("Balance History")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func series(settings: AppSettings) -> [BalanceHistoryLogic.Point] {
        if let card = selectedCard {
            return BalanceHistoryLogic.cardHistory(days: rangeDays, card: card, entries: ledger)
        }
        return BalanceHistoryLogic.checkingHistory(days: rangeDays, settings: settings, entries: ledger)
    }

    private var accountPicker: some View {
        Picker("Account", selection: $selectedID) {
            Text("Checking").tag("checking")
            ForEach(cards) { Text($0.name).tag($0.name) }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $rangeDays) {
            ForEach(ranges, id: \.days) { Text($0.label).tag($0.days) }
        }
        .pickerStyle(.segmented)
    }

    private func selectedPoint(_ points: [BalanceHistoryLogic.Point]) -> BalanceHistoryLogic.Point? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private func readoutColor(_ v: Double, isCard: Bool) -> Color {
        if isCard { return v > 0 ? .red : .green }
        return v < 0 ? .red : .primary
    }

    private func chartCard(_ points: [BalanceHistoryLogic.Point]) -> some View {
        let tint: Color = isCard ? .red : .green
        let dueDates: [Date] = {
            guard let card = selectedCard, let first = points.first?.date, let last = points.last?.date else { return [] }
            return BalanceHistoryLogic.dueDates(for: card, in: first...last)
        }()
        return Card(title: isCard ? "\(selectedID) owed" : "Checking balance",
                    systemImage: isCard ? "creditcard.fill" : "banknote.fill", tint: tint) {
            if points.count < 2 {
                Text("Not enough history yet — balances appear as transactions accumulate.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                let selected = selectedPoint(points)
                HStack {
                    if let selected {
                        Text(selected.date.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(selected.balance, format: .currency(code: "USD"))
                            .fontWeight(.semibold)
                            .foregroundStyle(readoutColor(selected.balance, isCard: isCard))
                    } else {
                        Text("Tap or drag the graph to read any day.").foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Date", p.date), y: .value("Balance", p.balance))
                            .foregroundStyle(tint.opacity(0.15))
                        LineMark(x: .value("Date", p.date), y: .value("Balance", p.balance))
                            .foregroundStyle(tint)
                            .interpolationMethod(.monotone)
                    }
                    ForEach(dueDates, id: \.self) { d in
                        RuleMark(x: .value("Due", d))
                            .foregroundStyle(.orange.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .center) {
                                Text("due").font(.system(size: 8)).foregroundStyle(.orange)
                            }
                    }
                    RuleMark(y: .value("Zero", 0))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    if let selected {
                        RuleMark(x: .value("Selected", selected.date))
                            .foregroundStyle(.secondary.opacity(0.6))
                        PointMark(x: .value("Selected", selected.date), y: .value("Balance", selected.balance))
                            .foregroundStyle(tint)
                            .symbolSize(90)
                    }
                }
                .frame(height: 240)
                .chartXSelection(value: $selectedDate)
                if isCard && !dueDates.isEmpty {
                    Text("Dashed orange lines mark monthly statement due dates.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func statsCard(_ points: [BalanceHistoryLogic.Point]) -> some View {
        let first = points.first?.balance ?? 0
        let last = points.last?.balance ?? 0
        let change = last - first
        let lo = points.map(\.balance).min() ?? 0
        let hi = points.map(\.balance).max() ?? 0
        let avg = points.isEmpty ? 0 : points.map(\.balance).reduce(0, +) / Double(points.count)
        let changeGood = isCard ? (change <= 0) : (change >= 0)
        return Card(title: "Summary", systemImage: "number", tint: .blue) {
            HStack {
                stat("Now", last, .primary)
                Divider().frame(height: 30)
                stat("Average", avg, .secondary)
                Divider().frame(height: 30)
                stat("Change", change, changeGood ? .green : .red)
            }
            HStack {
                stat("Low", lo, .secondary)
                Divider().frame(height: 30)
                stat("High", hi, .secondary)
            }
            Text("Over the last \(rangeDays) days\(isCard ? " on \(selectedID)" : ""). Average = the typical \(isCard ? "amount owed" : "balance") across the range. Change = now minus \(rangeDays) days ago (how much it \(isCard ? "rose or fell" : "grew or shrank")).")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func stat(_ label: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                .font(.callout.weight(.semibold))
                .foregroundStyle(color)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack { BalanceHistoryView() }
        .modelContainer(for: [AppSettings.self, LedgerEntry.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
