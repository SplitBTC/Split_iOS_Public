//
//  WalletEventListener.swift
//  Split Rewards
//
//  Created by TeeVee on 12/05/25.
//

import Foundation
import BreezSdkSpark

/// Thin adapter around Breez Spark's `EventListener` that forwards
/// `SdkEvent`s into an async handler closure.
///
/// This lets higher-level code (like `WalletManager`) decide what to do
/// with events without having to conform directly to `EventListener`.
final class WalletEventListener: EventListener {
    
    typealias EventHandler = @Sendable (SdkEvent) async -> Void
    
    private let handler: EventHandler
    
    init(handler: @escaping EventHandler) {
        self.handler = handler
    }
    
    func onEvent(event: SdkEvent) async {
        Task { @MainActor in
            await handler(event)
        }
    }
}


