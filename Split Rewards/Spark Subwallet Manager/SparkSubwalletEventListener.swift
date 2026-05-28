//
//  SparkSubwalletEventListener.swift
//  Split Rewards
//
//  Created by TeeVee on 5/12/26.
//

import BreezSdkSpark
import Foundation

final class SparkSubwalletEventListener: EventListener, @unchecked Sendable {
    private weak var manager: SparkSubwalletManager?
    private let walletId: String

    init(manager: SparkSubwalletManager, walletId: String) {
        self.manager = manager
        self.walletId = walletId
    }

    func onEvent(event: SdkEvent) async {
        Task { @MainActor [weak manager] in
            guard let manager,
                  manager.connectedWallet?.id == walletId else {
                return
            }

            await manager.handleSdkEvent(event)
        }
    }
}
