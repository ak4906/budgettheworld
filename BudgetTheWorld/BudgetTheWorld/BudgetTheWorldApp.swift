//
//  BudgetTheWorldApp.swift
//  BudgetTheWorld
//
//  App entry point: builds the SwiftData container (and the Application Support dir on first launch).
//

import SwiftUI
import SwiftData
import Foundation

@main
struct BudgetTheWorldApp: App {
    let modelContainer: ModelContainer

    init() {
        // SwiftData's default store lives in Library/Application Support, which doesn't exist yet on a
        // fresh install. Create it up front so CoreData doesn't print a (recoverable) wall of errors
        // the first time the app launches.
        _ = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        do {
            modelContainer = try ModelContainer(
                for: AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, PersonalDebt.self, LabelRule.self, CreditScoreEntry.self
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
