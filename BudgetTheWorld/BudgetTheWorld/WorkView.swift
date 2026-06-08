//
//  WorkView.swift
//  BudgetTheWorld
//
//  The Work tab: your standard day is counted automatically for every weekday.
//  Tap any day in the pay period to adjust it — mark it off, or set custom hours —
//  only when reality differed. No clocking in required.
//

import SwiftUI
import SwiftData

struct WorkView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query(sort: \WorkDay.date, order: .reverse) private var overrides: [WorkDay]
    @Query(sort: \LedgerEntry.date, order: .reverse) private var ledger: [LedgerEntry]

    @State private var editing: DayRef?

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let settings {
                    VStack(spacing: 16) {
                        standardDayCard(settings)
                        periodCard(settings)
                        recentPaychecksCard()
                    }
                    .padding()
                } else {
                    ContentUnavailableView("Setting things up…", systemImage: "hourglass")
                        .padding(.top, 80)
                }
            }
            .background(Color.btwBackground)
            .navigationTitle("Work")
            .sheet(item: $editing) { ref in
                EditDaySheet(date: ref.date, settings: settings, existing: WorkLogic.override(for: ref.date, in: overrides))
            }
        }
    }

    // MARK: Standard day

    private func standardDayCard(_ settings: AppSettings) -> some View {
        Card(title: "Standard Day", systemImage: "calendar.badge.clock", tint: .green) {
            Text("\(timeLabel(settings.scheduledStartMinutes)) – \(timeLabel(settings.scheduledEndMinutes))")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text("− \(settings.forecastLunchMinutes) min lunch  =  \(String(format: "%.2f", settings.scheduledPaidHoursPerDay)) paid hrs")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Counted automatically for every weekday — no clocking in. Tap a day below only if it was different.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Pay period

    private func periodCard(_ settings: AppSettings) -> some View {
        let cal = Calendar.current
        let period = settings.upcomingPayPeriod
        let start = period.start
        let days = WorkLogic.days(from: start, to: period.endExclusive)
        let today = cal.startOfDay(for: .now)
        let soFarEnd = min(cal.date(byAdding: .day, value: 1, to: today) ?? today, period.endExclusive)
        let hoursSoFar = WorkLogic.paidHours(from: start, to: max(soFarEnd, start), settings: settings, overrides: overrides)
        let projected = WorkLogic.paidHours(from: start, to: period.endExclusive, settings: settings, overrides: overrides)
        let projectedGross = projected * settings.hourlyWage

        return Card(title: "This Pay Period", systemImage: "calendar", tint: .blue) {
            Text("\(start.formatted(.dateTime.month().day())) – \(period.lastDay.formatted(.dateTime.month().day())) · paid \(period.payday.formatted(.dateTime.month().day()))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                stat("So far", String(format: "%.1f hrs", hoursSoFar))
                Divider().frame(height: 32)
                stat("Projected", String(format: "%.1f hrs", projected))
                Divider().frame(height: 32)
                stat("Gross", projectedGross.formatted(.currency(code: "USD")))
            }
            .padding(.vertical, 4)

            Divider()

            ForEach(days, id: \.self) { day in
                dayRow(day, settings: settings, calendar: cal, today: today)
            }
        }
    }

    // MARK: Recent paychecks (real synced deposits)

    private func recentPaychecksCard() -> some View {
        let pays = WorkLogic.recentPaychecks(from: ledger, limit: 8)
        return Card(title: "Recent Paychecks", systemImage: "banknote", tint: .green) {
            if pays.isEmpty {
                Text("Once your bank syncs (or you set an income transaction's Source to “Paycheck”), your real paychecks show up here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let avg = pays.reduce(0) { $0 + $1.amount } / Double(pays.count)
                Text("Avg \(avg.formatted(.currency(code: "USD"))) · last \(pays.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Divider()
                ForEach(pays) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.date.formatted(.dateTime.month().day().year()))
                            Text((p.subcategory?.isEmpty == false ? p.subcategory! : p.rawDescription))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(p.amount, format: .currency(code: "USD"))
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 3)
                }
                Text("Real deposits from your bank — your actual take-home. The projection above estimates your next check.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayRow(_ day: Date, settings: AppSettings, calendar cal: Calendar, today: Date) -> some View {
        let ov = WorkLogic.override(for: day, in: overrides)
        let hrs = WorkLogic.paidHours(for: day, settings: settings, override: ov)
        let scheduled = WorkLogic.isScheduledWeekday(day, settings: settings)
        let isToday = cal.isDate(day, inSameDayAs: today)
        return Button {
            editing = DayRef(date: day)
        } label: {
            HStack(spacing: 8) {
                Text(day.formatted(.dateTime.weekday(.abbreviated).month().day()))
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(.primary)
                if let ov, !ov.worked {
                    tag("off", .orange)
                } else if ov != nil {
                    tag("edited", .blue)
                }
                Spacer()
                if hrs > 0 {
                    Text(String(format: "%.2f hrs", hrs)).foregroundStyle(.secondary)
                } else if scheduled {
                    Text("off").foregroundStyle(.orange)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .font(.subheadline)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    // MARK: Helpers

    private func timeLabel(_ minutes: Int) -> String {
        let base = Calendar.current.startOfDay(for: .now)
        let d = Calendar.current.date(byAdding: .minute, value: minutes, to: base) ?? base
        return d.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Edit day sheet

private struct DayRef: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

private struct EditDaySheet: View {
    let date: Date
    let settings: AppSettings?
    let existing: WorkDay?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var worked: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var lunch: Int

    init(date: Date, settings: AppSettings?, existing: WorkDay?) {
        self.date = date
        self.settings = settings
        self.existing = existing
        let cal = Calendar.current
        let base = cal.startOfDay(for: date)
        let startMin = existing?.startMinutes ?? settings?.scheduledStartMinutes ?? 8 * 60
        let endMin = existing?.endMinutes ?? settings?.scheduledEndMinutes ?? 17 * 60
        _worked = State(initialValue: existing?.worked ?? true)
        _start = State(initialValue: cal.date(byAdding: .minute, value: startMin, to: base) ?? base)
        _end = State(initialValue: cal.date(byAdding: .minute, value: endMin, to: base) ?? base)
        _lunch = State(initialValue: existing?.lunchMinutes ?? settings?.forecastLunchMinutes ?? 45)
    }

    private var paidHours: Double {
        guard worked else { return 0 }
        let mins = Calendar.current.dateComponents([.minute], from: start, to: end).minute ?? 0
        return max(0, Double(mins - lunch) / 60.0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Worked this day", isOn: $worked)
                }
                if worked {
                    Section("Hours") {
                        DatePicker("Start", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("End", selection: $end, displayedComponents: .hourAndMinute)
                        Stepper("Unpaid lunch: \(lunch) min",
                                value: $lunch,
                                in: (settings?.lunchMinMinutes ?? 30)...(settings?.lunchMaxMinutes ?? 60),
                                step: 5)
                    }
                    Section {
                        LabeledContent("Paid hours", value: String(format: "%.2f hrs", paidHours))
                        LabeledContent("Earned", value: (paidHours * (settings?.hourlyWage ?? 0)).formatted(.currency(code: "USD")))
                    }
                }
                if existing != nil {
                    Section {
                        Button("Reset to standard day", role: .destructive) { reset() }
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month().day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
        }
    }

    private func save() {
        let cal = Calendar.current
        let base = cal.startOfDay(for: date)
        let startMin = minutesOfDay(start, cal: cal)
        let endMin = minutesOfDay(end, cal: cal)
        if let existing {
            existing.worked = worked
            existing.startMinutes = startMin
            existing.endMinutes = endMin
            existing.lunchMinutes = lunch
        } else {
            context.insert(WorkDay(date: base, worked: worked, startMinutes: startMin, endMinutes: endMin, lunchMinutes: lunch))
        }
        try? context.save()
        dismiss()
    }

    private func reset() {
        if let existing {
            context.delete(existing)
            try? context.save()
        }
        dismiss()
    }

    private func minutesOfDay(_ d: Date, cal: Calendar) -> Int {
        let c = cal.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

#Preview {
    WorkView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self], inMemory: true)
}
