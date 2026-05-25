//
//  RemoveWalletConfirmView.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//

import SwiftUI
import LocalAuthentication

struct RemoveWalletConfirmView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    let blue = Color.splitBrandBlue

    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            Text("Remove Wallet From This Device")
                .font(.title2)
                .fontWeight(.heavy)
                .foregroundColor(blue)

            VStack(alignment: .leading, spacing: 10) {
                Text("Your wallet is your Split account.")
                Text("This device will no longer be able to access it.")
                Text("You can only restore it using your recovery phrase.")
                Text("Split cannot recover wallets or funds for you.")
            }
            .font(.body)
            .foregroundColor(.primary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            Spacer()

            Button {
                Task { await confirmWithBiometricsAndRemove() }
            } label: {
                HStack {
                    if isWorking {
                        ProgressView()
                            .padding(.trailing, 6)
                    }
                    Text("Continue")
                        .fontWeight(.heavy)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            Button("Cancel") {
                dismiss()
            }
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 8)
        }
        .padding()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func confirmWithBiometricsAndRemove() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            errorMessage = "Biometric authentication is not available on this device."
            return
        }

        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirm wallet removal"
            )

            guard ok else { return }

            await MessagingDeviceTokenManager.shared.unregisterDeviceTokenIfPossible(
                authManager: authManager,
                walletManager: walletManager
            )

            // ✅ Core state change
            await walletManager.removeWalletFromThisDevice()
            authManager.clearSessionCookies()
            authManager.resetLocalSession()

            // ✅ Only dismiss THIS modal
            // MainTemplateView will reset navigation automatically
            dismiss()

        } catch {
            errorMessage = "Could not confirm with Face ID / Touch ID."
        }
    }
}
