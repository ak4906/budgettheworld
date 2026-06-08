//
//  BudgetModels.swift
//  BudgetTheWorld
//
//  SwiftData model layer + shared enums. Everything that gets persisted lives here.
//

import Foundation
import SwiftData

// MARK: - Enums

enum PayCadence: String, Codable, CaseIterable, Identifiable {
    case weekly, biweekly, semimonthly, monthly
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Biweekly"
        case .semimonthly: "Twice a month"
        case .monthly: "Monthly"
        }
    }
    /// Days between paydays, used to size forecast windows.
    var periodDays: Int {
        switch self {
        case .weekly: 7
        case .biweekly: 14
        case .semimonthly: 15
        case .monthly: 30
        }
    }
}

enum WorkTimeUnit: String, Codable, CaseIterable, Identifiable {
    case hours, workdays, workweeks, workmonths
    var id: String { rawValue }
    var label: String {
        switch self {
        case .hours: "Hours"
        case .workdays: "Workdays"
        case .workweeks: "Work-weeks"
        case .workmonths: "Work-months"
        }
    }
}

enum BucketKind: String, Codable, CaseIterable, Identifiable {
    case rentReserve, emergency, medSchool, apartment, lifestyle, custom
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .rentReserve: "Rent Reserve"
        case .emergency: "Emergency Fund"
        case .medSchool: "Med School Fund"
        case .apartment: "Apartment Setup"
        case .lifestyle: "Lifestyle"
        case .custom: "Savings"
        }
    }
    var systemImage: String {
        switch self {
        case .rentReserve: "house.fill"
        case .emergency: "cross.case.fill"
        case .medSchool: "graduationcap.fill"
        case .apartment: "bed.double.fill"
        case .lifestyle: "cup.and.saucer.fill"
        case .custom: "banknote.fill"
        }
    }
}

enum SpendCategory: String, Codable, CaseIterable, Identifiable {
    case rent, utilities, groceries, food, transportation, fun, furniture,
         clothing, subscriptions, tech, travel, household, healthcare, personalCare,
         insurance, gifts, education, fees, pets,
         savings, income, other
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .rent: "Rent"
        case .utilities: "Utilities"
        case .groceries: "Groceries"
        case .food: "Food & Drink"
        case .transportation: "Transportation"
        case .fun: "Fun & Dates"
        case .furniture: "Furniture"
        case .clothing: "Clothing"
        case .subscriptions: "Subscriptions"
        case .tech: "Tech"
        case .travel: "Travel"
        case .household: "Household"
        case .healthcare: "Healthcare"
        case .personalCare: "Personal Care"
        case .insurance: "Insurance"
        case .gifts: "Gifts"
        case .education: "Education"
        case .fees: "Fees & Charges"
        case .pets: "Pets"
        case .savings: "Savings"
        case .income: "Income"
        case .other: "Other"
        }
    }
    /// 50/30/20 classification for the wisdom engine (M5).
    var needsWantsSavings: String {
        switch self {
        case .rent, .utilities, .groceries, .transportation, .healthcare, .insurance, .household, .education, .personalCare, .fees: "Needs"
        case .food, .fun, .furniture, .other, .clothing, .subscriptions, .tech, .travel, .gifts, .pets: "Wants"
        case .savings: "Savings"
        case .income: "Income"
        }
    }

    var iconName: String {
        switch self {
        case .rent: "house.fill"
        case .utilities: "bolt.fill"
        case .groceries: "cart.fill"
        case .food: "fork.knife"
        case .transportation: "tram.fill"
        case .fun: "party.popper.fill"
        case .furniture: "bed.double.fill"
        case .clothing: "tshirt.fill"
        case .subscriptions: "play.rectangle.fill"
        case .tech: "laptopcomputer"
        case .travel: "airplane"
        case .household: "shippingbox.fill"
        case .healthcare: "cross.case.fill"
        case .personalCare: "comb.fill"
        case .insurance: "checkmark.shield.fill"
        case .gifts: "gift.fill"
        case .education: "book.fill"
        case .fees: "building.columns.fill"
        case .pets: "pawprint.fill"
        case .savings: "banknote.fill"
        case .income: "arrow.down.circle.fill"
        case .other: "tag.fill"
        }
    }
}

/// Where a ledger entry came from. Lets manual import (now) and Plaid (later) coexist.
enum TxnSource: String, Codable {
    case manual, csvImport, plaid, recurring
}

/// Optional "who/what for" tag on a purchase, for later analysis (gifts vs. self vs. a date, etc.).
enum TxnPurpose: String, Codable, CaseIterable, Identifiable {
    case personal, treat, date, gift, family, work, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .personal: "For myself"
        case .treat: "Treat"
        case .date: "Date"
        case .gift: "Gift"
        case .family: "Family"
        case .work: "Work"
        case .other: "Other"
        }
    }
    var icon: String {
        switch self {
        case .personal: "person.fill"
        case .treat: "sparkles"
        case .date: "heart.fill"
        case .gift: "gift.fill"
        case .family: "house.fill"
        case .work: "briefcase.fill"
        case .other: "tag.fill"
        }
    }
}

/// Optional meal tag for Food & Drink purchases.
enum MealType: String, Codable, CaseIterable, Identifiable {
    case breakfast, brunch, lunch, dinner, snack, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breakfast: "Breakfast"
        case .brunch: "Brunch"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        case .other: "Other"
        }
    }
}

/// One item on a receipt (apples, milk, tax…), stored as a Codable blob on a LedgerEntry.
struct LineItemDTO: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var amount: Double = 0
    var quantity: Double = 1
    var unitPrice: Double { quantity > 0 ? amount / quantity : amount }
}

/// One dated credit-score reading, for the history graph.
@Model
final class CreditScoreEntry {
    var date: Date = Date.now
    var fico: Int = 0
    var vantage: Int = 0
    var note: String?

    init(date: Date = Date.now, fico: Int = 0, vantage: Int = 0, note: String? = nil) {
        self.date = date
        self.fico = fico
        self.vantage = vantage
        self.note = note
    }
}

// MARK: - Models

@Model
final class AppSettings {
    var hourlyWage: Double
    var scheduledStartMinutes: Int   // minutes from midnight; 8:00 AM == 480
    var scheduledEndMinutes: Int     // 5:00 PM == 1020
    var lunchMinMinutes: Int         // shortest unpaid lunch
    var lunchMaxMinutes: Int         // longest unpaid lunch
    var forecastLunchMinutes: Int    // assumed lunch when projecting pay (midpoint)
    var workdayWeekdays: [Int]       // Calendar weekday ints (Sun=1 ... Sat=7); Mon-Fri == [2,3,4,5,6]
    var defaultNetRatio: Double      // take-home estimate until real paychecks exist
    var payCadence: PayCadence
    var firstPaydayAnchor: Date      // any known payday; the cycle is derived from it
    var currentCashBalance: Double   // manual until bank sync (M6) lands

    // Pay-period model (M8): known period start + length (from cadence) + pay lag, plus employment dates.
    var periodAnchorStart: Date = Date.now
    var payLagDays: Int = 6                           // days after the period ends that payday lands
    var employmentStartDate: Date = Date.distantPast  // no pre-hire restriction until you set it
    var employmentEndDate: Date = Date.distantFuture
    var balanceAnchorDate: Date = Date.now            // currentCashBalance is the balance "as of" this date (M9)
    var savingsBalance: Double = 0                     // synced savings-account balance (multi-account)
    var savingsAnchorDate: Date = Date.now

    // Retirement / 401(k) (M11)
    var retirementPercent: Double = 0                 // fraction of gross contributed (e.g. 0.05 = 5%)
    var retirementBalance: Double = 0                 // known 401(k) balance as of the anchor date
    var retirementAnchorDate: Date = Date.now
    var employerMatchPercent: Double = 0          // 401(k): employer matches up to this fraction of gross
    var annualIncreasePercent: Double = 0         // auto-increase added to contribution each year
    var annualIncreaseStartDate: Date = Date.distantFuture
    var annualIncreaseCap: Double = 0.75
    var ficoScore: Int = 0            // latest known FICO score (300–850); 0 = unset (Int back-fills safely)
    var vantageScore: Int = 0         // latest known VantageScore (300–850); 0 = unset
    var workTimeUnit: WorkTimeUnit?   // how to express "work-hours" (M5); optional so it migrates without crashing (enums don't back-fill a default)

    init(
        hourlyWage: Double = 20.00,
        scheduledStartMinutes: Int = 8 * 60,
        scheduledEndMinutes: Int = 17 * 60,
        lunchMinMinutes: Int = 30,
        lunchMaxMinutes: Int = 60,
        forecastLunchMinutes: Int = 45,
        workdayWeekdays: [Int] = [2, 3, 4, 5, 6],
        defaultNetRatio: Double = 0.77,
        payCadence: PayCadence = .biweekly,
        firstPaydayAnchor: Date = .now,
        currentCashBalance: Double = 0,
        periodAnchorStart: Date = .now,
        payLagDays: Int = 6,
        employmentStartDate: Date = .distantPast,
        employmentEndDate: Date = .distantFuture,
        balanceAnchorDate: Date = .now,
        savingsBalance: Double = 0,
        savingsAnchorDate: Date = .now,
        retirementPercent: Double = 0,
        retirementBalance: Double = 0,
        retirementAnchorDate: Date = .now,
        employerMatchPercent: Double = 0,
        annualIncreasePercent: Double = 0,
        annualIncreaseStartDate: Date = .distantFuture,
        annualIncreaseCap: Double = 0.75,
        ficoScore: Int = 0,
        vantageScore: Int = 0,
        workTimeUnit: WorkTimeUnit? = .hours
    ) {
        self.hourlyWage = hourlyWage
        self.scheduledStartMinutes = scheduledStartMinutes
        self.scheduledEndMinutes = scheduledEndMinutes
        self.lunchMinMinutes = lunchMinMinutes
        self.lunchMaxMinutes = lunchMaxMinutes
        self.forecastLunchMinutes = forecastLunchMinutes
        self.workdayWeekdays = workdayWeekdays
        self.defaultNetRatio = defaultNetRatio
        self.payCadence = payCadence
        self.firstPaydayAnchor = firstPaydayAnchor
        self.currentCashBalance = currentCashBalance
        self.periodAnchorStart = periodAnchorStart
        self.payLagDays = payLagDays
        self.employmentStartDate = employmentStartDate
        self.employmentEndDate = employmentEndDate
        self.balanceAnchorDate = balanceAnchorDate
        self.savingsBalance = savingsBalance
        self.savingsAnchorDate = savingsAnchorDate
        self.retirementPercent = retirementPercent
        self.retirementBalance = retirementBalance
        self.retirementAnchorDate = retirementAnchorDate
        self.employerMatchPercent = employerMatchPercent
        self.annualIncreasePercent = annualIncreasePercent
        self.annualIncreaseStartDate = annualIncreaseStartDate
        self.annualIncreaseCap = annualIncreaseCap
        self.ficoScore = ficoScore
        self.vantageScore = vantageScore
        self.workTimeUnit = workTimeUnit
    }

    /// Paid hours for a normal scheduled day (shift length minus assumed lunch).
    var scheduledPaidHoursPerDay: Double {
        Double(scheduledEndMinutes - scheduledStartMinutes - forecastLunchMinutes) / 60.0
    }

    var periodLengthDays: Int { payCadence.periodDays }

    /// The pay period whose payday is the next one on or after today.
    var upcomingPayPeriod: BudgetMath.PayPeriod {
        BudgetMath.payPeriod(forPaydayOnOrAfter: .now, anchorStart: periodAnchorStart, lengthDays: periodLengthDays, payLagDays: payLagDays)
    }
}

@Model
final class Paycheck {
    var payDate: Date
    var grossAmount: Double
    var netAmount: Double
    var note: String?

    init(payDate: Date, grossAmount: Double, netAmount: Double, note: String? = nil) {
        self.payDate = payDate
        self.grossAmount = grossAmount
        self.netAmount = netAmount
        self.note = note
    }

    var netRatio: Double { grossAmount > 0 ? netAmount / grossAmount : 0 }
}

@Model
final class Bucket {
    var name: String
    var kind: BucketKind
    var targetAmount: Double
    var currentAmount: Double
    var monthlyContribution: Double
    var sortIndex: Int

    init(
        name: String,
        kind: BucketKind,
        targetAmount: Double,
        currentAmount: Double = 0,
        monthlyContribution: Double = 0,
        sortIndex: Int = 0
    ) {
        self.name = name
        self.kind = kind
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.monthlyContribution = monthlyContribution
        self.sortIndex = sortIndex
    }

    var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(currentAmount / targetAmount, 1)
    }
    var remaining: Double { max(targetAmount - currentAmount, 0) }
}

@Model
final class RentObligation {
    var amount: Double
    var dueDate: Date

    init(amount: Double, dueDate: Date) {
        self.amount = amount
        self.dueDate = dueDate
    }
}

@Model
final class LedgerEntry {
    var date: Date
    var amount: Double          // signed: negative = money out, positive = money in
    var rawDescription: String
    var category: SpendCategory
    var source: TxnSource
    var note: String?
    var cardName: String?              // nil = paid from checking; set = charged to this card
    var isCardPayment: Bool = false    // true = a payment toward a card (money leaves checking)
    var subcategory: String?           // optional free-text detail (e.g. "Boba", "Streaming", "Renter's")
    var merchant: String?              // optional store/location (e.g. "Trader Joe's", "Jin Ramen")
    var area: String?                  // optional broader location (e.g. "Hamilton Heights")
    var lineItemsData: Data?           // optional itemized receipt, encoded [LineItemDTO]
    var purpose: TxnPurpose?           // optional tag (date / gift / self …); optional so it migrates safely
    var plaidID: String?               // Plaid transaction_id for bank-synced rows (dedup/upsert); nil for manual
    var accountID: String?             // Plaid account_id the synced transaction belongs to
    var accountName: String?           // denormalized account label for display (e.g. "Checking", "BofA Credit")
    var essential: Bool?               // per-transaction need/want override (nil = use the category default)
    var mealType: MealType?            // optional meal tag for Food & Drink (breakfast/lunch/…)

    init(
        date: Date,
        amount: Double,
        rawDescription: String,
        category: SpendCategory = .other,
        source: TxnSource = .manual,
        note: String? = nil,
        cardName: String? = nil,
        isCardPayment: Bool = false,
        subcategory: String? = nil,
        merchant: String? = nil,
        area: String? = nil,
        purpose: TxnPurpose? = nil,
        plaidID: String? = nil,
        accountID: String? = nil,
        accountName: String? = nil,
        essential: Bool? = nil,
        mealType: MealType? = nil
    ) {
        self.date = date
        self.amount = amount
        self.rawDescription = rawDescription
        self.category = category
        self.source = source
        self.note = note
        self.cardName = cardName
        self.isCardPayment = isCardPayment
        self.subcategory = subcategory
        self.merchant = merchant
        self.area = area
        self.purpose = purpose
        self.plaidID = plaidID
        self.accountID = accountID
        self.accountName = accountName
        self.essential = essential
        self.mealType = mealType
    }

    /// Itemized receipt lines, decoded from `lineItemsData` (a computed accessor, not persisted directly).
    var lineItems: [LineItemDTO] {
        get { (lineItemsData.flatMap { try? JSONDecoder().decode([LineItemDTO].self, from: $0) }) ?? [] }
        set { lineItemsData = newValue.isEmpty ? nil : (try? JSONEncoder().encode(newValue)) }
    }

    var isExpense: Bool { amount < 0 }
    /// Whether this moves the checking balance: checking spends and card payments do; card charges don't.
    var affectsChecking: Bool { cardName == nil || isCardPayment }
}

/// An *exception* to the standard schedule for one day — a day off, or custom hours.
/// If no WorkDay exists for a weekday, that day is assumed worked at the default schedule.
/// (Inline defaults keep SwiftData's lightweight migration happy when the shape changes.)
@Model
final class WorkDay {
    var date: Date = Date.distantPast   // start of the calendar day this applies to
    var worked: Bool = true             // false = day off (no pay)
    var startMinutes: Int = 8 * 60      // minutes from midnight
    var endMinutes: Int = 17 * 60
    var lunchMinutes: Int = 45
    var note: String?

    init(date: Date, worked: Bool = true, startMinutes: Int, endMinutes: Int, lunchMinutes: Int, note: String? = nil) {
        self.date = date
        self.worked = worked
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.lunchMinutes = lunchMinutes
        self.note = note
    }

    var paidHours: Double {
        guard worked else { return 0 }
        return max(0, Double(endMinutes - startMinutes - lunchMinutes) / 60.0)
    }
}

/// A credit card you carry. `currentBalance` is what's building up; `statementBalance`
/// and `minimumPayment` are what's due this cycle. Due date recurs monthly on `dueDayOfMonth`.
@Model
final class CreditCard {
    var name: String = "Credit Card"
    var currentBalance: Double = 0      // total owed right now
    var statementBalance: Double = 0    // amount due this cycle to avoid interest
    var minimumPayment: Double = 0
    var dueDayOfMonth: Int = 1              // legacy; superseded by statementDueDate
    var statementDueDate: Date = Date.now   // when the CURRENT balance is due (recurs monthly)
    var balanceAnchorDate: Date = Date.now  // currentBalance is the balance "as of" this date; charges/payments move it
    var note: String?
    var plaidAccountID: String?             // Plaid account_id this card maps to (for sync matching)

    init(name: String, currentBalance: Double = 0, statementBalance: Double = 0, minimumPayment: Double = 0, dueDayOfMonth: Int = 1, statementDueDate: Date = .now, balanceAnchorDate: Date = .now, note: String? = nil, plaidAccountID: String? = nil) {
        self.name = name
        self.currentBalance = currentBalance
        self.statementBalance = statementBalance
        self.minimumPayment = minimumPayment
        self.dueDayOfMonth = dueDayOfMonth
        self.statementDueDate = statementDueDate
        self.balanceAnchorDate = balanceAnchorDate
        self.note = note
        self.plaidAccountID = plaidAccountID
    }

    /// The current balance's due date, rolled forward monthly until it's today or later.
    var nextDueDate: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var d = cal.startOfDay(for: statementDueDate)
        var guardCount = 0
        while d < today && guardCount < 120 {
            d = cal.date(byAdding: .month, value: 1, to: d) ?? d
            guardCount += 1
        }
        return d
    }
}

enum RecurringCadence: String, Codable, CaseIterable, Identifiable {
    case daily, weekly, biweekly, monthly
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        }
    }
}

/// A planned, repeating income or expense used for forward projection (M10).
/// New model, so no inline defaults are needed (all set via init).
@Model
final class RecurringTransaction {
    var amount: Double            // signed: negative = expense, positive = income
    var detail: String
    var category: SpendCategory
    var cadence: RecurringCadence
    var startDate: Date
    var endDate: Date             // distantFuture = ongoing
    var isActive: Bool
    var cardName: String?         // nil = paid from checking; set = charged to this card
    var lastMaterializedDate: Date = Date.distantPast   // last day we created real LedgerEntry rows for this series
    var skippedDatesRaw: String = ""    // comma-separated "y-m-d" occurrence dates the user skipped (per-instance override)

    init(amount: Double, detail: String, category: SpendCategory = .other, cadence: RecurringCadence = .monthly, startDate: Date = .now, endDate: Date = .distantFuture, isActive: Bool = true, cardName: String? = nil, lastMaterializedDate: Date = .distantPast) {
        self.amount = amount
        self.detail = detail
        self.category = category
        self.cadence = cadence
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.cardName = cardName
        self.lastMaterializedDate = lastMaterializedDate
    }
}

enum DebtStatus: String, Codable, CaseIterable, Identifiable {
    case dormant, active, forgiven
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dormant: "Dormant"
        case .active: "Active"
        case .forgiven: "Forgiven"
        }
    }
}

/// An informal/personal debt (e.g. money owed to family) — often no deadline. Noted, not
/// auto-counted in spendable numbers; can later become active (with a due date) or forgiven.
@Model
final class PersonalDebt {
    var lender: String
    var amount: Double
    var status: DebtStatus
    var dueDate: Date?
    var note: String?
    var countInNetWorth: Bool = false   // off by default — informal debts are noted but excluded from Net Worth unless you opt in

    init(lender: String, amount: Double, status: DebtStatus = .dormant, dueDate: Date? = nil, note: String? = nil, countInNetWorth: Bool = false) {
        self.lender = lender
        self.amount = amount
        self.status = status
        self.dueDate = dueDate
        self.note = note
        self.countInNetWorth = countInNetWorth
    }
}

/// A saved labeling rule: synced transactions whose description matches get these labels applied
/// automatically on every sync (created from "All + future" in the transaction editor).
@Model
final class LabelRule {
    var match: String              // matches LedgerEntry.rawDescription (case-insensitive)
    var category: SpendCategory
    var subcategory: String?
    var merchant: String?
    var purpose: TxnPurpose?

    var amount: Double?            // when set, rule only applies to txns with this amount (e.g. a fare vs a different charge at the same merchant)

    init(match: String, category: SpendCategory, subcategory: String? = nil, merchant: String? = nil, purpose: TxnPurpose? = nil, amount: Double? = nil) {
        self.match = match
        self.category = category
        self.subcategory = subcategory
        self.merchant = merchant
        self.purpose = purpose
        self.amount = amount
    }
}
