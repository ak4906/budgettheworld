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

private enum TxnFilter: String, CaseIterable, Identifiable {
    case all, needsLabel
    var id: String { rawValue }
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
    @AppStorage("bankSyncIsSourceOfTruth") private var bankSyncOn = false
    @State private var filter: TxnFilter = .all
    @State private var searchText = ""

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

    /// A transaction still needing labels: an expense that's uncategorized (Other) or has no subcategory.
    private func needsLabel(_ e: LedgerEntry) -> Bool {
        e.amount < 0 && !e.isCardPayment && (e.category == .other || (e.subcategory?.isEmpty ?? true))
    }
    private var shownEntries: [LedgerEntry] {
        var base = filter == .all ? entries : entries.filter(needsLabel)
        let q = searchText.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            base = base.filter { e in
                let hay = "\(e.rawDescription) \(e.category.displayName) \(e.subcategory ?? "") \(e.merchant ?? "") \(e.accountName ?? "")".lowercased()
                return hay.contains(q) || String(format: "%.2f", abs(e.amount)).contains(q)
            }
        }
        return base
    }
    private var needsLabelCount: Int { entries.filter(needsLabel).count }

    /// Most recent distinct expenses (by description) for the quick-add row.
    private var quickAdds: [LedgerEntry] {
        let expenses = entries.filter { $0.amount < 0 && !$0.isCardPayment && $0.source != .recurring }
        var freq: [String: Int] = [:]
        var mostRecent: [String: LedgerEntry] = [:]
        for e in expenses {
            let key = e.rawDescription.lowercased()
            freq[key, default: 0] += 1
            if mostRecent[key] == nil { mostRecent[key] = e }   // entries are date-desc → first seen = newest
        }
        return mostRecent.values
            .sorted { (freq[$0.rawDescription.lowercased()] ?? 0, $0.date) > (freq[$1.rawDescription.lowercased()] ?? 0, $1.date) }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Checking balance", value: currentBalance.formatted(.currency(code: "USD")))
                        .font(.headline)
                }

                if !quickAdds.isEmpty && !bankSyncOn {
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
                    Section {
                        Picker("Filter", selection: $filter) {
                            Text("All").tag(TxnFilter.all)
                            Text(needsLabelCount > 0 ? "Needs label (\(needsLabelCount))" : "Needs label").tag(TxnFilter.needsLabel)
                        }
                        .pickerStyle(.segmented)
                    }
                    Section(filter == .needsLabel ? "Needs label" : "Spending") {
                        if shownEntries.isEmpty {
                            Text("All caught up — everything's labeled. 🎉").foregroundStyle(.secondary)
                        }
                        ForEach(shownEntries) { entry in
                            Button { activeSheet = .edit(entry) } label: { row(entry) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Menu("Set category") {
                                        ForEach(SpendCategory.allCases) { cat in
                                            Button { entry.category = cat; try? context.save() } label: {
                                                Label(cat.displayName, systemImage: cat.iconName)
                                            }
                                        }
                                    }
                                    Button(entry.essential == true ? "Mark as Want" : "Mark essential (Need)") {
                                        entry.essential = (entry.essential == true) ? false : true
                                        try? context.save()
                                    }
                                    Button("Edit…") { activeSheet = .edit(entry) }
                                }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search name, category, place, amount…")
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
        if let meal = e.mealType { parts.append(meal.label) }
        if let m = e.merchant, !m.isEmpty { parts.append(m) }
        if let a = e.area, !a.isEmpty { parts.append(a) }
        parts.append(e.date.formatted(.dateTime.month().day()))
        if let card = e.cardName {
            parts.append(card)
        } else if let acct = e.accountName, !acct.isEmpty {
            parts.append(acct)
        }
        return parts.joined(separator: " · ")
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(shownEntries[i]) }
        try? context.save()
    }
}

// MARK: - Add / Edit sheet

private enum ApplyScope: Hashable { case thisOnly, allMatching, allAndFuture, allAndFutureThisPrice }

struct TransactionSheet: View {
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
    @State private var area: String = ""
    @State private var purpose: TxnPurpose?
    @State private var date: Date
    @State private var isIncome: Bool
    @State private var payWith: String?
    @State private var note: String
    @State private var categoryTouched: Bool
    @State private var applyScope: ApplyScope = .thisOnly
    @State private var essential: Bool? = nil
    @State private var mealType: MealType? = nil
    @State private var lineItems: [LineItemDTO] = []

    init(entry: LedgerEntry?, template: TxnTemplate?) {
        self.entry = entry
        self.template = template
        if let e = entry {
            _desc = State(initialValue: e.rawDescription)
            _amount = State(initialValue: abs(e.amount))
            _category = State(initialValue: e.category)
            _subcategory = State(initialValue: e.subcategory ?? "")
            _merchant = State(initialValue: e.merchant ?? "")
            _area = State(initialValue: e.area ?? "")
            _purpose = State(initialValue: e.purpose)
            _date = State(initialValue: e.date)
            _isIncome = State(initialValue: e.amount > 0)
            _payWith = State(initialValue: e.cardName)
            _note = State(initialValue: e.note ?? "")
            _essential = State(initialValue: e.essential)
            _mealType = State(initialValue: e.mealType)
            _lineItems = State(initialValue: e.lineItems)
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

    private var subcategorySuggestions: [String] {
        merged(TxnDetailCatalog.subcategories(for: category),
               history: allEntries.filter { $0.category == category }.compactMap { $0.subcategory })
    }
    private var areaSuggestions: [String] {
        merged([], history: allEntries.compactMap { $0.area })
    }
    private var incomeSourceSuggestions: [String] {
        merged(TxnDetailCatalog.incomeSources,
               history: allEntries.filter { $0.category == .income }.compactMap { $0.subcategory })
    }
    /// Catalog defaults + the user's own typed values, de-duplicated (case-insensitive).
    private func merged(_ base: [String], history: [String]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in base + history where !s.isEmpty {
            let k = s.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k); out.append(s)
        }
        return out
    }

    /// Top ~6 one-tap subcategory chips: keyword hint from the name first, then your most-used
    /// for this category, then catalog defaults.
    private var subcategoryChips: [String] {
        var ranked: [String] = []
        if let hint = TxnDetailCatalog.subcategoryHint(for: category, name: desc) { ranked.append(hint) }
        let freq = Dictionary(grouping: allEntries.filter { $0.category == category }.compactMap { $0.subcategory }.filter { !$0.isEmpty }, by: { $0 })
            .mapValues { $0.count }
        ranked += freq.sorted { $0.value > $1.value }.map { $0.key }
        ranked += TxnDetailCatalog.subcategories(for: category)
        var seen = Set<String>(); var out: [String] = []
        for s in ranked where !s.isEmpty {
            let k = s.lowercased()
            if seen.contains(k) { continue }
            seen.insert(k); out.append(s)
            if out.count >= 6 { break }
        }
        return out
    }

    /// The most recent already-labeled transaction with the same name, to copy its labels.
    private var lastLabeled: LedgerEntry? {
        let key = desc.lowercased()
        guard !key.isEmpty else { return nil }
        return allEntries.first {
            $0.rawDescription.lowercased() == key &&
            $0.persistentModelID != entry?.persistentModelID &&
            ($0.category != .other || ($0.subcategory?.isEmpty == false))
        }
    }

    private func applyLast(_ e: LedgerEntry) {
        category = e.category
        subcategory = e.subcategory ?? ""
        merchant = e.merchant ?? ""
        area = e.area ?? ""
        purpose = e.purpose
        if e.category == .food { mealType = e.mealType }
        categoryTouched = true
    }

    @ViewBuilder
    private func chipRow(_ labels: [String], current: String, onTap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    let active = current.lowercased() == label.lowercased()
                    Button { onTap(label) } label: {
                        Text(label).font(.caption).fontWeight(.medium)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(active ? Color.accentColor : Color.btwCard, in: Capsule())
                            .foregroundStyle(active ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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
                    if let last = lastLabeled, subcategory.isEmpty {
                        Section {
                            Button { applyLast(last) } label: {
                                Label("Use last time: \(last.category.displayName)\(last.subcategory.map { " · \($0)" } ?? "")", systemImage: "wand.and.stars")
                            }
                        } footer: {
                            Text("You've labeled “\(desc)” before — tap to copy those labels.")
                        }
                    }
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
                        if !subcategoryChips.isEmpty {
                            chipRow(subcategoryChips, current: subcategory) { subcategory = $0 }
                        }
                        suggestField(title: "Subcategory", text: $subcategory,
                                     suggestions: subcategorySuggestions,
                                     placeholder: "e.g. Restaurant, Boba")
                        suggestField(title: "Where", text: $merchant,
                                     suggestions: merchantSuggestions,
                                     placeholder: "e.g. Jin Ramen")
                        suggestField(title: "Area", text: $area,
                                     suggestions: areaSuggestions,
                                     placeholder: "e.g. Hamilton Heights")
                        Picker("Purpose", selection: $purpose) {
                            Text("—").tag(TxnPurpose?.none)
                            ForEach(TxnPurpose.allCases) { p in
                                Label(p.label, systemImage: p.icon).tag(TxnPurpose?.some(p))
                            }
                        }
                        if category == .food {
                            Picker("Meal", selection: $mealType) {
                                Text("—").tag(MealType?.none)
                                ForEach(MealType.allCases) { m in
                                    Text(m.label).tag(MealType?.some(m))
                                }
                            }
                        }
                        Picker("Counts as", selection: $essential) {
                            Text("Default (by category)").tag(Bool?.none)
                            Text("Need (essential)").tag(Bool?.some(true))
                            Text("Want (not essential)").tag(Bool?.some(false))
                        }
                        TextField("Note", text: $note, axis: .vertical)
                    }
                    Section {
                        ForEach($lineItems) { $item in
                            HStack {
                                TextField("Item (e.g. Apples)", text: $item.name)
                                TextField("0.00", value: $item.amount, format: .currency(code: "USD"))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 90)
                            }
                        }
                        .onDelete { lineItems.remove(atOffsets: $0) }
                        Button { lineItems.append(LineItemDTO(name: "", amount: 0)) } label: {
                            Label("Add item", systemImage: "plus")
                        }
                        if !lineItems.isEmpty {
                            let sum = lineItems.reduce(0) { $0 + $1.amount }
                            HStack {
                                Text("Items total").foregroundStyle(.secondary)
                                Spacer()
                                Text(sum, format: .currency(code: "USD"))
                                    .foregroundStyle(abs(sum - amount) < 0.01 ? Color.green : Color.orange)
                            }
                            .font(.caption)
                        }
                    } header: {
                        Text("Line items (optional)")
                    } footer: {
                        Text("Break a receipt into items (apples, milk, tax…) to track per-item prices over time.")
                    }
                } else {
                    Section("Source (optional)") {
                        suggestField(title: "Source", text: $subcategory,
                                     suggestions: incomeSourceSuggestions,
                                     placeholder: "e.g. Paycheck, Gift, Benefit")
                        TextField("Note", text: $note, axis: .vertical)
                    }
                }

                if !desc.isEmpty {
                    let sameCount = allEntries.filter { $0.rawDescription.lowercased() == desc.lowercased() }.count
                    Section {
                        Picker("Apply labels to", selection: $applyScope) {
                            Text("This one only").tag(ApplyScope.thisOnly)
                            Text(sameCount > 1 ? "All “\(desc)” (\(sameCount))" : "All “\(desc)”").tag(ApplyScope.allMatching)
                            Text("All + future “\(desc)”").tag(ApplyScope.allAndFuture)
                            Text("All + future “\(desc)” at \(amount.formatted(.currency(code: "USD")))").tag(ApplyScope.allAndFutureThisPrice)
                        }
                        .pickerStyle(.inline)
                    } header: {
                        Text("Labeling")
                    } footer: {
                        Text(applyScope == .allAndFuture
                             ? "Also saves a rule so future synced “\(desc)” transactions get these labels automatically."
                             : "Apply these labels to just this one, or to every transaction with the same name.")
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
                    ForEach(suggestions.sorted(), id: \.self) { s in
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
        let sub = subcategory.isEmpty ? nil : subcategory          // income uses this as "Source"
        let merch = merchant.isEmpty ? nil : merchant
        let ar = area.isEmpty ? nil : area
        let purp = isIncome ? nil : purpose
        let ess = isIncome ? nil : essential
        let mealVal: MealType? = (!isIncome && category == .food) ? mealType : nil
        let noteVal = note.isEmpty ? nil : note
        let items = isIncome ? [] : lineItems.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        if let e = entry {
            e.date = date
            e.amount = signed
            e.rawDescription = desc
            e.category = cat
            e.cardName = cardName
            e.subcategory = sub
            e.merchant = merch
            e.area = ar
            e.purpose = purp
            e.essential = ess
            e.mealType = mealVal
            e.note = noteVal
            e.lineItems = items
        } else {
            let new = LedgerEntry(date: date, amount: signed, rawDescription: desc, category: cat,
                                  source: .manual, note: noteVal, cardName: cardName,
                                  subcategory: sub, merchant: merch, area: ar, purpose: purp, essential: ess,
                                  mealType: mealVal)
            new.lineItems = items
            context.insert(new)
        }
        // Apply to other transactions with the same name (and, for the price scope, the same amount).
        if applyScope != .thisOnly, !desc.isEmpty {
            let key = desc.lowercased()
            let priceScoped = (applyScope == .allAndFutureThisPrice)
            for other in allEntries where other.rawDescription.lowercased() == key
                && other.persistentModelID != entry?.persistentModelID
                && (!priceScoped || abs(abs(other.amount) - abs(amount)) < 0.01) {
                other.category = cat
                other.subcategory = sub
                other.merchant = merch
                other.area = ar
                other.purpose = purp
                other.essential = ess
            }
        }
        // Save a rule so FUTURE synced transactions with this name (optionally at this price) auto-label.
        if applyScope == .allAndFuture || applyScope == .allAndFutureThisPrice, !desc.isEmpty {
            let key = desc.lowercased()
            let ruleAmount: Double? = applyScope == .allAndFutureThisPrice ? abs(amount) : nil
            let rules = (try? context.fetch(FetchDescriptor<LabelRule>())) ?? []
            let existingRule = rules.first { r in
                guard r.match.lowercased() == key else { return false }
                switch (r.amount, ruleAmount) {
                case (nil, nil): return true
                case let (a?, b?): return abs(a - b) < 0.01
                default: return false
                }
            }
            if let rule = existingRule {
                rule.category = cat; rule.subcategory = sub; rule.merchant = merch; rule.purpose = purp; rule.amount = ruleAmount
            } else {
                context.insert(LabelRule(match: desc, category: cat, subcategory: sub, merchant: merch, purpose: purp, amount: ruleAmount))
            }
        }
        try? context.save()
        dismiss()
    }
}

#Preview {
    TransactionsView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, LabelRule.self], inMemory: true)
}
