//
//  EmergencyFundView.swift
//  BudgetTheWorld
//
//  The staged emergency-fund plan ($1,000 → 1 month → 3 months of essentials), with the
//  current stage, next milestone, and a suggested monthly contribution. Reached from Buckets.
//

import SwiftUI
import SwiftData

struct EmergencyFundView: View {
    @Query(sort: \Bucket.sortIndex) private var buckets: [Bucket]
    @Query private var rents: [RentObligation]
    @Query private var recurrings: [RecurringTransaction]
    @AppStorage("essentialCategories") private var essentialCodes: String = "rent,utilities,groceries,transportation"

    private var emergency: Bucket? { buckets.first { $0.kind == .emergency } }
    private var essentialSet: Set<String> { Set(essentialCodes.split(separator: ",").map(String.init)) }

    var body: some View {
        ScrollView {
            let monthly = EmergencyLogic.monthlyEssentials(rent: rents.first, recurrings: recurrings, essentialCategories: essentialSet)
            let stages = EmergencyLogic.stages(monthlyEssentials: monthly)
            let current = emergency?.currentAmount ?? 0
            let next = stages.first { current < $0.target }
            VStack(spacing: 16) {
                Card(title: "Emergency Fund", systemImage: "cross.case.fill", tint: .red) {
                    Text(current, format: .currency(code: "USD"))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    if let next {
                        let toGo = max(next.target - current, 0)
                        ProgressView(value: next.target > 0 ? min(current / next.target, 1) : 0).tint(.red)
                        Text("Next: \(next.name) — \(next.target, format: .currency(code: "USD"))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("\(toGo, format: .currency(code: "USD")) to go · about \(toGo / 6, format: .currency(code: "USD"))/mo to reach it in 6 months")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("Fully funded — 3+ months of essentials. 🎉")
                            .font(.subheadline).foregroundStyle(.green)
                    }
                }

                Card(title: "The plan", systemImage: "list.number", tint: .blue) {
                    ForEach(stages) { s in
                        let reached = current >= s.target
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: reached ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(reached ? .green : .secondary)
                                Text(s.name).font(.subheadline)
                                Spacer()
                                Text(s.target, format: .currency(code: "USD"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ProgressView(value: s.target > 0 ? min(current / s.target, 1) : 0)
                                .tint(reached ? .green : .red)
                        }
                        .padding(.vertical, 2)
                    }
                }

                Text("Based on ~\(monthly, format: .currency(code: "USD"))/month of essentials (rent + your essential recurring items). Build the $1,000 buffer first, then 1 month, then 3 months. Your med-school fund is tracked separately in Buckets.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding()
        }
        .background(Color.btwBackground)
        .navigationTitle("Emergency Fund")
    }
}

#Preview {
    NavigationStack { EmergencyFundView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, PersonalDebt.self], inMemory: true)
}
