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

    @AppStorage("bankSyncBaseURL") private var baseURL = ""
    @AppStorage("bankSyncSecret") private var appSecret = ""
    @AppStorage("bankSyncIsSourceOfTruth") private var sourceOfTruth = false
    @AppStorage("bankSyncLastSummary") private var lastSummary = ""

    @State private var busy = false
    @State private var message: String?
    @State private var isError = false
    @State private var showDisconnectConfirm = false

    private var configured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty && !appSecret.isEmpty
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
                        return summary
                    }
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        if busy { Spacer(); ProgressView() }
                    }
                }
                .disabled(!configured || busy)
            } header: {
                Text("Sync")
            } footer: {
                if !lastSummary.isEmpty { Text("Last sync: \(lastSummary)") }
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
