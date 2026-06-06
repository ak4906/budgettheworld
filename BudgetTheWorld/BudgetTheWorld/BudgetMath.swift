//
//  BudgetMath.swift
//  BudgetTheWorld
//
//  Pure, side-effect-free finance math. No SwiftData / SwiftUI here, so it stays trivially testable.
//

import Foundation

enum BudgetMath {

    // MARK: Work hours

    /// Paid hours for a shift = elapsed time minus the unpaid lunch.
    static func paidHours(clockIn: Date, clockOut: Date, lunchMinutes: Int) -> Double {
        let grossHours = clockOut.timeIntervalSince(clockIn) / 3600.0
        let lunchHours = Double(lunchMinutes) / 60.0
        return max(0, grossHours - lunchHours)
    }

    /// Clamp a lunch duration into the allowed unpaid-lunch window (e.g. 30-60 min).
    static func clampedLunchMinutes(_ minutes: Int, min lo: Int, max hi: Int) -> Int {
        Swift.min(Swift.max(minutes, lo), hi)
    }

    // MARK: Pay cycle

    /// The next payday on or after `reference`, derived from a known anchor payday + cadence.
    static func nextPayday(
        onOrAfter reference: Date = .now,
        anchor: Date,
        cadenceDays: Int,
        calendar: Calendar = .current
    ) -> Date {
        let refDay = calendar.startOfDay(for: reference)
        var candidate = calendar.startOfDay(for: anchor)

        if candidate >= refDay {
            // Anchor is today/future: step back to the earliest payday still >= today.
            while let prev = calendar.date(byAdding: .day, value: -cadenceDays, to: candidate), prev >= refDay {
                candidate = prev
            }
            return candidate
        }
        // Anchor is in the past: step forward to the first payday >= today.
        while candidate < refDay {
            guard let next = calendar.date(byAdding: .day, value: cadenceDays, to: candidate) else { break }
            candidate = next
        }
        return candidate
    }

    /// Whole days from `reference` until `date` (negative if `date` is past).
    static func daysUntil(_ date: Date, from reference: Date = .now, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: reference)
        let b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Count scheduled workdays in the half-open range [start, end).
    static func workdayCount(
        from start: Date,
        to end: Date,
        weekdays: Set<Int>,
        calendar: Calendar = .current
    ) -> Int {
        var count = 0
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day < last {
            if weekdays.contains(calendar.component(.weekday, from: day)) { count += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return count
    }

    // MARK: Take-home (adaptive net ratio)

    /// Average net/gross ratio across logged paychecks, falling back to an estimate until data exists.
    /// This is the "learn from real deposits" step: each real paycheck makes future forecasts sharper.
    static func averageNetRatio(_ paychecks: [Paycheck], fallback: Double) -> Double {
        let ratios = paychecks.filter { $0.grossAmount > 0 }.map { $0.netAmount / $0.grossAmount }
        guard !ratios.isEmpty else { return fallback }
        return ratios.reduce(0, +) / Double(ratios.count)
    }

    static func gross(hours: Double, hourlyWage: Double) -> Double {
        max(0, hours * hourlyWage)
    }

    /// Wage after the learned take-home ratio — the "real" dollars per hour worked.
    static func effectiveHourly(hourlyWage: Double, netRatio: Double) -> Double {
        max(0, hourlyWage * netRatio)
    }

    // MARK: Work-hours reframe

    /// "How much of my life did this cost?" — dollars expressed as work time.
    static func workTimeDescription(forDollars dollars: Double, effectiveHourly: Double) -> String {
        guard effectiveHourly > 0, dollars > 0 else { return "—" }
        let hours = dollars / effectiveHourly
        if hours < 1 {
            let minutes = Int((hours * 60).rounded())
            return "\(minutes) min of work"
        }
        return String(format: "%.1f hrs of work", hours)
    }

    /// Work-time expressed in the user's chosen unit (hours / workdays / work-weeks / work-months).
    static func workTimeDescription(forDollars dollars: Double, effectiveHourly: Double, unit: WorkTimeUnit, hoursPerWorkday: Double, workdaysPerWeek: Int) -> String {
        guard effectiveHourly > 0, dollars > 0 else { return "—" }
        let hours = dollars / effectiveHourly
        let perDay = max(hoursPerWorkday, 0.1)
        let perWeek = perDay * Double(max(workdaysPerWeek, 1))
        let perMonth = perWeek * 52.0 / 12.0

        let hoursPart = hours < 1 ? "\(Int((hours * 60).rounded())) min of work" : String(format: "%.1f hrs of work", hours)

        // A bigger, more intuitive unit shown alongside hours ("200 hrs · 4.8 work-weeks").
        var bigger: String?
        switch unit {
        case .hours:
            if hours >= perMonth { bigger = String(format: "%.1f work-months", hours / perMonth) }
            else if hours >= perWeek { bigger = String(format: "%.1f work-weeks", hours / perWeek) }
            else if hours >= perDay { bigger = String(format: "%.1f workdays", hours / perDay) }
        case .workdays: bigger = String(format: "%.1f workdays", hours / perDay)
        case .workweeks: bigger = String(format: "%.1f work-weeks", hours / perWeek)
        case .workmonths: bigger = String(format: "%.2f work-months", hours / perMonth)
        }
        if let bigger { return "\(hoursPart) · \(bigger)" }
        return hoursPart
    }

    /// Number of paydays from `reference` through `end` (inclusive of a payday on `end`).
    static func paydayCount(through end: Date, from reference: Date = .now, anchorStart: Date, lengthDays: Int, payLagDays: Int, calendar: Calendar = .current) -> Int {
        let endDay = calendar.startOfDay(for: end)
        guard endDay >= calendar.startOfDay(for: reference) else { return 0 }
        var count = 0
        var period = payPeriod(forPaydayOnOrAfter: reference, anchorStart: anchorStart, lengthDays: lengthDays, payLagDays: payLagDays, calendar: calendar)
        while calendar.startOfDay(for: period.payday) <= endDay && count < 60 {
            count += 1
            period = period.next(lengthDays: lengthDays, payLagDays: payLagDays, calendar: calendar)
        }
        return count
    }

    // MARK: Pay periods

    /// A single pay period: the days worked plus the date that work gets paid.
    struct PayPeriod {
        let start: Date          // inclusive first day (start of day)
        let endExclusive: Date   // start + length (exclusive)
        let payday: Date         // when this period is paid

        var lastDay: Date {
            Calendar.current.date(byAdding: .day, value: -1, to: endExclusive) ?? endExclusive
        }

        func next(lengthDays: Int, payLagDays: Int, calendar: Calendar = .current) -> PayPeriod {
            let s = calendar.date(byAdding: .day, value: lengthDays, to: start) ?? start
            return PayPeriod(
                start: s,
                endExclusive: calendar.date(byAdding: .day, value: lengthDays, to: s) ?? s,
                payday: calendar.date(byAdding: .day, value: (lengthDays - 1) + payLagDays, to: s) ?? s
            )
        }
    }

    /// The pay period whose payday is the first one on or after `reference`.
    static func payPeriod(forPaydayOnOrAfter reference: Date = .now, anchorStart: Date, lengthDays: Int, payLagDays: Int, calendar: Calendar = .current) -> PayPeriod {
        let len = max(lengthDays, 1)
        let offset = (len - 1) + payLagDays
        let index = ceilDiv(dayCount(from: anchorStart, to: reference, calendar: calendar) - offset, len)
        return period(index: index, anchorStart: anchorStart, lengthDays: len, payLagDays: payLagDays, calendar: calendar)
    }

    /// The pay period that contains `date`.
    static func payPeriod(containing date: Date, anchorStart: Date, lengthDays: Int, payLagDays: Int, calendar: Calendar = .current) -> PayPeriod {
        let len = max(lengthDays, 1)
        let index = floorDiv(dayCount(from: anchorStart, to: date, calendar: calendar), len)
        return period(index: index, anchorStart: anchorStart, lengthDays: len, payLagDays: payLagDays, calendar: calendar)
    }

    private static func period(index: Int, anchorStart: Date, lengthDays: Int, payLagDays: Int, calendar: Calendar) -> PayPeriod {
        let base = calendar.startOfDay(for: anchorStart)
        let start = calendar.date(byAdding: .day, value: index * lengthDays, to: base) ?? base
        return PayPeriod(
            start: start,
            endExclusive: calendar.date(byAdding: .day, value: lengthDays, to: start) ?? start,
            payday: calendar.date(byAdding: .day, value: (lengthDays - 1) + payLagDays, to: start) ?? start
        )
    }

    private static func dayCount(from a: Date, to b: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    private static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b, r = a % b
        return (r != 0 && ((r < 0) != (b < 0))) ? q - 1 : q
    }

    private static func ceilDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b, r = a % b
        return (r != 0 && ((r < 0) == (b < 0))) ? q + 1 : q
    }
}
