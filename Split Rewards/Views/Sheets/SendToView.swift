//
//  SendToView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import SwiftUI

struct SendToView: View {
    let prefilledRecipientInput: String
    let prefilledComment: String?
    let onExitFlow: (() -> Void)?

    init(
        prefilledRecipientInput: String = "",
        prefilledComment: String? = nil,
        onExitFlow: (() -> Void)? = nil
    ) {
        self.prefilledRecipientInput = prefilledRecipientInput
        self.prefilledComment = prefilledComment
        self.onExitFlow = onExitFlow
    }

    var body: some View {
        SendPaymentFlowView(
            startMode: .entry(prefilledRecipientInput: prefilledRecipientInput),
            prefilledLnurlComment: prefilledComment,
            onExitFlow: onExitFlow
        )
    }
}
