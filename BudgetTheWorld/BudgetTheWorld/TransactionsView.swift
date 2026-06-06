//
//  TransactionsView.swift
//  BudgetTheWorld
//
//  Manual purchase log — the crutch before Plaid. Every expense shows how many work-hours it
//  cost. Tap any transaction to edit it; categories auto-guess from the description, and you can
//  add an optional subcategory, store/location, and a purpose tag. Quick-add repeats recent buys.
//

import SwiftUI
import SwiftData

/// A prefilled template for quick-add (repeat a recent purchase).
struct TxnTemplate: Identifiable {
    let id = UUID()
    var desc: String
    var amount: Double
    var category: SpendCategory
    var subcategory: String?
    var merchant: String?
    var purpose: TxnPurpose?
    var isIncome: Bool
    var payWith: String?

    init(from e: LedgerEntry) {
        desc = e.rawDescription
        amount = abs(e.amount)
        category = e.category
        subcategory = e.subcategory
        merchant = e.merchant
        purpose = e.purpose
        isIncome = e.amount > 0
        payWith = e.cardName
    }
}

struct TransactionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerEntry.date, order: .reverse) private var entries: [LedgerEntry]
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]

    private enum ActiveSheet: Identifiable {
        case add
        case edit(LedgerEntry)
        case quick(TxnTemplate)
        var id: String {
            switch self {
            case .add: "add"
            case .edit(let e): "edit-\(ObjectIdentifier(e))"
            case .quick(let t): "quick-\(t.id)"
            }
        }
    }
    @State private var activeSheet: ActiveSheet?

    private var effectiveHourly: Double {
        guard let s = settingsList.first else { return 0 }
        let ratio = BudgetMath.averageNetRatio(paychecks, fallback: s.defaultNetRatio)
        return BudgetMath.effectiveHourly(hourlyWage: s.hourlyWage, netRatio: ratio)
    }

    private var currentBalance: Double {
        BalanceLogic.balance(asOf: .now,
                             anchorAmount: settingsList.first?.currentCashBalance ?? 0,
                             anchorDate: settingsList.first?.balanceAnchorDate ?? .now,
                             entries: entries)
    }

    /// Most recent distinct expenses (by description) for the quick-add row.
    private var quickAdds: [LedgerEntry] {
        var seen = Set<String>()
        var result: [LedgerEntry] = []
        for e in entries where e.amount < 0 && !e.isCardPayment && e.source != .recurring {
            let key = e.rawDescription.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(e)
            if result.count >= 8 { break }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Checking balance", value: currentBalance.formatted(.currency(code: "USD")))
                        .font(.headline)
                }

                if !quickAdds.isEmpty {
                    Section("Quick add") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(quickAdds) { e in
                                    Button { activeSheet = .quick(TxnTemplate(from: e)) } label: {
                                        HStack(spacing: 5) {
                                            Image(systemName: e.category.iconName).font(.caption2)
                                            Text(e.rawDescription).lineLimit(1)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(e.category.color.opacity(0.15), in: Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    }
                }

                if entries.isEmpty {
                    ContentUnavailableView("No transactions yet", systemImage: "creditcard",
                                           description: Text("Tap + to add a purchase."))
                } else {
                    Section("Spending") {
                        ForEach(entries) { entry in
                            Button { activeSheet = .edit(entry) } label: { row(entry) }
                                .buttonStyle(.plain)
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Transactions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { RecurringView() } label: { Image(systemName: "repeat") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { InsightsView() } label: { Image(systemName: "chart.pie.fill") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { activeSheet = .add } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .add: TransactionSheet(entry: nil, template: nil)
                case .edit(let e): TransactionSheet(entry: e, template: nil)
                case .quick(let t): TransactionSheet(entry: nil, template: t)
                }
            }
        }
    }

    private func row(_ entry: LedgerEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.iconName)
                .foregroundStyle(entry.category.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.rawDescription).fontWeight(.medium)
                    if entry.source == .recurring {
                        Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let p = entry.purpose {
                        Image(systemName: p.icon).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(subtitle(entry))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.amount, format: .currency(code: "USD"))
                    .fontWeight(.semibold)
                    .foregroundStyle(entry.amount < 0 ? Color.primary : Color.green)
                if entry.amount < 0 {
                    Text(BudgetMath.workTimeDescription(forDollars: -entry.amount, effectiveHourly: effectiveHourly, unit: settingsList.first?.workTimeUnit ?? .hours, hoursPerWorkday: settingsList.first?.scheduledPaidHoursPerDay ?? 8, workdaysPerWeek: settingsList.first?.workdayWeekdays.count ?? 5))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ e: LedgerEntry) -> String {
        var parts: [String] = [e.category.displayName]
        if let sub = e.subcategory, !sub.isEmpty { parts.append(sub) }
        if let m = e.merchant, !m.isEmpty { parts.append(m) }
        parts.append(e.date.formatted(.dateTime.month().day()))
        if let card = e.cardName { parts.append(card) }
        return parts.joined(separator: " · ")
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(entries[i]) }
        try? context.save()
    }
}

// MARK: - Add / Edit sheet

private struct TransactionSheet: View {
    let entry: LedgerEntry?       // non-nil = editing an existing transaction
    let template: TxnTemplate?    // non-nil = prefill from quick-add

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var allEntries: [LedgerEntry]

    @State private var desc: String
    @State private var amount: Double
    @State private var category: SpendCategory
    @State private var subcategory: String
    @State private var merchant: String
    @State private var purpose: TxnPurpose?
    @State private var date: Date
    @State private var isIncome: Bool
    @State private var payWith: String?
    @State private var note: String
    @State private var categoryTouched: Bool

    init(entry: LedgerEntry?, template: TxnTemplate?) {
        self.entry = entry
        self.template = template
        if let e = entry {
            _desc = State(initialValue: e.rawDescription)
            _amount = State(initialValue: abs(e.amount))
            _category = State(initialValue: e.category)
            _subcategory = State(initialValue: e.subcategory ?? "")
            _merchant = State(initialValue: e.merchant ?? "")
            _purpose = State(initialValue: e.purpose)
            _date = State(initialValue: e.date)
            _isIncome = State(initialValue: e.amount > 0)
            _payWith = State(initialValue: e.cardName)
            _note = State(initialValue: e.note ?? "")
            _categoryTouched = State(initialValue: true)
        } else if let t = template {
            _desc = State(initialValue: t.desc)
            _amount = State(initialValue: t.amount)
            _category = State(initialValue: t.category)
            _subcategory = State(initialValue: t.subcategory ?? "")
            _merchant = State(initialValue: t.merchant ?? "")
            _purpose = State(initialValue: t.purpose)
            _date = State(initialValue: .now)
            _isIncome = State(initialValue: t.isIncome)
            _payWith = State(initialValue: t.payWith)
            _note = State(initialValue: "")
            _categoryTouched = State(initialValue: true)
        } else {
            _desc = State(initialValue: "")
            _amount = State(initialValue: 0)
            _category = State(initialValue: .other)
            _subcategory = State(initialValue: "")
            _merchant = State(initialValue: "")
            _purpose = State(initialValue: nil)
            _date = State(initialValue: .now)
            _isIncome = State(initialValue: false)
            _payWith = State(initialValue: nil)
            _note = State(initialValue: "")
            _categoryTouched = State(initialValue: false)
        }
    }

    private var merchantSuggestions: [String] {
        let history = allEntries.compactMap { $0.merchant }.filter { !$0.isEmpty }
        var seen = Set<String>()
        var out: [String] = []
        for m in history + TxnDetailCatalog.defaultMerchants {
            let key = m.lowercased()
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(m)
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it? (e.g. Boba)", text: $desc)
                        .onChange(of: desc) { _, new in
                            if !categoryTouched { category = Categorizer.category(for: new) }
                        }
                    LabeledContent("Amount") {
                        TextField("0.00", value: $amount, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("This is income", isOn: $isIncome)
                }
                if !isIncome {
                    Section {
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
                        .onChange(of: category) { _, _ in
                            categoryTouched = true
                            subcategory = ""
                        }
                    }
                    Section("Detail (optional)") {
                        suggestField(title: "Subcategory", text: $subcategory,
                                     suggestions: TxnDetailCatalog.subcategories(for: category),
                                     placeholder: "e.g. Boba")
                        suggestField(title: "Where", text: $merchant,
                                     suggestions: merchantSuggestions,
                                     placeholder: "e.g. Trader Joe's")
                        Picker("Purpose", selection: $purpose) {
                            Text("—").tag(TxnPurpose?.none)
                            ForEach(TxnPurpose.allCases) { p in
                                Label(p.label, systemImage: p.icon).tag(TxnPurpose?.some(p))
                            }
                        }
                        TextField("Note", text: $note, axis: .vertical)
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(entry == nil ? "Add Transaction" : "Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0 || desc.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func suggestField(title: String, text: Binding<String>, suggestions: [String], placeholder: String) -> some View {
        HStack {
            TextField(placeholder, text: text)
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { text.wrappedValue = s }
                    }
                } label: {
                    Image(systemName: "text.badge.plus")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func save() {
        let signed = isIncome ? abs(amount) : -abs(amount)
        let cat = isIncome ? SpendCategory.income : category
        let cardName = isIncome ? nil : payWith
        let sub = (isIncome || subcategory.isEmpty) ? nil : subcategory
        let merch = (isIncome || merchant.isEmpty) ? nil : merchant
        let purp = isIncome ? nil : purpose
        let noteVal = note.isEmpty ? nil : note
        if let e = entry {
            e.date = date
            e.amount = signed
            e.rawDescription = desc
            e.category = cat
            e.cardName = cardName
            e.subcategory = sub
            e.merchant = merch
            e.purpose = purp
            e.note = noteVal
        } else {
            context.insert(LedgerEntry(date: date, amount: signed, rawDescription: desc, category: cat,
                                       source: .manual, note: noteVal, cardName: cardName,
                                       subcategory: sub, merchant: merch, purpose: purp))
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    TransactionsView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
