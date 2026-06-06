//
//  CreditCardsView.swift
//  BudgetTheWorld
//
//  Manage credit cards: balances, statement/minimum due, and the monthly due day.
//  Reached from Settings → Credit Cards.
//

import SwiftUI
import SwiftData

struct CreditCardsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @Query private var ledger: [LedgerEntry]

    @State private var editing: CreditCard?
    @State private var creatingNew = false
    @State private var payingCard: CreditCard?

    var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView("No cards", systemImage: "creditcard",
                                       description: Text("Tap + to add a credit card."))
            } else {
                ForEach(cards) { card in
                    Button { editing = card } label: { cardRow(card) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading) {
                            Button { payingCard = card } label: { Label("Pay", systemImage: "dollarsign.circle") }
                                .tint(.green)
                        }
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Credit Cards")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { EditCreditCardSheet(card: $0) }
        .sheet(isPresented: $creatingNew) { EditCreditCardSheet(card: nil) }
        .sheet(item: $payingCard) { PaymentSheet(card: $0) }
    }

    private func cardRow(_ card: CreditCard) -> some View {
        let due = card.nextDueDate
        let days = BudgetMath.daysUntil(due)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(card.name).fontWeight(.medium)
                Spacer()
                Text(CardLogic.balance(for: card, entries: ledger), format: .currency(code: "USD")).fontWeight(.semibold)
            }
            Text("Statement \(card.statementBalance, format: .currency(code: "USD")) · min \(card.minimumPayment, format: .currency(code: "USD"))")
                .font(.caption).foregroundStyle(.secondary)
            Text("Due \(due.formatted(.dateTime.month().day())) · in \(days) days")
                .font(.caption).foregroundStyle(days <= 3 ? Color.red : Color.secondary)
        }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(cards[i]) }
        try? context.save()
    }
}

private struct EditCreditCardSheet: View {
    let card: CreditCard?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var balance: Double
    @State private var statement: Double
    @State private var minimum: Double
    @State private var dueDate: Date

    init(card: CreditCard?) {
        self.card = card
        _name = State(initialValue: card?.name ?? "Credit Card")
        _balance = State(initialValue: card?.currentBalance ?? 0)
        _statement = State(initialValue: card?.statementBalance ?? 0)
        _minimum = State(initialValue: card?.minimumPayment ?? 0)
        _dueDate = State(initialValue: card?.statementDueDate ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Card") {
                    TextField("Name", text: $name)
                }
                Section("Balances") {
                    currencyField("Current balance", $balance)
                    currencyField("Statement balance", $statement)
                    currencyField("Minimum payment", $minimum)
                }
                Section {
                    DatePicker("Current balance due", selection: $dueDate, displayedComponents: .date)
                } header: {
                    Text("Statement due date")
                } footer: {
                    Text("When the CURRENT balance is actually due. Already paid this month's statement? Set this to next month's date — that $ is for the next cycle.")
                }
                if card != nil {
                    Section {
                        Button("Delete card", role: .destructive) { delete() }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(card == nil ? "New Card" : "Edit Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.isEmpty) }
            }
        }
    }

    private func currencyField(_ label: String, _ value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        if let card {
            card.name = name
            card.currentBalance = balance
            card.statementBalance = statement
            card.minimumPayment = minimum
            card.statementDueDate = dueDate
        } else {
            context.insert(CreditCard(name: name, currentBalance: balance, statementBalance: statement,
                                      minimumPayment: minimum, statementDueDate: dueDate))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let card {
            context.delete(card)
            try? context.save()
        }
        dismiss()
    }
}

private struct PaymentSheet: View {
    let card: CreditCard

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double
    @State private var date = Date()

    init(card: CreditCard) {
        self.card = card
        _amount = State(initialValue: card.statementBalance > 0 ? card.statementBalance : 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Paid on", selection: $date, displayedComponents: .date)
                } header: {
                    Text("Pay \(card.name)")
                } footer: {
                    Text("Records a payment from checking toward \(card.name). It lowers your checking balance and the card balance on that date.")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Make a Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0)
                }
            }
        }
    }

    private func save() {
        context.insert(LedgerEntry(date: date, amount: -amount, rawDescription: "Payment — \(card.name)", category: .other, source: .manual, cardName: card.name, isCardPayment: true))
        try? context.save()
        dismiss()
    }
}

#Preview {
    NavigationStack { CreditCardsView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
