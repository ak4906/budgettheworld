//
//  RetirementLogic.swift
//  BudgetTheWorld
//
//  401(k): contribution %, employer match, annual auto-increase (capped), and a balance that
//  accumulates each paycheck's contribution + match — and stops once employment ends.
//

import Foundation

enum RetirementLogic {
    /// Effective contribution % on a given date: base + annual auto-increases (capped),
    /// and 0 outside the employment window (so contributions stop when you leave the job).
    static func effectivePercent(at date: Date, settings: AppSettings, calendar: Calendar = .current) -> Double {
        let day = calendar.startOfDay(for: date)
        if day < calendar.startOfDay(for: settings.employmentStartDate) { return 0 }
        if day > calendar.startOfDay(for: settings.employmentEndDate) { return 0 }
        var pct = settings.retirementPercent
        let incStart = calendar.startOfDay(for: settings.annualIncreaseStartDate)
        if settings.annualIncreasePercent > 0, day >= incStart {
            let years = calendar.dateComponents([.year], from: incStart, to: day).year ?? 0
            pct += settings.annualIncreasePercent * Double(years + 1)
        }
        let cap = settings.annualIncreaseCap > 0 ? settings.annualIncreaseCap : 1.0
        return Swift.min(pct, cap)
    }

    /// Per-paycheck split: what you contribute, and what the employer matches (free money).
    static func contribution(forGross gross: Double, at date: Date, settings: AppSettings, calendar: Calendar = .current) -> (user: Double, match: Double) {
        let pct = effectivePercent(at: date, settings: settings, calendar: calendar)
        let user = Swift.max(0, gross * pct)
        let match = Swift.max(0, gross * Swift.min(pct, settings.employerMatchPercent))
        return (user, match)
    }

    /// Estimated 401(k) balance = anchor + every paycheck's (contribution + match) since the anchor date.
    static func balance(settings: AppSettings, workDays: [WorkDay], asOf reference: Date = .now, calendar: Calendar = .current) -> Double {
        var total = settings.retirementBalance
        guard settings.retirementPercent > 0 || settings.annualIncreasePercent > 0 else { return total }
        let anchorDay = calendar.startOfDay(for: settings.retirementAnchorDate)
        let endDay = calendar.startOfDay(for: reference)
        guard endDay > anchorDay else { return total }
        var period = BudgetMath.payPeriod(forPaydayOnOrAfter: settings.retirementAnchorDate, anchorStart: settings.periodAnchorStart, lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
        var guardC = 0
        while calendar.startOfDay(for: period.payday) <= endDay, guardC < 400 {
            if calendar.startOfDay(for: period.payday) > anchorDay {
                let hrs = WorkLogic.paidHours(from: period.start, to: period.endExclusive, settings: settings, overrides: workDays, calendar: calendar)
                let gross = BudgetMath.gross(hours: hrs, hourlyWage: settings.hourlyWage)
                let c = contribution(forGross: gross, at: period.payday, settings: settings, calendar: calendar)
                total += c.user + c.match
            }
            period = period.next(lengthDays: settings.periodLengthDays, payLagDays: settings.payLagDays, calendar: calendar)
            guardC += 1
        }
        return total
    }
}
