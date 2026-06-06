//
//  RootTabView.swift
//  BudgetTheWorld
//
//  Bottom tab bar — the navigation shell every screen lives in.
//  More tabs (Buckets, Transactions, Insights) get added as those milestones land.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
            WorkView()
                .tabItem { Label("Work", systemImage: "clock.fill") }
            BucketsView()
                .tabItem { Label("Buckets", systemImage: "bag.fill") }
            TransactionsView()
                .tabItem { Label("Spending", systemImage: "creditcard.fill") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
