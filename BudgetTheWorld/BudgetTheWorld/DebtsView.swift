//
//  DebtsView.swift
//  BudgetTheWorld
//
//  Informal/personal debts (e.g. money owed to family) — often no deadline. Noted here,
//  not counted in spendable numbers. Can become active (with a due date) or be forgiven.
//  Reached from Settings → Debts. Will feed the what-if graph's payoff planning later.
//

import SwiftUI
import SwiftData

struct DebtsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PersonalDebt.amount, order: .reverse) private var debts: [PersonalDebt]
    @State private var editing: PersonalDebt?
    @State private var creatingNew = false

    private var totalOwed: Double { debts.filter { $0.status != .forgiven }.reduce(0) { $0 + $1.amount } }

    var body: some View {
        List {
            if debts.isEmpty {
                ContentUnavailableView("No informal debts", systemImage: "person.2",
                                       description: Text("Note money you informally owe (e.g. family). These aren't counted in your spendable numbers."))
            } else {
                Section {
                    LabeledContent("Total owed (not forgiven)", value: totalOwed.formatted(.currency(code: "USD")))
                }
                Section {
                    ForEach(debts) { debt in
                        Button { editing = debt } label: { row(debt) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Informal Debts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { EditDebtSheet(debt: $0) }
        .sheet(isPresented: $creatingNew) { EditDebtSheet(debt: nil) }
    }

    private func row(_ debt: PersonalDebt) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(debt.lender).fontWeight(.medium)
                Text(debt.status.label + (debt.dueDate.map { " · due \($0.formatted(.dateTime.month().day().year()))" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(debt.status == .active ? .orange : .secondary)
            }
            Spacer()
            Text(debt.amount, format: .currency(code: "USD"))
                .fontWeight(.semibold)
                .strikethrough(debt.status == .forgiven)
                .foregroundStyle(debt.status == .forgiven ? .secondary : .primary)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(debts[i]) }
        try? context.save()
    }
}

private struct EditDebtSheet: View {
    let debt: PersonalDebt?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var lender: String
    @State private var amount: Double
    @State private var status: DebtStatus
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var note: String

    init(debt: PersonalDebt?) {
        self.debt = debt
        _lender = State(initialValue: debt?.lender ?? "")
        _amount = State(initialValue: debt?.amount ?? 0)
        _status = State(initialValue: debt?.status ?? .dormant)
        _hasDueDate = State(initialValue: debt?.dueDate != nil)
        _dueDate = State(initialValue: debt?.dueDate ?? .now)
        _note = State(initialValue: debt?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Who (e.g. Dad, Aunt)", text: $lender)
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Status", selection: $status) {
                        ForEach(DebtStatus.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Toggle("Has a due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                } footer: {
                    Text("Dormant debts have no deadline and aren't counted in your numbers. Add a due date when one becomes real, or set it Forgiven to retire it.")
                }
                Section {
                    TextField("Note", text: $note, axis: .vertical)
                }
                if debt != nil {
                    Section {
                        Button("Delete", role: .destructive) { delete() }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(debt == nil ? "New Debt" : "Edit Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(lender.isEmpty || amount <= 0)
                }
            }
        }
    }

    private func save() {
        let due = hasDueDate ? dueDate : nil
        if let debt {
            debt.lender = lender
            debt.amount = amount
            debt.status = status
            debt.dueDate = due
            debt.note = note.isEmpty ? nil : note
        } else {
            context.insert(PersonalDebt(lender: lender, amount: amount, status: status, dueDate: due, note: note.isEmpty ? nil : note))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let debt {
            context.delete(debt)
            try? context.save()
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { DebtsView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, PersonalDebt.self], inMemory: true)
}
