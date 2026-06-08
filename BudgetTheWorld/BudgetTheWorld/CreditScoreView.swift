//
//  CreditScoreView.swift
//  BudgetTheWorld
//
//  Credit-score history: a trend graph of FICO + VantageScore over time, the latest
//  readings with their change, what-moves-your-score guidance, and a log of readings.
//  Reached by tapping the Credit Score tile in Overview.
//

import SwiftUI
import SwiftData
import Charts

struct CreditScoreView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CreditScoreEntry.date) private var history: [CreditScoreEntry]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]

    @State private var adding = false

    private var totalCardOwed: Double {
        cards.reduce(0) { $0 + CardLogic.balance(for: $1, entries: ledger) }
    }

    var body: some View {
        List {
            chartSection
            latestSection
            factorsSection
            historySection
        }
        .navigationTitle("Credit Score")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $adding) { AddScoreSheet() }
    }

    private var yDomain: ClosedRange<Int> {
        let vals = history.flatMap { [$0.fico, $0.vantage] }.filter { $0 > 0 }
        guard let lo = vals.min(), let hi = vals.max() else { return 300...850 }
        return max(300, lo - 20)...min(850, hi + 20)
    }

    @ViewBuilder private var chartSection: some View {
        Section {
            if history.count >= 2 {
                Chart {
                    ForEach(history) { e in
                        if e.fico > 0 {
                            LineMark(x: .value("Date", e.date), y: .value("Score", e.fico),
                                     series: .value("Type", "FICO"))
                                .foregroundStyle(by: .value("Type", "FICO"))
                            PointMark(x: .value("Date", e.date), y: .value("Score", e.fico))
                                .foregroundStyle(by: .value("Type", "FICO"))
                        }
                    }
                    ForEach(history) { e in
                        if e.vantage > 0 {
                            LineMark(x: .value("Date", e.date), y: .value("Score", e.vantage),
                                     series: .value("Type", "Vantage"))
                                .foregroundStyle(by: .value("Type", "Vantage"))
                            PointMark(x: .value("Date", e.date), y: .value("Score", e.vantage))
                                .foregroundStyle(by: .value("Type", "Vantage"))
                        }
                    }
                }
                .chartForegroundStyleScale(["FICO": Color.blue, "Vantage": Color.purple])
                .chartYScale(domain: yDomain)
                .frame(height: 220)
            } else {
                Text("Log at least two readings to see your trend. Tap ➕ to add today's scores.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Trend")
        }
    }

    @ViewBuilder private var latestSection: some View {
        if let last = history.last {
            let prev = history.count >= 2 ? history[history.count - 2] : nil
            Section {
                scoreRow("FICO", last.fico, prev?.fico)
                scoreRow("VantageScore", last.vantage, prev?.vantage)
            } header: {
                Text("Latest")
            } footer: {
                Text("As of \(last.date.formatted(.dateTime.month().day().year()))")
            }
        }
    }

    private func scoreRow(_ label: String, _ score: Int, _ previous: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            if score > 0 {
                if let p = previous, p > 0, p != score {
                    let d = score - p
                    Text("\(d > 0 ? "▲" : "▼")\(abs(d))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(d > 0 ? Color.green : Color.red)
                }
                Text("\(score)").fontWeight(.semibold)
                Text(OverviewLogic.creditBand(score)).font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var factorsSection: some View {
        Section {
            factorRow("Payment history", "35%", "Pay every bill on time — the single biggest factor.")
            factorRow("Amounts owed (utilization)", "30%", "Keep card balances low vs their limits — under ~30%, ideally under 10%.")
            factorRow("Length of history", "15%", "Older accounts help; avoid closing your oldest card.")
            factorRow("Credit mix", "10%", "A mix of cards and loans can help a little.")
            factorRow("New credit", "10%", "Space out new applications to limit hard inquiries.")
        } header: {
            Text("What moves your score")
        } footer: {
            if totalCardOwed > 0 {
                Text("Your cards currently report \(totalCardOwed, format: .currency(code: "USD")) owed. Paying that down lowers utilization — log a reading afterward to see the effect. (Approximate FICO weightings.)")
            } else {
                Text("Approximate FICO weightings. Log a reading after a big change (paying off a card, opening an account) to track its effect.")
            }
        }
    }

    private func factorRow(_ title: String, _ weight: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(weight).font(.caption.weight(.semibold)).foregroundStyle(.blue)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var historySection: some View {
        if !history.isEmpty {
            Section("Readings") {
                ForEach(history.reversed()) { e in
                    HStack {
                        Text(e.date.formatted(.dateTime.month().day().year()))
                        if let n = e.note, !n.isEmpty {
                            Text(n).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(scoreText(e)).foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteEntries)
            }
        }
    }

    private func scoreText(_ e: CreditScoreEntry) -> String {
        switch (e.fico > 0, e.vantage > 0) {
        case (true, true): "F \(e.fico) · V \(e.vantage)"
        case (true, false): "FICO \(e.fico)"
        case (false, true): "Vantage \(e.vantage)"
        default: "—"
        }
    }

    private func deleteEntries(_ offsets: IndexSet) {
        let reversed = Array(history.reversed())
        for i in offsets { context.delete(reversed[i]) }
        try? context.save()
        // Keep AppSettings showing the newest remaining reading.
        let remaining = (try? context.fetch(FetchDescriptor<CreditScoreEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        if let s = settingsList.first {
            s.ficoScore = remaining.last(where: { $0.fico > 0 })?.fico ?? 0
            s.vantageScore = remaining.last(where: { $0.vantage > 0 })?.vantage ?? 0
            try? context.save()
        }
    }
}

// MARK: - Add a reading

private struct AddScoreSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var date = Date.now
    @State private var fico = 0
    @State private var vantage = 0
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                Section("FICO") {
                    numberField($fico, "e.g. 720")
                    if fico > 0 { Text(OverviewLogic.creditBand(fico)).font(.caption).foregroundStyle(.secondary) }
                }
                Section("VantageScore") {
                    numberField($vantage, "e.g. 735")
                    if vantage > 0 { Text(OverviewLogic.creditBand(vantage)).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("e.g. “after paying off the credit card”")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Log Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(fico <= 0 && vantage <= 0)
                }
            }
            .onAppear {
                if let s = settingsList.first {
                    if fico == 0 { fico = s.ficoScore }
                    if vantage == 0 { vantage = s.vantageScore }
                }
            }
        }
    }

    private func numberField(_ value: Binding<Int>, _ placeholder: String) -> some View {
        LabeledContent("Score") {
            TextField(placeholder, value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        let f = fico > 0 ? min(max(fico, 300), 850) : 0
        let v = vantage > 0 ? min(max(vantage, 300), 850) : 0
        context.insert(CreditScoreEntry(date: date, fico: f, vantage: v, note: note.isEmpty ? nil : note))
        try? context.save()
        // Keep the Overview tile showing the newest reading.
        let all = (try? context.fetch(FetchDescriptor<CreditScoreEntry>(sortBy: [SortDescriptor(\.date)]))) ?? []
        if let s = settingsList.first {
            if let latestF = all.last(where: { $0.fico > 0 })?.fico { s.ficoScore = latestF }
            if let latestV = all.last(where: { $0.vantage > 0 })?.vantage { s.vantageScore = latestV }
            try? context.save()
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { CreditScoreView() }
        .modelContainer(for: [AppSettings.self, CreditScoreEntry.self, CreditCard.self, LedgerEntry.self], inMemory: true)
}
