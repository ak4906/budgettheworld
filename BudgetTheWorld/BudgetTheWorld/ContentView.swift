//
//  ContentView.swift
//  BudgetTheWorld
//
//  App shell: seeds data, materializes recurring, and — when the user opts in — gates everything
//  behind Face ID / Touch ID / device passcode (re-locks when the app is backgrounded).
//

import SwiftUI
import SwiftData
import LocalAuthentication

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appLockEnabled") private var appLockEnabled = false

    @State private var unlocked = false
    @State private var authenticating = false

    var body: some View {
        ZStack {
            RootTabView()
                .task {
                    BudgetSeed.seedIfNeeded(context)
                    RecurringMaterializer.catchUp(context: context)
                    try? await Task.sleep(for: .milliseconds(300))
                    KeyboardSupport.shared.installTapToDismiss()
                    KeyboardSupport.shared.prewarm()
                }

            if appLockEnabled && !unlocked {
                LockScreen(authenticating: authenticating) { authenticate() }
            }
        }
        .onAppear {
            if appLockEnabled { authenticate() } else { unlocked = true }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                if appLockEnabled { unlocked = false }   // re-lock when leaving the app
            case .active:
                if appLockEnabled && !unlocked { authenticate() }
            default:
                break
            }
        }
        .onChange(of: appLockEnabled) { _, enabled in
            // Turning the lock off unlocks now; turning it on takes effect on next background/launch.
            if !enabled { unlocked = true }
        }
    }

    private func authenticate() {
        guard appLockEnabled, !unlocked, !authenticating else { return }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // No biometrics/passcode is set on the device — don't lock the user out of their own app.
            unlocked = true
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication,
                           localizedReason: "Unlock BudgetTheWorld to view your finances.") { success, _ in
            DispatchQueue.main.async {
                authenticating = false
                if success { unlocked = true }
            }
        }
    }
}

private struct LockScreen: View {
    let authenticating: Bool
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            Color.btwBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("BudgetTheWorld is locked")
                    .font(.headline)
                Button(action: onUnlock) {
                    Label(authenticating ? "Unlocking…" : "Unlock", systemImage: "faceid")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(authenticating)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self, CreditCard.self, RecurringTransaction.self], inMemory: true)
}
