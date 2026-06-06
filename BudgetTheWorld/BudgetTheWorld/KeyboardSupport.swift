//
//  KeyboardSupport.swift
//  BudgetTheWorld
//
//  Two keyboard quality-of-life fixes:
//   1. Tap anywhere outside a field to dismiss the keyboard (a reliable escape hatch).
//   2. Pre-warm the keyboard at launch so the first real edit isn't laggy.
//

import SwiftUI
import UIKit

final class KeyboardSupport: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardSupport()
    private var installed = false

    private func keyWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first
    }

    /// Adds a tap recognizer to the window that ends editing. `cancelsTouchesInView = false`
    /// so buttons, list rows, etc. still work normally.
    func installTapToDismiss() {
        guard !installed, let window = keyWindow() else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        installed = true
    }

    /// Briefly make a hidden text field first responder so the keyboard subsystem initializes
    /// up front instead of stalling the first time the user taps a real field.
    func prewarm() {
        guard let window = keyWindow() else { return }
        let field = UITextField(frame: .zero)
        field.keyboardType = .decimalPad
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }

    @objc private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // Let our tap coexist with SwiftUI's own gestures.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
