//
//  InsightsView.swift
//  BudgetTheWorld
//
//  The "wisdom" screen: where your money is going by category, and how your observed
//  spending fits the 50/30/20 guideline. Reached from the Spending tab.
//

import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query(sort: \WorkDay.date, order: .reverse) private var workDays: [WorkDay]

    @State private var period: InsightPeriod = .thisMonth
    @AppStorage("nwsOverrides") private var nwsOverridesRaw = ""
    @State private var showNWSEditor = false

    private var nwsOverrides: [String: String] {
        var dict: [String: String] = [:]
        for pair in nwsOverridesRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2 { dict[String(kv[0])] = String(kv[1]) }
        }
        return dict
    }

    var body: some View {
        ScrollView {
            if let settings = settingsList.first {
                let bounds = period.bounds(settings: settings)
                let cats = InsightsLogic.spendingByCategory(ledger, start: bounds.start, end: bounds.end)
                let totalSpent = cats.reduce(0) { $0 + $1.amount }
                let income = InsightsLogic.income(settings: settings, paychecks: paychecks, workDays: workDays, entries: ledger, start: bounds.start, end: bounds.end)
                let nws = InsightsLogic.needsWantsSavings(entries: ledger, income: income, start: bounds.start, end: bounds.end, overrides: nwsOverrides)
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(InsightPeriod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text("\(bounds.start.formatted(.dateTime.month().day())) – \(bounds.end.formatted(.dateTime.month().day().year()))")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    planCard(income: income, nws: nws, bounds: bounds)
                    categoryCard(cats: cats, total: totalSpent, bounds: bounds)
                }
                .padding()
            } else {
                ContentUnavailableView("No data yet", systemImage: "chart.pie")
                    .padding(.top, 80)
            }
        }
        .background(Color.btwBackground)
        .navigationTitle("Insights")
        .sheet(isPresented: $showNWSEditor) { NWSEditor() }
    }

    private func planCard(income: Double, nws: (needs: Double, wants: Double, savings: Double), bounds: (start: Date, end: Date)) -> some View {
        Card(title: "50 / 30 / 20 Plan", systemImage: "chart.bar.fill", tint: .indigo) {
            if income <= 0 {
                Text("Add income for this period (a paycheck lands, or log income) to see how your spending fits the 50/30/20 guideline.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                NavigationLink { NWSBreakdownView(bucket: "Needs", start: bounds.start, end: bounds.end, income: income, needs: nws.needs, wants: nws.wants, savings: nws.savings) } label: {
                    planRow("Needs", spent: nws.needs, income: income, target: 0.50, tint: .blue)
                }.buttonStyle(.plain)
                NavigationLink { NWSBreakdownView(bucket: "Wants", start: bounds.start, end: bounds.end, income: income, needs: nws.needs, wants: nws.wants, savings: nws.savings) } label: {
                    planRow("Wants", spent: nws.wants, income: income, target: 0.30, tint: .pink)
                }.buttonStyle(.plain)
                NavigationLink { NWSBreakdownView(bucket: "Savings", start: bounds.start, end: bounds.end, income: income, needs: nws.needs, wants: nws.wants, savings: nws.savings) } label: {
                    planRow("Savings", spent: nws.savings, income: income, target: 0.20, tint: .green)
                }.buttonStyle(.plain)
                Text("Against \(income, format: .currency(code: "USD")) take-home this period. Tap Needs, Wants, or Savings to see what's inside. Guideline: 50% / 30% / 20%.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Button { showNWSEditor = true } label: {
                Label("Customize needs / wants / savings", systemImage: "slider.horizontal.3")
            }
            .font(.caption)
            .padding(.top, 2)
        }
    }

    private func planRow(_ label: String, spent: Double, income: Double, target: Double, tint: Color) -> some View {
        let pct = income > 0 ? spent / income : 0
        let onTrack = label == "Savings" ? pct >= target : pct <= target
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).fontWeight(.medium)
                Spacer()
                Text("\(Int((pct * 100).rounded()))% · target \(Int(target * 100))%")
                    .font(.caption)
                    .foregroundStyle(onTrack ? .green : .orange)
            }
            ProgressView(value: min(pct, 1)).tint(onTrack ? tint : .orange)
            Text(spent, format: .currency(code: "USD"))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func categoryCard(cats: [CategorySpend], total: Double, bounds: (start: Date, end: Date)) -> some View {
        Card(title: "Where it's going", systemImage: "list.bullet.rectangle.fill", tint: .teal) {
            if cats.isEmpty {
                Text("No spending logged this period.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Total spent: \(total, format: .currency(code: "USD"))")
                    .font(.subheadline).fontWeight(.semibold)
                VStack(spacing: 10) {
                    ForEach(cats) { c in
                        let pct = total > 0 ? c.amount / total : 0
                        NavigationLink {
                            CategoryBreakdownView(category: c.category, start: bounds.start, end: bounds.end)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Label(c.category.displayName, systemImage: c.category.iconName)
                                        .font(.caption).fontWeight(.medium)
                                        .foregroundStyle(c.category.color)
                                    Spacer()
                                    Text("\(c.amount, format: .currency(code: "USD")) · \(Int((pct * 100).rounded()))%")
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                }
                                ProgressView(value: pct).tint(c.category.color)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

// MARK: - Needs / Wants / Savings editor

private struct NWSEditor: View {
    @AppStorage("nwsOverrides") private var nwsOverridesRaw = ""
    @Environment(\.dismiss) private var dismiss

    private let options: [SpendCategory] = SpendCategory.allCases.filter { $0 != .income && $0 != .savings }
    private let classes = ["Needs", "Wants", "Savings"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(options) { cat in
                        Picker(selection: binding(for: cat)) {
                            ForEach(classes, id: \.self) { Text($0).tag($0) }
                        } label: {
                            Label(cat.displayName, systemImage: cat.iconName)
                        }
                    }
                } footer: {
                    Text("Choose how each category counts toward the 50/30/20 plan: Needs (≤50%), Wants (≤30%), or Savings (≥20% of take-home).")
                }
                Section {
                    Button("Reset to defaults", role: .destructive) { nwsOverridesRaw = "" }
                }
            }
            .navigationTitle("Needs / Wants / Savings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func binding(for cat: SpendCategory) -> Binding<String> {
        Binding(
            get: { parse()[cat.rawValue] ?? cat.needsWantsSavings },
            set: { newVal in
                var dict = parse()
                if newVal == cat.needsWantsSavings { dict[cat.rawValue] = nil } else { dict[cat.rawValue] = newVal }
                nwsOverridesRaw = dict.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",")
            }
        )
    }

    private func parse() -> [String: String] {
        var dict: [String: String] = [:]
        for pair in nwsOverridesRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2 { dict[String(kv[0])] = String(kv[1]) }
        }
        return dict
    }
}

// MARK: - Drill-down views

private struct CategoryBreakdownView: View {
    let category: SpendCategory
    let start: Date
    let end: Date
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @State private var editingEntry: LedgerEntry?
    @State private var searchText = ""

    var body: some View {
        let bySub = InsightsLogic.grouped(category: category, by: { $0.subcategory ?? "Unlabeled" }, entries: ledger, start: start, end: end)
        let byPlace = InsightsLogic.grouped(category: category, by: { $0.merchant ?? "—" }, entries: ledger, start: start, end: end)
        let total = bySub.reduce(0) { $0 + $1.amount }
        let cal = Calendar.current
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        let txns = ledger.filter { e in
            guard e.category == category, e.amount < 0, !e.isCardPayment,
                  cal.startOfDay(for: e.date) >= cal.startOfDay(for: start),
                  cal.startOfDay(for: e.date) <= cal.startOfDay(for: end) else { return false }
            if q.isEmpty { return true }
            let hay = "\(e.rawDescription) \(e.subcategory ?? "") \(e.merchant ?? "") \(e.area ?? "")".lowercased()
            return hay.contains(q) || String(format: "%.2f", -e.amount).contains(q)
        }
        let chips = dedup(bySub.map(\.label).filter { $0 != "Unlabeled" } + byPlace.map(\.label).filter { $0 != "—" })
        return List {
            Section { LabeledContent("Total", value: total.formatted(.currency(code: "USD"))).font(.headline) }
            if !q.isEmpty {
                Section {
                    NavigationLink { PriceAnalyticsView(query: searchText) } label: {
                        Label("Price-check “\(searchText)” (all time, incl. items)", systemImage: "chart.dots.scatter")
                    }
                }
            }
            if !chips.isEmpty {
                Section {
                    FilterChipRow(labels: chips, search: $searchText)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                } header: { Text("Quick filter") }
            }
            if !bySub.isEmpty {
                Section {
                    ForEach(bySub, id: \.label) { row in
                        if row.label == "Unlabeled" {
                            HStack { Text(row.label); Spacer(); Text(row.amount, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                        } else {
                            NavigationLink { PriceAnalyticsView(query: row.label) } label: {
                                HStack { Text(row.label); Spacer(); Text(row.amount, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                            }
                        }
                    }
                } header: {
                    Text("By subcategory")
                } footer: {
                    Text("Tap a subcategory or place to see where it's cheapest and how its price has moved.")
                }
            }
            if !byPlace.isEmpty {
                Section("By place") {
                    ForEach(byPlace, id: \.label) { row in
                        if row.label == "—" {
                            HStack { Text(row.label); Spacer(); Text(row.amount, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                        } else {
                            NavigationLink { PriceAnalyticsView(query: row.label) } label: {
                                HStack { Text(row.label); Spacer(); Text(row.amount, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
            if !txns.isEmpty {
                Section(q.isEmpty ? "Transactions" : "Matching “\(searchText)”") {
                    ForEach(txns) { e in
                        Button { editingEntry = e } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.rawDescription).foregroundStyle(.primary)
                                    Text("\(e.date.formatted(.dateTime.month().day()))\(e.subcategory.map { " · \($0)" } ?? "")\(e.merchant.map { " · \($0)" } ?? "")")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(-e.amount, format: .currency(code: "USD")).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if !q.isEmpty {
                Section { Text("No transactions match “\(searchText)”.").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search \(category.displayName)…")
        .sheet(item: $editingEntry) { TransactionSheet(entry: $0, template: nil) }
    }

    private func dedup(_ arr: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in arr { let k = s.lowercased(); if !seen.contains(k) { seen.insert(k); out.append(s) } }
        return out
    }
}

private struct PriceAnalyticsView: View {
    let query: String
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]

    var body: some View {
        let stats = InsightsLogic.priceStats(matching: query, entries: ledger)
        let series = InsightsLogic.priceSeries(matching: query, entries: ledger)
        let avg = series.isEmpty ? 0 : series.reduce(0) { $0 + $1.price } / Double(series.count)
        let cheapest = stats.first { $0.merchant != "Unknown" && $0.count >= 1 } ?? stats.first
        List {
            if series.isEmpty {
                ContentUnavailableView("No purchases match", systemImage: "magnifyingglass",
                                       description: Text("Nothing matching “\(query)” yet."))
            } else {
                Section {
                    if let cheapest, stats.count > 1 {
                        LabeledContent("Cheapest on average", value: cheapest.merchant)
                        LabeledContent("…its average", value: cheapest.avg.formatted(.currency(code: "USD")))
                    }
                    LabeledContent("Overall average", value: avg.formatted(.currency(code: "USD")))
                    LabeledContent("Purchases (all time)", value: "\(series.count)")
                } header: {
                    Text("“\(query)”")
                }

                Section("Price over time") {
                    Chart {
                        ForEach(series) { p in
                            PointMark(x: .value("Date", p.date), y: .value("Price", p.price))
                                .foregroundStyle(by: .value("Place", p.merchant))
                        }
                        RuleMark(y: .value("Average", avg))
                            .foregroundStyle(.secondary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, alignment: .leading) {
                                Text("avg").font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                    }
                    .frame(height: 200)
                }

                Section("By place · cheapest average first") {
                    ForEach(stats) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.merchant).fontWeight(.medium)
                                Spacer()
                                Text("avg \(s.avg.formatted(.currency(code: "USD")))").foregroundStyle(.secondary)
                            }
                            Text("\(s.count)×  ·  \(s.min.formatted(.currency(code: "USD")))–\(s.max.formatted(.currency(code: "USD")))  ·  total \(s.total.formatted(.currency(code: "USD")))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Price check")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NWSBreakdownView: View {
    let bucket: String   // "Needs", "Wants", or "Savings"
    let start: Date
    let end: Date
    let income: Double
    let needs: Double
    let wants: Double
    let savings: Double
    @AppStorage("nwsOverrides") private var nwsOverridesRaw = ""
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @State private var editingEntry: LedgerEntry?
    @State private var searchText = ""

    private var overrides: [String: String] {
        var dict: [String: String] = [:]
        for pair in nwsOverridesRaw.split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2 { dict[String(kv[0])] = String(kv[1]) }
        }
        return dict
    }

    private var bucketTotal: Double {
        switch bucket {
        case "Needs": return needs
        case "Wants": return wants
        default: return savings
        }
    }

    private var txns: [LedgerEntry] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: start), hi = cal.startOfDay(for: end)
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        return ledger.filter { e in
            guard e.amount < 0, !e.isCardPayment,
                  cal.startOfDay(for: e.date) >= lo, cal.startOfDay(for: e.date) <= hi,
                  InsightsLogic.entryClass(e, overrides: overrides) == bucket else { return false }
            if q.isEmpty { return true }
            let hay = "\(e.rawDescription) \(e.category.displayName) \(e.subcategory ?? "") \(e.merchant ?? "") \(e.area ?? "")".lowercased()
            return hay.contains(q) || String(format: "%.2f", -e.amount).contains(q)
        }
    }

    private var categoryChips: [String] {
        let cal = Calendar.current
        let lo = cal.startOfDay(for: start), hi = cal.startOfDay(for: end)
        var seen = Set<String>(); var out: [String] = []
        for e in ledger where e.amount < 0 && !e.isCardPayment {
            guard cal.startOfDay(for: e.date) >= lo, cal.startOfDay(for: e.date) <= hi,
                  InsightsLogic.entryClass(e, overrides: overrides) == bucket else { continue }
            let name = e.category.displayName
            if !seen.contains(name) { seen.insert(name); out.append(name) }
        }
        return out
    }

    var body: some View {
        let rows = InsightsLogic.bucketCategories(bucket, entries: ledger, start: start, end: end, overrides: overrides)
        List {
            Section { LabeledContent("Total \(bucket)", value: bucketTotal.formatted(.currency(code: "USD"))).font(.headline) }

            if !categoryChips.isEmpty {
                Section {
                    FilterChipRow(labels: categoryChips, search: $searchText)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                } header: { Text("Quick filter") }
            }

            if bucket == "Savings" {
                Section("How it's calculated") {
                    LabeledContent("Take-home", value: income.formatted(.currency(code: "USD")))
                    LabeledContent("− Needs", value: needs.formatted(.currency(code: "USD")))
                    LabeledContent("− Wants", value: wants.formatted(.currency(code: "USD")))
                    LabeledContent("= Saved", value: savings.formatted(.currency(code: "USD")))
                }
            }

            if !rows.isEmpty {
                Section(bucket == "Savings" ? "Categorized as savings" : "What's in it") {
                    ForEach(rows, id: \.label) { row in
                        HStack { Text(row.label); Spacer(); Text(row.amount, format: .currency(code: "USD")).foregroundStyle(.secondary) }
                    }
                }
            }

            if !txns.isEmpty {
                Section(searchText.isEmpty ? "Transactions" : "Matching “\(searchText)”") {
                    ForEach(txns) { e in
                        Button { editingEntry = e } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(e.rawDescription).foregroundStyle(.primary)
                                    Text("\(e.category.displayName)\(e.subcategory.map { " · \($0)" } ?? "") · \(e.date.formatted(.dateTime.month().day()))")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(-e.amount, format: .currency(code: "USD")).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if bucket == "Savings" {
                Section {
                    Text("No transactions are categorized as Savings — savings here is simply what's left of your take-home after needs and wants. Tap a Need or Want to re-file anything that's miscategorized.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(bucket)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search \(bucket.lowercased())…")
        .sheet(item: $editingEntry) { TransactionSheet(entry: $0, template: nil) }
    }
}

// MARK: - Quick filter chips

private struct FilterChipRow: View {
    let labels: [String]
    @Binding var search: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    let active = search.lowercased() == label.lowercased()
                    Button {
                        search = active ? "" : label
                    } label: {
                        Text(label)
                            .font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(active ? Color.accentColor : Color.btwCard, in: Capsule())
                            .foregroundStyle(active ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

#Preview {
    NavigationStack { InsightsView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
