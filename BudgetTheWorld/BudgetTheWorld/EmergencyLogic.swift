//
//  EmergencyLogic.swift
//  BudgetTheWorld
//
//  Staged emergency-fund plan: starter buffer → 1 month of essentials → 3 months.
//

import Foundation

enum EmergencyLogic {
    struct Stage: Identifiable {
        let id = UUID()
        let name: String
        let target: Double
    }

    /// Rough monthly essential spend = rent + essential recurring items (monthly-equivalent).
    static func monthlyEssentials(rent: RentObligation?, recurrings: [RecurringTransaction], essentialCategories: Set<String>) -> Double {
        var total = rent?.amount ?? 0
        for r in recurrings where r.isActive && r.amount < 0 && essentialCategories.contains(r.category.rawValue) {
            let perMonth: Double
            switch r.cadence {
            case .daily: perMonth = -r.amount * 30.4
            case .weekly: perMonth = -r.amount * 4.33
            case .biweekly: perMonth = -r.amount * 2.17
            case .monthly: perMonth = -r.amount
            }
            total += perMonth
        }
        return total
    }

    static func stages(monthlyEssentials: Double) -> [Stage] {
        let oneMonth = Swift.max(monthlyEssentials, 1000)
        return [
            Stage(name: "Starter buffer", target: 1000),
            Stage(name: "1 month of essentials", target: oneMonth),
            Stage(name: "3 months of essentials", target: oneMonth * 3)
        ]
    }
}
