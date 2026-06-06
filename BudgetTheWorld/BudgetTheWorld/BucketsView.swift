//
//  BucketsView.swift
//  BudgetTheWorld
//
//  Sinking funds made interactive: create, edit, add money, delete.
//  Emergency / med-school / apartment / rent-reserve all live here.
//

import SwiftUI
import SwiftData

struct BucketsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bucket.sortIndex) private var buckets: [Bucket]

    @State private var editing: Bucket?
    @State private var creatingNew = false

    private var totalSaved: Double { buckets.reduce(0) { $0 + $1.currentAmount } }
    private var totalTarget: Double { buckets.reduce(0) { $0 + $1.targetAmount } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    totalCard
                    ForEach(buckets) { bucket in
                        bucketCard(bucket)
                    }
                    if buckets.isEmpty {
                        ContentUnavailableView("No funds yet", systemImage: "tray",
                                               description: Text("Tap + to create a savings bucket."))
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
            .background(Color.btwBackground)
            .navigationTitle("Buckets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { EmergencyFundView() } label: { Image(systemName: "cross.case.fill") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { creatingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { EditBucketSheet(bucket: $0) }
            .sheet(isPresented: $creatingNew) { EditBucketSheet(bucket: nil) }
        }
    }

    private var totalCard: some View {
        Card(title: "Total Saved", systemImage: "building.columns.fill", tint: .green) {
            Text(totalSaved, format: .currency(code: "USD"))
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("across \(buckets.count) fund\(buckets.count == 1 ? "" : "s") · goal \(totalTarget, format: .currency(code: "USD"))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func bucketCard(_ bucket: Bucket) -> some View {
        Button { editing = bucket } label: {
            Card(title: bucket.name, systemImage: bucket.kind.systemImage, tint: bucket.kind.color) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bucket.currentAmount, format: .currency(code: "USD"))
                        .font(.title2.weight(.bold))
                    Text("of \(bucket.targetAmount, format: .currency(code: "USD"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((bucket.progress * 100).rounded()))%")
                        .font(.headline)
                        .foregroundStyle(bucket.kind.color)
                }
                ProgressView(value: bucket.progress).tint(bucket.kind.color)
                HStack {
                    Text("\(bucket.remaining, format: .currency(code: "USD")) to go")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if bucket.monthlyContribution > 0 {
                        Text("\(bucket.monthlyContribution, format: .currency(code: "USD"))/mo")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit sheet

private struct EditBucketSheet: View {
    let bucket: Bucket?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var kind: BucketKind
    @State private var target: Double
    @State private var current: Double
    @State private var monthly: Double
    @State private var addAmount: Double = 0

    init(bucket: Bucket?) {
        self.bucket = bucket
        _name = State(initialValue: bucket?.name ?? "")
        _kind = State(initialValue: bucket?.kind ?? .custom)
        _target = State(initialValue: bucket?.targetAmount ?? 0)
        _current = State(initialValue: bucket?.currentAmount ?? 0)
        _monthly = State(initialValue: bucket?.monthlyContribution ?? 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fund") {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $kind) {
                        ForEach(BucketKind.allCases) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Amounts") {
                    currencyField("Current", $current)
                    currencyField("Goal", $target)
                    currencyField("Monthly contribution", $monthly)
                }
                if bucket != nil {
                    Section("Add money") {
                        currencyField("Amount to add", $addAmount)
                        Button("Add to fund") {
                            current += addAmount
                            addAmount = 0
                        }
                        .disabled(addAmount <= 0)
                    }
                    Section {
                        Button("Delete fund", role: .destructive) { delete() }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(bucket == nil ? "New Fund" : "Edit Fund")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func currencyField(_ label: String, _ value: Binding<Double>) -> some View {
        LabeledContent(label) {
            TextField(label, value: value, format: .currency(code: "USD"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
    }

    private func save() {
        if let bucket {
            bucket.name = name
            bucket.kind = kind
            bucket.targetAmount = target
            bucket.currentAmount = current
            bucket.monthlyContribution = monthly
        } else {
            context.insert(Bucket(name: name, kind: kind, targetAmount: target,
                                  currentAmount: current, monthlyContribution: monthly, sortIndex: 99))
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        if let bucket {
            context.delete(bucket)
            try? context.save()
        }
        dismiss()
    }
}

#Preview {
    BucketsView()
        .modelContainer(for: [AppSettings.self, Paycheck.self, Bucket.self, RentObligation.self, LedgerEntry.self, WorkDay.self], inMemory: true)
}
