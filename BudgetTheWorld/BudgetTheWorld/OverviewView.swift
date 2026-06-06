//
//  OverviewView.swift
//  BudgetTheWorld
//
//  The "everything at a glance" screen: the eight core metrics (credit score, monthly income &
//  expenses, cash flow, debt, net worth, savings rate, retirement) in a Monarch-style grid.
//  Reached from the Dashboard toolbar (the grid icon).
//

import SwiftUI
import SwiftData

struct OverviewView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query private var recurrings: [RecurringTransaction]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query(sort: \WorkDay.date, order: .reverse) private var workDays: [WorkDay]
    @Query private var rents: [RentObligation]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @Query(sort: \Bucket.sortIndex) private var buckets: [Bucket]
    @Query private var debts: [PersonalDebt]

    @State private var showCreditEditor = false
    @State private var showInformal = false

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            if let settings = settingsList.first {
                let m = OverviewLogic.compute(settings: settings, ledger: ledger, recurrings: recurrings,
                                              paychecks: paychecks, workDays: workDays, rent: rents.first,
                                              cards: cards, buckets: buckets, debts: debts)
                VStack(spacing: 12) {
                    netWorthCard(m)
                    LazyVGrid(columns: cols, spacing: 12) {
                        creditTile(m)
                        tile("Monthly Income", "arrow.down.circle.fill", .green,
                             money(m.monthlyIncome), "take-home, this month")
                        tile("Monthly Expenses", "arrow.up.circle.fill", .orange,
                             money(m.monthlyExpenses), "rent + recurring")
                        tile("Cash Flow", "arrow.left.arrow.right.circle.fill", m.cashFlow >= 0 ? .green : .red,
                             money(m.cashFlow), m.cashFlow >= 0 ? "left over each month" : "short each month",
                             valueColor: m.cashFlow < 0 ? .red : .primary)
                        tile("Savings Rate", "percent", savingsColor(m.savingsRate),
                             pct(m.savingsRate), savingsLabel(m.savingsRate),
                             valueColor: m.savingsRate < 0 ? .red : .primary)
                        tile("Debt Balance", "creditcard.fill", m.debtBalance > 0 ? .red : .green,
                             money(m.debtBalance), "cards + counted informal",
                             valueColor: m.debtBalance > 0 ? .red : .primary)
                        tile("Retirement", "chart.line.uptrend.xyaxis", .purple,
                             money(m.retirementMonthly) + "/mo", "401(k) bal \(money(m.retirementBalance))")
                    }
                    Text("Estimates from your wage, schedule, recurring items, balances and 401(k). Add recurring expenses and a credit score to sharpen them.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            } else {
                ContentUnavailableView("No data yet", systemImage: "square.grid.2x2").padding(.top, 80)
            }
        }
        .background(Color.btwBackground)
        .navigationTitle("Overview")
        .sheet(isPresented: $showCreditEditor) { CreditScoreEditor() }
        .sheet(isPresented: $showInformal) { InformalDebtsSheet() }
    }

    private func netWorthCard(_ m: CoreMetrics) -> some View {
        Card(title: "Net Worth", systemImage: "chart.line.uptrend.xyaxis", tint: .purple) {
            Text(m.netWorth, format: .currency(code: "USD"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(m.netWorth < 0 ? .red : .primary)
            Text("Everything you have − everything you owe (checking + funds + 401(k) − debts).")
                .font(.caption).foregroundStyle(.secondary)
            if m.informalTotalCount > 0 {
                Button { showInformal = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                        Text("Informal debts: \(money(m.informalCounted)) of \(money(m.informalTotal)) counted (\(m.informalCountedCount)/\(m.informalTotalCount))")
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption2)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
    }

    private func creditTile(_ m: CoreMetrics) -> some View {
        let value: String
        let sub: String
        if m.ficoScore > 0 && m.vantageScore > 0 {
            value = "\(m.ficoScore) / \(m.vantageScore)"
            sub = "FICO / Vantage"
        } else if m.ficoScore > 0 {
            value = "\(m.ficoScore)"
            sub = "FICO · \(OverviewLogic.creditBand(m.ficoScore))"
        } else if m.vantageScore > 0 {
            value = "\(m.vantageScore)"
            sub = "Vantage · \(OverviewLogic.creditBand(m.vantageScore))"
        } else {
            value = "—"
            sub = "Tap to add"
        }
        return Button { showCreditEditor = true } label: {
            tile("Credit Score", "gauge.medium", .blue, value, sub)
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, _ icon: String, _ tint: Color,
                      _ value: String, _ subtitle: String, valueColor: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold)).foregroundStyle(tint).lineLimit(1)
            Text(value)
                .font(.title3.weight(.bold)).foregroundStyle(valueColor)
                .minimumScaleFactor(0.5).lineLimit(1)
            Text(subtitle)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .padding(14)
        .background(Color.btwCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private func money(_ v: Double) -> String { v.formatted(.currency(code: "USD").precision(.fractionLength(0))) }
    private func pct(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
    private func savingsColor(_ r: Double) -> Color { r >= 0.2 ? .green : (r >= 0 ? .orange : .red) }
    private func savingsLabel(_ r: Double) -> String {
        r >= 0.2 ? "great — 20%+ goal" : (r >= 0 ? "building toward 20%" : "spending over income")
    }
}

// MARK: - Credit score editor

private struct CreditScoreEditor: View {
    @Query private var settingsList: [AppSettings]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fico: Int = 0
    @State private var vantage: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("FICO Score") {
                    LabeledContent("Score") {
                        TextField("e.g. 720", value: $fico, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if fico > 0 {
                        Text(OverviewLogic.creditBand(fico)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    LabeledContent("Score") {
                        TextField("e.g. 735", value: $vantage, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if vantage > 0 {
                        Text(OverviewLogic.creditBand(vantage)).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("VantageScore")
                } footer: {
                    Text("Track both your FICO and VantageScore (each 300–850). Lenders usually use FICO; many free apps show VantageScore. Leave one at 0 if you don't have it. A history graph and event correlations are coming next.")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Credit Scores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear {
                if let s = settingsList.first {
                    fico = s.ficoScore
                    vantage = s.vantageScore
                }
            }
        }
    }

    private func save() {
        if let s = settingsList.first {
            s.ficoScore = fico > 0 ? min(max(fico, 300), 850) : 0
            s.vantageScore = vantage > 0 ? min(max(vantage, 300), 850) : 0
            try? context.save()
        }
        dismiss()
    }
}

// MARK: - Informal debts in Net Worth (selective inclusion)

private struct InformalDebtsSheet: View {
    @Query(sort: \PersonalDebt.amount, order: .reverse) private var debts: [PersonalDebt]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private var nonForgiven: [PersonalDebt] { debts.filter { $0.status != .forgiven } }
    private var countedTotal: Double { nonForgiven.filter { $0.countInNetWorth }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            Form {
                if nonForgiven.isEmpty {
                    Text("No informal debts to count.").foregroundStyle(.secondary)
                } else {
                    Section {
                        ForEach(nonForgiven) { debt in
                            Toggle(isOn: binding(debt)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(debt.lender)
                                    Text(debt.amount, format: .currency(code: "USD"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Count toward Net Worth")
                    } footer: {
                        Text("Tick the informal debts you mentally count. Unticked ones stay noted but are left out of Net Worth and Debt Balance. Counted now: \(countedTotal.formatted(.currency(code: "USD"))).")
                    }
                    Section {
                        Button("Count all") { setAll(true) }
                        Button("Count none") { setAll(false) }
                    }
                }
            }
            .navigationTitle("Informal Debts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { try? context.save(); dismiss() } }
            }
        }
    }

    private func binding(_ d: PersonalDebt) -> Binding<Bool> {
        Binding(get: { d.countInNetWorth }, set: { d.countInNetWorth = $0; try? context.save() })
    }

    private func setAll(_ v: Bool) {
        for d in nonForgiven { d.countInNetWorth = v }
        try? context.save()
    }
}

#Preview {
    NavigationStack { OverviewView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, PersonalDebt.self], inMemory: true)
}
