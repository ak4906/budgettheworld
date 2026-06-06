//
//  InsightsView.swift
//  BudgetTheWorld
//
//  The "wisdom" screen: where your money is going by category, and how your observed
//  spending fits the 50/30/20 guideline. Reached from the Spending tab.
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query(sort: \WorkDay.date, order: .reverse) private var workDays: [WorkDay]

    @State private var period: InsightPeriod = .thisMonth

    var body: some View {
        ScrollView {
            if let settings = settingsList.first {
                let bounds = period.bounds(settings: settings)
                let cats = InsightsLogic.spendingByCategory(ledger, start: bounds.start, end: bounds.end)
                let totalSpent = cats.reduce(0) { $0 + $1.amount }
                let income = InsightsLogic.income(settings: settings, paychecks: paychecks, workDays: workDays, entries: ledger, start: bounds.start, end: bounds.end)
                let nws = InsightsLogic.needsWantsSavings(cats, income: income)
                VStack(spacing: 16) {
                    Picker("Period", selection: $period) {
                        ForEach(InsightPeriod.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    planCard(income: income, nws: nws)
                    categoryCard(cats: cats, total: totalSpent)
                }
                .padding()
            } else {
                ContentUnavailableView("No data yet", systemImage: "chart.pie")
                    .padding(.top, 80)
            }
        }
        .background(Color.btwBackground)
        .navigationTitle("Insights")
    }

    private func planCard(income: Double, nws: (needs: Double, wants: Double, savings: Double)) -> some View {
        Card(title: "50 / 30 / 20 Plan", systemImage: "chart.bar.fill", tint: .indigo) {
            if income <= 0 {
                Text("Add income for this period (a paycheck lands, or log income) to see how your spending fits the 50/30/20 guideline.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                planRow("Needs", spent: nws.needs, income: income, target: 0.50, tint: .blue)
                planRow("Wants", spent: nws.wants, income: income, target: 0.30, tint: .pink)
                planRow("Savings", spent: nws.savings, income: income, target: 0.20, tint: .green)
                Text("Against \(income, format: .currency(code: "USD")) take-home this period. Guideline: 50% needs · 30% wants · 20% savings.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
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

    private func categoryCard(cats: [CategorySpend], total: Double) -> some View {
        Card(title: "Where it's going", systemImage: "list.bullet.rectangle.fill", tint: .teal) {
            if cats.isEmpty {
                Text("No spending logged this period.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Total spent: \(total, format: .currency(code: "USD"))")
                    .font(.subheadline).fontWeight(.semibold)
                VStack(spacing: 10) {
                    ForEach(cats) { c in
                        let pct = total > 0 ? c.amount / total : 0
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(c.category.displayName, systemImage: c.category.iconName)
                                    .font(.caption).fontWeight(.medium)
                                    .foregroundStyle(c.category.color)
                                Spacer()
                                Text("\(c.amount, format: .currency(code: "USD")) · \(Int((pct * 100).rounded()))%")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            ProgressView(value: pct).tint(c.category.color)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

#Preview {
    NavigationStack { InsightsView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
