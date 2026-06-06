//
//  WorkLogic.swift
//  BudgetTheWorld
//
//  Model-aware work-hours calculation. The core idea: every scheduled weekday is
//  assumed worked at the default schedule unless a WorkDay override says otherwise.
//

import Foundation

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
