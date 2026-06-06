//
//  BudgetTheme.swift
//  BudgetTheWorld
//
//  Shared design system: colors + reusable building blocks (Card, RingGauge).
//  Centralizing the UIKit color bridge here keeps the rest of the views clean.
//

import SwiftUI
import UIKit

// MARK: - Palette

extension Color {
    static let btwBackground = Color(.systemGroupedBackground)
    static let btwCard = Color(.secondarySystemGroupedBackground)
}

// MARK: - Card

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let content: Content

    init(title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.btwCard, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Ring gauge (the "Safe-to-Spend" hero)

struct RingGauge<Center: View>: View {
    let progress: Double      // 0...1
    let tint: Color
    let lineWidth: CGFloat
    let center: Center

    init(progress: Double, tint: Color, lineWidth: CGFloat = 16, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.tint = tint
        self.lineWidth = lineWidth
        self.center = center()
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)
            center
        }
    }
}

// MARK: - Keyboard dismissal

extension View {
    /// Adds a "Done" bar above the keyboard so number pads (which have no return key) can be dismissed.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

// MARK: - Bucket colors

extension BucketKind {
    var color: Color {
        switch self {
        case .rentReserve: .orange
        case .emergency: .red
        case .medSchool: .blue
        case .apartment: .teal
        case .lifestyle: .pink
        case .custom: .purple
        }
    }
}

extension SpendCategory {
    var color: Color {
        switch self {
        case .rent: .orange
        case .utilities: .yellow
        case .groceries: .green
        case .food: .red
        case .transportation: .blue
        case .fun: .pink
        case .furniture: .teal
        case .clothing: .pink
        case .subscriptions: .indigo
        case .tech: .gray
        case .travel: .teal
        case .household: .brown
        case .healthcare: .red
        case .personalCare: .mint
        case .insurance: .blue
        case .gifts: .purple
        case .education: .orange
        case .fees: .gray
        case .pets: .brown
        case .savings: .mint
        case .income: .green
        case .other: .gray
        }
    }
}
