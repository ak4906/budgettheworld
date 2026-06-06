//
//  SettingsView.swift
//  BudgetTheWorld
//
//  Make the seeded numbers real: wage, the standard schedule, cash balance, rent,
//  and the take-home estimate. Plus Log-a-Paycheck, which teaches the app your true
//  net/gross ratio so forecasts get sharper with every real deposit.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var settingsList: [AppSettings]
    @Query private var rents: [RentObligation]

    var body: some View {
        NavigationStack {
            Group {
                if let settings = settingsList.first {
                    SettingsForm(settings: settings, rent: rents.first)
                } else {
                    ContentUnavailableView("Setting things up…", systemImage: "hourglass")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Form

private struct SettingsForm: View {
    @Bindable var settings: AppSettings
    let rent: RentObligation?
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    var body: some View {
        Form {
            Section("Pay") {
                LabeledContent("Hourly wage") {
                    TextField("Wage", value: $settings.hourlyWage, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                Picker("Pay schedule", selection: $settings.payCadence) {
                    ForEach(PayCadence.allCases) { Text($0.displayName).tag($0) }
                }
                DatePicker("Pay period start", selection: $settings.periodAnchorStart, displayedComponents: .date)
                Stepper("Payday: \(settings.payLagDays) days after period ends", value: $settings.payLagDays, in: 0...30)
                DatePicker("Employment start", selection: $settings.employmentStartDate, displayedComponents: .date)
                Toggle("Planned employment end", isOn: hasEmploymentEndBinding)
                if hasEmploymentEndBinding.wrappedValue {
                    DatePicker("Ends", selection: $settings.employmentEndDate, displayedComponents: .date)
                }
                LabeledContent("Next payday", value: settings.upcomingPayPeriod.payday.formatted(date: .abbreviated, time: .omitted))
            }

            Section("Standard schedule") {
                DatePicker("Start", selection: timeBinding(\.scheduledStartMinutes), displayedComponents: .hourAndMinute)
                DatePicker("End", selection: timeBinding(\.scheduledEndMinutes), displayedComponents: .hourAndMinute)
                Stepper("Assumed lunch: \(settings.forecastLunchMinutes) min", value: $settings.forecastLunchMinutes, in: 0...120, step: 5)
                LabeledContent("Paid hours / day", value: String(format: "%.2f", settings.scheduledPaidHoursPerDay))
                Picker("Show costs as", selection: workTimeUnitBinding) {
                    ForEach(WorkTimeUnit.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Lunch range (for day edits)") {
                Stepper("Min lunch: \(settings.lunchMinMinutes) min", value: $settings.lunchMinMinutes, in: 0...120, step: 5)
                Stepper("Max lunch: \(settings.lunchMaxMinutes) min", value: $settings.lunchMaxMinutes, in: 0...120, step: 5)
            }

            Section {
                LabeledContent("Balance amount") {
                    TextField("Balance", value: $settings.currentCashBalance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("As of", selection: $settings.balanceAnchorDate, displayedComponents: .date)
            } header: {
                Text("Checking balance")
            } footer: {
                Text("Transactions dated on or after this date add to or subtract from this balance.")
            }

            if let rent {
                RentSection(rent: rent)
            }

            Section("Credit Cards") {
                NavigationLink {
                    CreditCardsView()
                } label: {
                    Label("Manage cards", systemImage: "creditcard")
                }
            }

            Section("Debts") {
                NavigationLink {
                    DebtsView()
                } label: {
                    Label("Informal debts", systemImage: "person.2.fill")
                }
            }

            Section("Bank Sync") {
                NavigationLink {
                    BankSyncView()
                } label: {
                    Label("Connect & sync (Plaid)", systemImage: "building.columns")
                }
            }

            Section {
                Toggle(isOn: $appLockEnabled) {
                    Label("Require Face ID / passcode", systemImage: "faceid")
                }
            } header: {
                Text("Privacy & Security")
            } footer: {
                Text("Locks the app behind Face ID / Touch ID / your device passcode. Add a “Face ID” usage description in the Xcode target's Info settings or Face ID won't prompt.")
            }

            Section("Take-home") {
                Stepper("Estimate until paychecks: \(Int((settings.defaultNetRatio * 100).rounded()))%",
                        value: percentBinding, in: 50...100, step: 1)
                NavigationLink {
                    PaychecksView()
                } label: {
                    Label("Logged paychecks", systemImage: "banknote")
                }
            }

            Section {
                Stepper("Your contribution: \(Int((settings.retirementPercent * 100).rounded()))% of gross", value: retirementPercentBinding, in: 0...75)
                Stepper("Employer match: up to \(Int((settings.employerMatchPercent * 100).rounded()))%", value: employerMatchBinding, in: 0...25)
                Stepper("Auto-increase: +\(Int((settings.annualIncreasePercent * 100).rounded()))%/yr", value: annualIncreaseBinding, in: 0...10)
                if settings.annualIncreasePercent > 0 {
                    DatePicker("Increases start", selection: $settings.annualIncreaseStartDate, displayedComponents: .date)
                    Stepper("Cap at \(Int((settings.annualIncreaseCap * 100).rounded()))%", value: annualCapBinding, in: 0...100)
                }
                LabeledContent("Current 401(k) balance") {
                    TextField("Balance", value: $settings.retirementBalance, format: .currency(code: "USD"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("As of", selection: $settings.retirementAnchorDate, displayedComponents: .date)
            } header: {
                Text("Retirement / 401(k)")
            } footer: {
                Text("Your % is withheld from take-home; the employer match (up to its %) is added on top — free money. Auto-increase raises your % each year. Contributions stop after your employment end date.")
            }
        }
        .keyboardDoneButton()
        .scrollDismissesKeyboard(.interactively)
    }

    private var percentBinding: Binding<Int> {
        Binding(
            get: { Int((settings.defaultNetRatio * 100).rounded()) },
            set: { settings.defaultNetRatio = Double($0) / 100.0 }
        )
    }

    private var retirementPercentBinding: Binding<Int> {
        Binding(
            get: { Int((settings.retirementPercent * 100).rounded()) },
            set: { settings.retirementPercent = Double($0) / 100.0 }
        )
    }

    private var workTimeUnitBinding: Binding<WorkTimeUnit> {
        Binding(
            get: { settings.workTimeUnit ?? .hours },
            set: { settings.workTimeUnit = $0 }
        )
    }

    private var employerMatchBinding: Binding<Int> {
        Binding(get: { Int((settings.employerMatchPercent * 100).rounded()) }, set: { settings.employerMatchPercent = Double($0) / 100.0 })
    }
    private var annualIncreaseBinding: Binding<Int> {
        Binding(get: { Int((settings.annualIncreasePercent * 100).rounded()) }, set: { settings.annualIncreasePercent = Double($0) / 100.0 })
    }
    private var annualCapBinding: Binding<Int> {
        Binding(get: { Int((settings.annualIncreaseCap * 100).rounded()) }, set: { settings.annualIncreaseCap = Double($0) / 100.0 })
    }
    private var hasEmploymentEndBinding: Binding<Bool> {
        Binding(
            get: { settings.employmentEndDate.timeIntervalSinceNow < 100 * 365 * 86_400 },
            set: { on in settings.employmentEndDate = on ? (Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now) : .distantFuture }
        )
    }

    /// Bridges a minutes-from-midnight Int property to a Date the picker can edit.
    private func timeBinding(_ keyPath: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding(
            get: {
                let base = Calendar.current.startOfDay(for: .now)
                return Calendar.current.date(byAdding: .minute, value: settings[keyPath: keyPath], to: base) ?? base
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                settings[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}

private struct RentSection: View {
    @Bindable var rent: RentObligation
    var body: some View {
        Section("Rent") {
            LabeledContent("Amount") {
                TextField("Amount", value: $rent.amount, format: .currency(code: "USD"))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            DatePicker("Due date", selection: $rent.dueDate, displayedComponents: .date)
        }
    }
}

// MARK: - Paychecks

private struct PaychecksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Paycheck.payDate, order: .reverse) private var paychecks: [Paycheck]
    @Query private var settingsList: [AppSettings]
    @State private var showingAdd = false

    private var learnedRatio: Double {
        BudgetMath.averageNetRatio(paychecks, fallback: settingsList.first?.defaultNetRatio ?? 0.77)
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Learned take-home", value: "\(Int((learnedRatio * 100).rounded()))%")
                Text(paychecks.isEmpty
                     ? "No paychecks logged yet — add your real net pay to replace the estimate."
                     : "Averaged across \(paychecks.count) paycheck(s). Every one sharpens the forecast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Logged paychecks") {
                if paychecks.isEmpty {
                    Text("Nothing yet").foregroundStyle(.secondary)
                } else {
                    ForEach(paychecks) { pc in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(pc.payDate.formatted(date: .abbreviated, time: .omitted))
                                    .fontWeight(.medium)
                                Spacer()
                                Text("\(Int((pc.netRatio * 100).rounded()))%")
                                    .foregroundStyle(.secondary)
                            }
                            Text("Net \(pc.netAmount.formatted(.currency(code: "USD"))) of \(pc.grossAmount.formatted(.currency(code: "USD"))) gross")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Paychecks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { LogPaycheckSheet() }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(paychecks[i]) }
        try? context.save()
    }
}

private struct LogPaycheckSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var payDate = Date()
    @State private var gross = 0.0
    @State private var net = 0.0

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Pay date", selection: $payDate, displayedComponents: .date)
                Section("Amounts") {
                    LabeledContent("Gross") {
                        TextField("Before deductions", value: $gross, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Net deposited") {
                        TextField("What hit your account", value: $net, format: .currency(code: "USD"))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                if gross > 0 {
                    LabeledContent("Take-home", value: "\(Int((net / gross * 100).rounded()))%")
                }
            }
            .navigationTitle("Log Paycheck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(gross <= 0 || net <= 0)
                }
            }
            .keyboardDoneButton()
        }
    }

    private func save() {
        context.insert(Paycheck(payDate: payDate, grossAmount: gross, netAmount: net))
        try? context.save()
        dismiss()
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self], inMemory: true)
}
