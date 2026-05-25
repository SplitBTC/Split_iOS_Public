//
//  SendBTCView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import SwiftUI

struct SendBTCView: View {
    let onExitFlow: (() -> Void)?

    init(onExitFlow: (() -> Void)? = nil) {
        self.onExitFlow = onExitFlow
    }

    var body: some View {
        SendPaymentFlowView(
            startMode: .scan,
            onExitFlow: onExitFlow
        )
    }
}
