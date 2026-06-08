//
//  BankSyncView.swift
//  BudgetTheWorld
//
//  Connect the app to its Plaid backend and pull real transactions. Stage 1 works against Plaid
//  Sandbox (fake bank) to prove the pipeline; Stage 2 adds Plaid Link to connect a real bank.
//  Reached from Settings → Bank Sync.
//

import SwiftUI
import SwiftData

struct BankSyncView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LedgerEntry]

    @AppStorage("bankSyncBaseURL") private var baseURL = ""
    @AppStorage("bankSyncSecret") private var appSecret = ""
    @AppStorage("bankSyncIsSourceOfTruth") private var sourceOfTruth = false
    @AppStorage("bankSyncLastSummary") private var lastSummary = ""
    @AppStorage("bankSyncAccountsSummary") private var accountsSummary = ""
    @AppStorage("bankSyncLastSyncAt") private var lastSyncAt: Double = 0

    @State private var busy = false
    @State private var message: String?
    @State private var isError = false
    @State private var showDisconnectConfirm = false
    @State private var pendingCleanupTitle = ""
    @State private var pendingCleanup: (() -> Void)?

    private var configured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !appSecret.isEmpty
    }

    private var recurringCount: Int { entries.filter { $0.source == .recurring }.count }
    private var manualCount: Int { entries.filter { $0.source == .manual }.count }

    private func deleteEntries(source: TxnSource) {
        for e in entries where e.source == source { context.delete(e) }
        try? context.save()
    }

    var body: some View {
        Form {
            Section {
                TextField("Backend URL (https://…workers.dev)", text: $baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("App secret (your APP_SECRET)", text: $appSecret)
            } header: {
                Text("Connection")
            } footer: {
                Text("Deploy the Plaid backend (in the project's plaid-backend/ folder), then paste its URL and the shared secret you set.")
            }

            Section {
                Toggle("Bank is my source of truth", isOn: $sourceOfTruth)
            } footer: {
                Text("When on, the app stops auto-adding recurring items as past spending (your synced bank data covers actual spending). Recurring still powers the future forecast.")
            }

            Section {
                Button { connectBank() } label: {
                    Label("Connect a bank (Plaid Link)", systemImage: "link")
                }
                .disabled(!configured || busy)

                Button {
                    run { try await PlaidSyncService.seedSandbox(baseURL: baseURL, appSecret: appSecret)
                        return "Sandbox test bank linked. Now tap “Sync now.”" }
                } label: {
                    Label("Set up sandbox test data", systemImage: "testtube.2")
                }
                .disabled(!configured || busy)

                Button {
                    run {
                        let r = try await PlaidSyncService.sync(baseURL: baseURL, appSecret: appSecret, context: context)
                        let summary = "Added \(r.added), updated \(r.updated), removed \(r.removed)."
                        lastSummary = "\(Date.now.formatted(date: .abbreviated, time: .shortened)) · \(summary)"
                        lastSyncAt = Date.now.timeIntervalSince1970
                        return summary
                    }
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(!configured || busy)

                Button {
                    run {
                        let r = try await PlaidSyncService.resyncAll(baseURL: baseURL, appSecret: appSecret, context: context)
                        return "Re-synced all history. Added \(r.added), updated \(r.updated)."
                    }
                } label: {
                    Label("Re-sync all history (re-tag accounts)", systemImage: "arrow.clockwise.circle")
                }
                .disabled(!configured || busy)
            } header: {
                Text("Sync")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if lastSyncAt > 0 {
                        Text("Last synced \(Date(timeIntervalSince1970: lastSyncAt).formatted(.relative(presentation: .named))).")
                    }
                    Text("Auto-syncs when you open the app (at most once every 6 hours), so you don't have to remember. Tap “Sync now” to refresh immediately.")
                    if !lastSummary.isEmpty { Text(lastSummary).foregroundStyle(.tertiary) }
                }
            }

            if !accountsSummary.isEmpty {
                Section {
                    Text(accountsSummary).font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Accounts seen on last sync")
                } footer: {
                    Text("name · kind · balance. If your savings isn't listed (or shows the wrong kind), the backend needs a redeploy. If it's listed correctly but $0 elsewhere, tell me.")
                }
            }

            if recurringCount > 0 || manualCount > 0 {
                Section {
                    if recurringCount > 0 {
                        Button(role: .destructive) {
                            pendingCleanupTitle = "Delete \(recurringCount) recurring-generated rows?"
                            pendingCleanup = { deleteEntries(source: .recurring) }
                        } label: { Label("Delete recurring-generated rows (\(recurringCount))", systemImage: "repeat") }
                    }
                    if manualCount > 0 {
                        Button(role: .destructive) {
                            pendingCleanupTitle = "Delete \(manualCount) manually-added rows?"
                            pendingCleanup = { deleteEntries(source: .manual) }
                        } label: { Label("Delete manually-added rows (\(manualCount))", systemImage: "hand.tap") }
                    }
                } header: {
                    Text("Clean up duplicates")
                } footer: {
                    Text("Bank sync now provides your real transactions, so old recurring/manual rows can double-count them. Removing these doesn't affect your recurring items — those still power the forecast.")
                }
            }

            Section {
                Button(role: .destructive) { showDisconnectConfirm = true } label: {
                    Label("Disconnect bank & delete synced data", systemImage: "trash")
                }
                .disabled(!configured || busy)
            } footer: {
                Text("Revokes the Plaid connection and removes bank-synced transactions from this device. Your manual entries are kept.")
            }

            if let message {
                Section { Text(message).font(.caption).foregroundStyle(isError ? .red : .green) }
            }

            Section {
                Text("Stage 1 uses Plaid Sandbox to prove the pipeline. Connecting your real Bank of America account (Plaid Link + Production) is the next step.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .navigationTitle("Bank Sync")
        .keyboardDoneButton()
        .confirmationDialog("Disconnect bank?", isPresented: $showDisconnectConfirm, titleVisibility: .visible) {
            Button("Disconnect & delete", role: .destructive) {
                run {
                    let n = try await PlaidSyncService.disconnect(baseURL: baseURL, appSecret: appSecret, context: context)
                    lastSummary = ""
                    return "Disconnected. Removed \(n) synced transaction(s)."
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This revokes Plaid access and deletes bank-synced transactions. Manual entries stay.")
        }
        .confirmationDialog(pendingCleanupTitle,
                            isPresented: Binding(get: { pendingCleanup != nil }, set: { if !$0 { pendingCleanup = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { pendingCleanup?(); pendingCleanup = nil }
            Button("Cancel", role: .cancel) { pendingCleanup = nil }
        }
    }

    private func connectBank() {
        busy = true
        message = nil
        Task {
            do {
                let token = try await PlaidSyncService.createLinkToken(baseURL: baseURL, appSecret: appSecret)
                PlaidLinkPresenter.shared.present(
                    token: token,
                    onSuccess: { publicToken in
                        Task {
                            do {
                                try await PlaidSyncService.exchange(baseURL: baseURL, appSecret: appSecret, publicToken: publicToken)
                                let r = try await PlaidSyncService.sync(baseURL: baseURL, appSecret: appSecret, context: context)
                                lastSummary = "\(Date.now.formatted(date: .abbreviated, time: .shortened)) · connected · added \(r.added)"
                                message = "Connected! Added \(r.added) transactions."
                                isError = false
                            } catch {
                                message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                                isError = true
                            }
                            busy = false
                        }
                    },
                    onExit: { busy = false }
                )
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                isError = true
                busy = false
            }
        }
    }

    private func run(_ op: @escaping () async throws -> String) {
        busy = true
        message = nil
        Task {
            do {
                let result = try await op()
                message = result
                isError = false
            } catch {
                message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                isError = true
            }
            busy = false
        }
    }
}

#Preview {
    NavigationStack { BankSyncView() }
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self, PersonalDebt.self], inMemory: true)
}
