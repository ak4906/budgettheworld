//
//  WorkLogic.swift
//  BudgetTheWorld
//
//  Model-aware work-hours calculation. The core idea: every scheduled weekday is
//  assumed worked at the default schedule unless a WorkDay override says otherwise.
//

import Foundation
import SwiftData

enum WorkLogic {

    /// The override (if any) recorded for a given calendar day.
    static func override(for date: Date, in overrides: [WorkDay], calendar: Calendar = .current) -> WorkDay? {
        overrides.first { calendar.isDate($0.date, inSameDayAs: date) }
    }

    static func isScheduledWeekday(_ date: Date, settings: AppSettings, calendar: Calendar = .current) -> Bool {
        settings.workdayWeekdays.contains(calendar.component(.weekday, from: date))
    }

    /// Effective paid hours for a single day: the override if present, else the default
    /// schedule for a scheduled weekday, else 0 (weekend with no override).
    static func paidHours(for date: Date, settings: AppSettings, override: WorkDay?, calendar: Calendar = .current) -> Double {
        let day = calendar.startOfDay(for: date)
        // No pay before hire or after employment ends.
        if day < calendar.startOfDay(for: settings.employmentStartDate) { return 0 }
        if day > calendar.startOfDay(for: settings.employmentEndDate) { return 0 }
        if let override { return override.paidHours }
        return isScheduledWeekday(date, settings: settings, calendar: calendar) ? settings.scheduledPaidHoursPerDay : 0
    }

    /// Total effective paid hours over the half-open range [start, end).
    static func paidHours(from start: Date, to end: Date, settings: AppSettings, overrides: [WorkDay], calendar: Calendar = .current) -> Double {
        var total = 0.0
        for day in days(from: start, to: end, calendar: calendar) {
            total += paidHours(for: day, settings: settings, override: override(for: day, in: overrides, calendar: calendar), calendar: calendar)
        }
        return total
    }

    /// Every calendar day in [start, end).
    static func days(from start: Date, to end: Date, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day < last {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

extension WorkLogic {
    /// True if a logged/synced deposit represents work pay (a paycheck), as opposed to a gift,
    /// refund, transfer, cash-back, etc. Prefers the income "Source" label; falls back to the
    /// bank description for unlabeled synced income.
    static func isPaycheckDeposit(_ entry: LedgerEntry) -> Bool {
        guard entry.amount > 0, entry.category == .income else { return false }
        let src = (entry.subcategory ?? "").lowercased()
        if !src.isEmpty {
            return src.contains("paycheck") || src.contains("payroll") || src.contains("wage")
                || src.contains("salary") || src.contains("bonus")
        }
        let d = entry.rawDescription.lowercased()
        return d.contains("payroll") || d.contains("paycheck") || d.contains("direct dep")
            || d.contains("dir dep") || d.contains("salary")
    }

    /// Most-recent real paycheck deposits (actual take-home), newest first.
    static func recentPaychecks(from entries: [LedgerEntry], limit: Int = 8) -> [LedgerEntry] {
        Array(entries.filter(isPaycheckDeposit).sorted { $0.date > $1.date }.prefix(limit))
    }
}
