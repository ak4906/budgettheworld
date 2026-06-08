//
//  RecurringView.swift
//  BudgetTheWorld
//
//  Manage planned, repeating income/expenses (food, commute, subscriptions, side income).
//  These drive the forward projection / "Left to Spend" horizon. Reached from the Spending tab.
//

import SwiftUI
import SwiftData

struct RecurringView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringTransaction.detail) private var items: [RecurringTransaction]
    @State private var editing: RecurringTransaction?
    @State private var creatingNew = false

    var body: some View {
        List {
            if items.isEmpty {
                ContentUnavailableView("No recurring items", systemImage: "repeat",
                                       description: Text("Add things you regularly pay or earn — food, commute, subscriptions, side income."))
            } else {
                ForEach(items) { item in
                    Button { editing = item } label: { row(item) }
                        .buttonStyle(.plain)
                }
                .onDelete(perform: delete)
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingNew = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { EditRecurringSheet(item: $0) }
        .sheet(isPresented: $creatingNew) { EditRecurringSheet(item: nil) }
    }

    private func row(_ item: RecurringTransaction) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.category.iconName)
                .foregroundStyle(item.category.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.detail).fontWeight(.medium)
                Text("\(item.cadence.displayName) · \(item.category.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.amount, format: .currency(code: "USD"))
                .fontWeight(.semibold)
                .foregroundStyle(item.amount < 0 ? Color.primary : Color.green)
        }
        .opacity(item.isActive ? 1 : 0.4)
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(items[i]) }
        try? context.save()
    }
}

private struct EditRecurringSheet: View {
    let item: RecurringTransaction?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var detail: String
    @State private var amount: Double
    @State private var category: SpendCategory
    @State private var cadence: RecurringCadence
    @State private var startDate: Date
    @State private var isIncome: Bool
    @State private var isActive: Bool
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var payWith: String? = nil
    @State private var hasEnd: Bool
    @State private var endDate: Date
    @State private var skippedKeys: Set<String>

    init(item: RecurringTransaction?) {
        self.item = item
        _detail = State(initialValue: item?.detail ?? "")
        _amount = State(initialValue: item.map { abs($0.amount) } ?? 0)
        _category = State(initialValue: item?.category ?? .other)
        _cadence = State(initialValue: item?.cadence ?? .monthly)
        _startDate = State(initialValue: item?.startDate ?? .now)
        _isIncome = State(initialValue: (item?.amount ?? -1) > 0)
        _isActive = State(initialValue: item?.isActive ?? true)
        _payWith = State(initialValue: item?.cardName)
        let end = item?.endDate ?? .distantFuture
        let bounded = end.timeIntervalSinceNow < 100 * 365 * 86_400
        _hasEnd = State(initialValue: bounded)
        _endDate = State(initialValue: bounded ? end : .now)
        _skippedKeys = State(initialValue: Set((item?.skippedDatesRaw ?? "").split(separator: ",").map(String.init)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it? (e.g. Lunch, Subway)", text: $detail)
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle("This is income", isOn: $isIncome)
                    Picker("How often", selection: $cadence) {
                        ForEach(RecurringCadence.allCases) { Text($0.displayName).tag($0) }
                    }
                    DatePicker("Starting", selection: $startDate, displayedComponents: .date)
                    Toggle("Ends on a date", isOn: $hasEnd)
                    if hasEnd {
                        DatePicker("Ends", selection: $endDate, displayedComponents: .date)
                    }
                    if !isIncome {
                        if !cards.isEmpty {
                            Picker("Paid with", selection: $payWith) {
                                Text("Checking").tag(String?.none)
                                ForEach(cards) { card in
                                    Text(card.name).tag(String?.some(card.name))
                                }
                            }
                        }
                        Picker("Category", selection: $category) {
                            ForEach(SpendCategory.allCases) { cat in
                                Label(cat.displayName, systemImage: cat.iconName).tag(cat)
                            }
                        }
                    }
                }
                Section {
                    let dates = ProjectionEngine.upcomingOccurrenceDates(start: startDate, cadence: cadence, end: hasEnd ? endDate : .distantFuture, limit: 8)
                    if dates.isEmpty {
                        Text("No upcoming occurrences.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(dates, id: \.self) { d in
                            let key = ProjectionEngine.skipKey(d)
                            let skipped = skippedKeys.contains(key)
                            Button {
                                if skipped { skippedKeys.remove(key) } else { skippedKeys.insert(key) }
                            } label: {
                                HStack {
                                    Text(d.formatted(.dateTime.weekday(.abbreviated).month().day().year()))
                                        .strikethrough(skipped)
                                        .foregroundStyle(skipped ? Color.secondary : Color.primary)
                                    Spacer()
                                    if skipped {
                                        Text("Skipped").font(.caption).foregroundStyle(.orange)
                                    } else {
                                        Image(systemName: "checkmark.circle").foregroundStyle(.green)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Upcoming occurrences")
                } footer: {
                    Text("Tap an occurrence to skip just that one (a week off, a paused month). Skipped dates are left out of forecasts and Free to Spend.")
                }
                if item != nil {
                    Section {
                        Toggle("Active", isOn: $isActive)
                        Button("Delete", role: .destructive) { delete() }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(item == nil ? "New Recurring" : "Edit Recurring")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0 || detail.isEmpty)
                }
            }
        }
    }

    private func save() {
        let signed = isIncome ? amount : -amount
        let cat = isIncome ? SpendCategory.income : category
        let skips = skippedKeys.sorted().joined(separator: ",")
        if let item {
            item.detail = detail
            item.amount = signed
            item.category = cat
            item.cadence = cadence
            item.startDate = startDate
            item.isActive = isActive
            item.cardName = isIncome ? nil : payWith
            item.endDate = hasEnd ? endDate : .distantFuture
            item.skippedDatesRaw = skips
        } else {
            let new = RecurringTransaction(amount: signed, detail: detail, category: cat, cadence: cadence, startDate: startDate, endDate: hasEnd ? endDate : .distantFuture, cardName: isIncome ? nil : payWith)
            new.skippedDatesRaw = skips
            context.insert(new)
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let item {
            context.delete(item)
            try? context.save()
        }
        dismiss()
    }
}

#Preview {
    NavigationStack { RecurringView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
