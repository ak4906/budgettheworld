//
//  PlaidLink.swift
//  BudgetTheWorld
//
//  Presents Plaid Link (LinkKit) to connect a bank. Requires the Plaid Link SDK:
//    Xcode → File → Add Package Dependencies → https://github.com/plaid/plaid-link-ios → add "LinkKit".
//  Until that package is added, this file (and the app) will not compile.
//

import UIKit
import LinkKit

@MainActor
final class PlaidLinkPresenter {
    static let shared = PlaidLinkPresenter()
    private var handler: Handler?   // must be retained for the duration of the Link session

    /// Opens Plaid Link with a link token. `onSuccess` returns the public token to exchange.
    func present(token: String,
                 onSuccess: @escaping (String) -> Void,
                 onExit: @escaping () -> Void) {
        var configuration = LinkTokenConfiguration(token: token) { success in
            onSuccess(success.publicToken)
        }
        configuration.onExit = { _ in onExit() }

        switch Plaid.create(configuration) {
        case .failure(let error):
            print("Plaid.create failed: \(error)")
            onExit()
        case .success(let handler):
            self.handler = handler
            guard let presenter = Self.topViewController() else { onExit(); return }
            handler.open(presentUsing: .viewController(presenter))
        }
    }

    /// Resume Link after an OAuth redirect back into the app (banks like BofA require this).
    func resume(from url: URL) {
        handler?.resumeAfterTermination(from: url)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
