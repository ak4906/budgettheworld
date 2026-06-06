//
//  DashboardView.swift
//  BudgetTheWorld
//
//  Home screen, driven by one adjustable horizon. "Safe to Spend" = everything coming IN by
//  the horizon (balance + paychecks + income) minus everything going OUT (rent, cards, recurring
//  expenses) — every line is shown in the breakdown. "Net Worth" is a separate wealth snapshot.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query private var settingsList: [AppSettings]
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query(sort: \Bucket.sortIndex) private var buckets: [Bucket]
    @Query private var rents: [RentObligation]
    @Query(sort: \WorkDay.date, order: .reverse) private var workDays: [WorkDay]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @Query private var recurrings: [RecurringTransaction]

    @AppStorage("preferredHorizon") private var horizonCode: String = "payday:1"
    @AppStorage("essentialCategories") private var essentialCodes: String = "rent,utilities,groceries,transportation"
    @State private var showDatePicker = false
    @State private var customDate: Date = .now
    @State private var rateBasis: RateBasis = .total
    @State private var showEssentials = false
    @State private var showMoveToFund = false
    @State private var freeForFund: Double = 0

    private var settings: AppSettings? { settingsList.first }
    private var rent: RentObligation? { rents.first }
    private var creditOwed: Double { cards.reduce(0) { $0 + CardLogic.balance(for: $1, entries: ledger) } }

    /// Persisted across launches via @AppStorage.
    private var horizon: SpendHorizon {
        get { SpendHorizon(code: horizonCode) }
        nonmutating set { horizonCode = newValue.code }
    }
    private var essentialSet: Set<String> { Set(essentialCodes.split(separator: ",").map(String.init)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let settings {
                    VStack(spacing: 16) {
                        horizonPicker
                        heroRing(settings)
                        leftToSpendCard(settings)
                        paycheckCard(settings)
                        rentCard(settings)
                        if !cards.isEmpty { creditCardsCard(settings) }
                        savingsCard(settings)
                    }
                    .padding()
                } else {
                    ContentUnavailableView("Setting things up…", systemImage: "hourglass")
                        .padding(.top, 80)
                }
            }
            .background(Color.btwBackground)
            .navigationTitle("BudgetTheWorld")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { OverviewView() } label: { Image(systemName: "square.grid.2x2.fill") }
                }
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink { ForecastView() } label: { Image(systemName: "chart.xyaxis.line") }
                }
            }
            .sheet(isPresented: $showDatePicker) { datePickerSheet }
            .sheet(isPresented: $showEssentials) { EssentialsSheet() }
            .sheet(isPresented: $showMoveToFund) { MoveToFundSheet(suggested: freeForFund) }
        }
    }

    // MARK: Horizon control

    private var horizonPicker: some View {
        Menu {
            Button("Today") { horizon = .today }
            Button("Next payday") { horizon = .payday(1) }
            Button("2nd payday") { horizon = .payday(2) }
            Button("3rd payday") { horizon = .payday(3) }
            Button("4th payday") { horizon = .payday(4) }
            Button("5th payday") { horizon = .payday(5) }
            if let rent {
                Button("Rent due (\(rent.dueDate.formatted(.dateTime.month().day())))") { horizon = .on(rent.dueDate) }
            }
            if let cardDue = cards.map(\.nextDueDate).min() {
                Button("Card due (\(cardDue.formatted(.dateTime.month().day())))") { horizon = .on(cardDue) }
            }
            Button("End of month") { horizon = .endOfMonth }
            Button("End of year") { horizon = .endOfYear }
            Button("Pick a date…") { showDatePicker = true }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text("Through: \(horizon.label)").fontWeight(.semibold)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.btwCard, in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker("Horizon", selection: $customDate, in: Date.now..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Pick a date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showDatePicker = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { horizon = .on(customDate); showDatePicker = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Shared computations

    private var netRatio: Double {
        guard let settings else { return 0.77 }
        return BudgetMath.averageNetRatio(paychecks, fallback: settings.defaultNetRatio)
    }

    private var effectiveHourly: Double {
        guard let settings else { return 0 }
        return BudgetMath.effectiveHourly(hourlyWage: settings.hourlyWage, netRatio: netRatio)
    }

    private func breakdown(_ settings: AppSettings) -> HorizonBreakdown {
        ProjectionEngine.breakdown(by: horizon.endDate(settings: settings), settings: settings, entries: ledger, recurrings: recurrings, paychecks: paychecks, workDays: workDays, rent: rent, cards: cards, essentialCategories: essentialSet)
    }

    private func projected(_ settings: AppSettings, by date: Date) -> Double {
        ProjectionEngine.projectedBalance(asOf: date, settings: settings, entries: ledger, recurrings: recurrings, paychecks: paychecks, workDays: workDays)
    }

    private func nextPaycheck(_ settings: AppSettings) -> (date: Date, gross: Double, net: Double) {
        let period = settings.upcomingPayPeriod
        let hours = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays)
        let gross = BudgetMath.gross(hours: hours, hourlyWage: settings.hourlyWage)
        return (period.payday, gross, gross * netRatio)
    }

    // MARK: Hero ring

    private func heroRing(_ settings: AppSettings) -> some View {
        let end = horizon.endDate(settings: settings)
        let bd = breakdown(settings)
        let safe = bd.safe
        let isNegative = safe < 0
        let tint: Color = isNegative ? .red : .green
        let progress = bd.inflowTotal > 0 ? min(max(safe / bd.inflowTotal, 0), 1) : 0
        return VStack(spacing: 14) {
            RingGauge(progress: progress, tint: tint) {
                VStack(spacing: 2) {
                    Text(safe, format: .currency(code: "USD"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                        .foregroundStyle(isNegative ? .red : .primary)
                    Text(isNegative ? "Over Budget" : "Safe to Spend")
                        .font(.subheadline)
                        .foregroundStyle(isNegative ? .red : .secondary)
                }
                .padding(.horizontal, 24)
            }
            .frame(width: 220, height: 220)

            if isNegative {
                Text("Short \(abs(safe).formatted(.currency(code: "USD"))) by \(end.formatted(.dateTime.month().day()))")
                    .font(.subheadline).foregroundStyle(.red)
            } else {
                Text(BudgetMath.workTimeDescription(forDollars: safe, effectiveHourly: effectiveHourly, unit: settings.workTimeUnit ?? .hours, hoursPerWorkday: settings.scheduledPaidHoursPerDay, workdaysPerWeek: settings.workdayWeekdays.count))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(bd.inflowTotal.formatted(.currency(code: "USD"))) in − \(abs(bd.outflowTotal).formatted(.currency(code: "USD"))) out, through \(end.formatted(.dateTime.month().day()))")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Left to Spend (itemized)

    private func leftToSpendCard(_ settings: AppSettings) -> some View {
        let end = horizon.endDate(settings: settings)
        let bd = breakdown(settings)
        let days = max(BudgetMath.daysUntil(end), 1)
        let free = bd.freeToSpend
        let rate = rateBasis.value(safe: free, days: days)
        return Card(title: "Free to Spend · \(horizon.label)", systemImage: "party.popper.fill", tint: free < 0 ? .red : .green) {
            Text(free, format: .currency(code: "USD"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(free < 0 ? .red : .primary)
            Picker("Rate", selection: $rateBasis) {
                ForEach(RateBasis.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("\(rate.formatted(.currency(code: "USD")))\(rateBasis.suffix) for fun through \(end.formatted(.dateTime.month().day())) — after this, only essentials are covered.")
                .font(.caption)
                .foregroundStyle(free < 0 ? .red : .secondary)
            HStack {
                breakdownStat("In", bd.inflowTotal)
                Divider().frame(height: 28)
                breakdownStat("Essentials", bd.essentialOutflowTotal)
                Divider().frame(height: 28)
                breakdownStat("Free", free)
            }
            HStack {
                Button { showEssentials = true } label: { Label("Essentials", systemImage: "slider.horizontal.3") }
                Spacer()
                Button { freeForFund = max(free, 0); showMoveToFund = true } label: { Label("Save to a fund", systemImage: "arrow.down.to.line") }
                    .disabled(free <= 0)
            }
            .font(.caption)
            .buttonStyle(.borderless)
            DisclosureGroup("Show every line") {
                VStack(spacing: 6) {
                    ForEach(bd.inflows) { lineRow($0) }
                    if !bd.outflows.isEmpty {
                        Divider()
                        ForEach(bd.outflows) { lineRow($0) }
                    }
                }
                .padding(.top, 4)
            }
            .font(.caption)
            .tint(.blue)
        }
    }

    private func lineRow(_ line: ProjectionLine) -> some View {
        HStack {
            Text(line.count > 1 ? "\(line.label) ×\(line.count)" : line.label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(line.total, format: .currency(code: "USD"))
                .foregroundStyle(line.total < 0 ? .red : .green)
                .fontWeight(.medium)
        }
        .font(.caption)
    }

    private func breakdownStat(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(value, format: .currency(code: "USD"))
                .font(.callout.weight(.semibold))
                .foregroundStyle(value < 0 ? .red : .primary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func breakdownRow(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .currency(code: "USD"))
                .foregroundStyle(value < 0 ? .red : .primary)
                .fontWeight(bold ? .semibold : .regular)
        }
        .font(.subheadline)
    }

    // MARK: Next paycheck

    private func paycheckCard(_ settings: AppSettings) -> some View {
        let forecast = nextPaycheck(settings)
        let days = BudgetMath.daysUntil(forecast.date)
        let withheld = max(forecast.gross - forecast.net, 0)
        let pct = RetirementLogic.effectivePercent(at: forecast.date, settings: settings)
        let retire = forecast.gross * pct
        let match = forecast.gross * Swift.min(pct, settings.employerMatchPercent)
        let taxes = max(withheld - retire, 0)
        return Card(title: "Next Paycheck", systemImage: "calendar.badge.clock", tint: .blue) {
            Text(forecast.net, format: .currency(code: "USD"))
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(forecast.date.formatted(.dateTime.weekday(.wide).month().day())) · in \(days) days")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 4) {
                breakdownRow("Gross pay", forecast.gross)
                breakdownRow("− Taxes (est.)", -taxes)
                breakdownRow("− 401(k)", -retire)
                breakdownRow("= Take-home", forecast.net, bold: true)
            }
            if match > 0 {
                Text("Employer adds \(match, format: .currency(code: "USD")) to your 401(k) (match)")
                    .font(.caption2).foregroundStyle(.green)
            }
            Text(paychecks.isEmpty
                 ? "Estimated at \(Int((netRatio * 100).rounded()))% take-home — log a real paycheck to sharpen this."
                 : "Learned from your last \(paychecks.count) paycheck(s): \(Int((netRatio * 100).rounded()))% take-home.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Rent readiness (projected by due date)

    private func rentCard(_ settings: AppSettings) -> some View {
        let rentAmount = rent?.amount ?? 0
        let due = rent?.dueDate ?? .now
        let projectedByDue = rent != nil ? projected(settings, by: due) : 0
        let days = rent.map { BudgetMath.daysUntil($0.dueDate) } ?? 0
        let progress = rentAmount > 0 ? min(max(projectedByDue / rentAmount, 0), 1) : 0
        let shortfall = rentAmount - projectedByDue
        let covered = shortfall <= 0
        return Card(title: "Rent Readiness", systemImage: "house.fill", tint: covered ? .green : .orange) {
            HStack(alignment: .firstTextBaseline) {
                Text(projectedByDue, format: .currency(code: "USD"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(covered ? .green : .primary)
                Text("projected by \(due.formatted(.dateTime.month().day()))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress).tint(covered ? .green : .orange)
            if rentAmount > 0 {
                Text(covered
                     ? "Rent \(rentAmount, format: .currency(code: "USD")) covered — \((projectedByDue - rentAmount), format: .currency(code: "USD")) to spare"
                     : "Rent \(rentAmount, format: .currency(code: "USD")) due in \(days) days · short \(shortfall, format: .currency(code: "USD"))")
                    .font(.caption)
                    .foregroundStyle(covered ? .green : .orange)
            }
        }
    }

    // MARK: Credit cards (with statement readiness)

    private func creditCardsCard(_ settings: AppSettings) -> some View {
        Card(title: "Credit Cards", systemImage: "creditcard.fill", tint: .red) {
            ForEach(cards) { card in
                let due = card.nextDueDate
                let days = BudgetMath.daysUntil(due)
                let projByDue = projected(settings, by: due)
                let covers = projByDue >= card.statementBalance
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(card.name).fontWeight(.medium)
                        Spacer()
                        Text(CardLogic.balance(for: card, entries: ledger), format: .currency(code: "USD")).fontWeight(.semibold)
                    }
                    Text("Statement \(card.statementBalance, format: .currency(code: "USD")) · min \(card.minimumPayment, format: .currency(code: "USD")) · due \(due.formatted(.dateTime.month().day())) (in \(days)d)")
                        .font(.caption)
                        .foregroundStyle(days <= 3 ? Color.red : Color.secondary)
                    if card.statementBalance > 0 {
                        Text(covers
                             ? "On track to pay the statement by \(due.formatted(.dateTime.month().day()))"
                             : "Statement may be short \((card.statementBalance - projByDue).formatted(.currency(code: "USD"))) by \(due.formatted(.dateTime.month().day()))")
                            .font(.caption2)
                            .foregroundStyle(covers ? .green : .orange)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Net Worth (wealth snapshot — distinct from Safe to Spend)

    private func savingsCard(_ settings: AppSettings) -> some View {
        let balance = BalanceLogic.balance(asOf: .now, anchorAmount: settings.currentCashBalance, anchorDate: settings.balanceAnchorDate, entries: ledger)
        let funds = buckets.filter { $0.kind == .emergency || $0.kind == .medSchool || $0.kind == .apartment }
        let fundsTotal = funds.reduce(0) { $0 + $1.currentAmount }
        let retire = RetirementLogic.balance(settings: settings, workDays: workDays)
        let net = balance + fundsTotal + retire - creditOwed
        return Card(title: "Net Worth", systemImage: "chart.line.uptrend.xyaxis", tint: .purple) {
            Text(net, format: .currency(code: "USD"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(net < 0 ? .red : .primary)
            Text("Everything you have − what you owe (a snapshot now, not tied to the horizon).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(balance, format: .currency(code: "USD")) balance + \(fundsTotal, format: .currency(code: "USD")) funds + \(retire, format: .currency(code: "USD")) 401(k) − \(creditOwed, format: .currency(code: "USD")) cards")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if !funds.isEmpty {
                VStack(spacing: 10) {
                    ForEach(funds) { fund in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(fund.name, systemImage: fund.kind.systemImage)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(fund.currentAmount, format: .currency(code: "USD")) / \(fund.targetAmount, format: .currency(code: "USD"))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: fund.progress).tint(.purple)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Essentials editor

private struct EssentialsSheet: View {
    @AppStorage("essentialCategories") private var essentialCodes: String = "rent,utilities,groceries,transportation"
    @Environment(\.dismiss) private var dismiss

    private let options: [SpendCategory] = SpendCategory.allCases.filter { $0 != .savings && $0 != .income }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(options) { cat in
                        Toggle(isOn: binding(for: cat)) {
                            Label(cat.displayName, systemImage: cat.iconName)
                        }
                    }
                } header: {
                    Text("What counts as essential?")
                } footer: {
                    Text("\"Free to Spend\" is what's left for fun after covering these (plus credit-card balances) through your horizon. Toggle items off to see what you'd free up by sacrificing them.")
                }
            }
            .navigationTitle("Essentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func binding(for cat: SpendCategory) -> Binding<Bool> {
        Binding(
            get: { essentialCodes.split(separator: ",").map(String.init).contains(cat.rawValue) },
            set: { isOn in
                var items = Set(essentialCodes.split(separator: ",").map(String.init))
                if isOn { items.insert(cat.rawValue) } else { items.remove(cat.rawValue) }
                essentialCodes = items.sorted().joined(separator: ",")
            }
        )
    }
}

// MARK: - Move free money into a fund (surplus allocation)

private struct MoveToFundSheet: View {
    let suggested: Double

    @Query(sort: \Bucket.sortIndex) private var buckets: [Bucket]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Double
    @State private var selectedID: PersistentIdentifier?

    init(suggested: Double) {
        self.suggested = suggested
        _amount = State(initialValue: max(suggested, 0))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if buckets.isEmpty {
                        Text("Create a fund in the Buckets tab first.").foregroundStyle(.secondary)
                    } else {
                        Picker("Fund", selection: $selectedID) {
                            ForEach(buckets) { b in
                                Text(b.name).tag(Optional(b.persistentModelID))
                            }
                        }
                        LabeledContent("Amount") {
                            TextField("0.00", value: $amount, format: .currency(code: "USD"))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } footer: {
                    Text("Earmarks money toward a savings goal (emergency, med school, a vacation…). It stays in your balance but is labeled as set aside.")
                }
            }
            .keyboardDoneButton()
            .navigationTitle("Save to a Fund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(amount <= 0 || selectedID == nil)
                }
            }
            .onAppear { if selectedID == nil { selectedID = buckets.first?.persistentModelID } }
        }
    }

    private func save() {
        guard let id = selectedID, let bucket = buckets.first(where: { $0.persistentModelID == id }) else { dismiss(); return }
        bucket.currentAmount += amount
        try? context.save()
        dismiss()
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
