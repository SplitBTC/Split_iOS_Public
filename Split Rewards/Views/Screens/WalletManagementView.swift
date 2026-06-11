//
//  WalletManagementView.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//

import Foundation
import LocalAuthentication
import SwiftUI

struct WalletManagementView: View {
    @EnvironmentObject private var walletManager: WalletManager

    @State private var isAuthenticating = false
    @State private var revealErrorMessage: String?
    @State private var revealedSeedWords: [String] = []
    @State private var isShowingRecoveryPhrase = false

    private let background = Color.splitAppBlack
    private let surface = Color.splitInputSurfaceTertiary
    private let secondarySurface = Color.splitInputSurface
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                accountSummary
                recoverySection
                dangerSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("Account Management")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isShowingRecoveryPhrase, onDismiss: clearRevealedSeed) {
            RecoveryPhraseReviewView(words: revealedSeedWords) {
                isShowingRecoveryPhrase = false
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        Circle()
                            .fill(pink)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Your Split Account")
                        .font(.title2.weight(.heavy))
                        .foregroundColor(.white)

                    Text("Wallet-backed identity")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.62))
                }
            }

            Text("Your wallet is your Split account. Keep your recovery phrase saved somewhere private and durable. Split cannot recover your account, wallet, or funds if your device is lost and you do not have that phrase.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accountSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Account Security")

            VStack(spacing: 1) {
                managementRow(
                    icon: "lock.shield.fill",
                    iconColor: blue,
                    title: "Self-custodial wallet",
                    subtitle: "The recovery phrase controls access to this Split account."
                )

                managementRow(
                    icon: "icloud.slash.fill",
                    iconColor: pink,
                    title: "No server recovery",
                    subtitle: "Split does not store your recovery phrase or private keys."
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Recovery Phrase")

            VStack(alignment: .leading, spacing: 14) {
                Text("Use this only when you need to back up or restore your wallet. Never share these words with anyone, including Split support.")
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task { await authenticateAndRevealSeed() }
                } label: {
                    HStack(spacing: 12) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                                .font(.system(size: 20, weight: .semibold))
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(isAuthenticating ? "Checking Identity" : "Reveal Recovery Phrase")
                                .font(.headline.weight(.bold))

                            Text("Requires Face ID or Touch ID")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.white.opacity(0.62))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundColor(.white.opacity(0.52))
                    }
                    .foregroundColor(.white)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(pink)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isAuthenticating)

                if let revealErrorMessage {
                    Text(revealErrorMessage)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(Color(red: 1, green: 0.74, blue: 0.84))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Device Access")

            VStack(spacing: 12) {
                NavigationLink {
                    RemoveWalletConfirmView()
                } label: {
                    dangerRow(
                        icon: "trash.fill",
                        title: "Remove Wallet From This Device",
                        subtitle: "You will need your recovery phrase to restore access."
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    DeleteRewardsAccountConfirmView()
                } label: {
                    dangerRow(
                        icon: "person.crop.circle.badge.xmark.fill",
                        title: "Delete Rewards Account",
                        subtitle: "This will delete your rewards account. This data cannot be restored."
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.heavy))
            .foregroundColor(.white.opacity(0.52))
            .textCase(.uppercase)
    }

    private func managementRow(
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(iconColor.opacity(0.88))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
    }

    private func dangerRow(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.82))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundColor(.white.opacity(0.48))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(secondarySurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.22), lineWidth: 1)
        )
    }

    private func authenticateAndRevealSeed() async {
        revealErrorMessage = nil
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        var authError: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) else {
            revealErrorMessage = "Face ID or Touch ID is required to reveal your recovery phrase."
            return
        }

        do {
            let didAuthenticate = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Reveal your Split recovery phrase"
            )

            guard didAuthenticate else { return }

            guard let seed = walletManager.readLocalSeed() else {
                revealErrorMessage = "No recovery phrase is saved on this device."
                return
            }

            let words = seed
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)

            guard words.count >= 12 else {
                revealErrorMessage = "The saved recovery phrase on this device could not be read."
                return
            }

            revealedSeedWords = words
            isShowingRecoveryPhrase = true
        } catch {
            revealErrorMessage = "Could not confirm with Face ID or Touch ID."
        }
    }

    private func clearRevealedSeed() {
        revealedSeedWords = []
    }
}

private struct RecoveryPhraseReviewView: View {
    let words: [String]
    let onClose: () -> Void

    @Environment(\.scenePhase) private var scenePhase

    private let background = Color.splitAppBlack
    private let surface = Color.splitInputSurface
    private let pink = Color.splitBrandPink

    var body: some View {
        NavigationStack {
            ZStack {
                background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recovery Phrase")
                                .font(.title2.weight(.heavy))
                                .foregroundColor(.white)

                            Text("Write these words down exactly, in order. Anyone with this phrase can access your wallet and Split account.")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.70))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Text("Screenshots and screen recordings are blocked on this screen. Store the phrase somewhere private and offline, or in a trusted password manager.")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(pink.opacity(0.18))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(pink.opacity(0.42), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                        ScreenshotProtectedView {
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                                spacing: 8
                            ) {
                                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                    HStack(spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.footnote.weight(.semibold))
                                            .foregroundColor(.white.opacity(0.48))

                                        Text(word)
                                            .font(.body.weight(.semibold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 12)
                                    .background(surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                            }
                            .padding(4)
                        }
                        .frame(minHeight: CGFloat(max(words.count / 2, 1)) * 48 + 12)
                    }
                    .padding(18)
                    .padding(.bottom, 30)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onClose()
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                onClose()
            }
        }
    }
}

private struct DeleteRewardsAccountConfirmView: View {
    @EnvironmentObject private var walletManager: WalletManager
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var errorMessage: String?

    private let pink = Color.splitBrandPink

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete Rewards Account")
                .font(.title2.weight(.heavy))
                .foregroundColor(pink)

            VStack(alignment: .leading, spacing: 10) {
                Text("This will delete your rewards account.")
                Text("This data cannot be restored.")
                Text("Your wallet and recovery phrase will also be removed from this device.")
                Text("Your bitcoin wallet still exists on-chain and can only be restored with your recovery phrase.")
            }
            .font(.body)
            .foregroundColor(.primary)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.red)
            }

            Spacer()

            Button {
                Task { await confirmWithBiometricsAndDelete() }
            } label: {
                HStack {
                    if isWorking {
                        ProgressView()
                            .padding(.trailing, 6)
                    }

                    Text("Delete Rewards Account")
                        .fontWeight(.heavy)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
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

    private func confirmWithBiometricsAndDelete() async {
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
                localizedReason: "Confirm rewards account deletion"
            )

            guard ok else { return }

            try await RewardsAccountDeletionAPI.deleteRewardsAccount(
                authManager: authManager,
                walletManager: walletManager
            )

            await walletManager.removeWalletFromThisDevice()
            authManager.clearSessionCookies()
            authManager.resetLocalSession()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription.isEmpty
                ? "Could not delete your rewards account."
                : error.localizedDescription
        }
    }
}

private enum RewardsAccountDeletionAPI {
    private struct DeleteNonceResponse: Decodable {
        let nonce: String
        let expiresAt: String?
        let messageToSign: String
        let purpose: String?
    }

    private struct SignedDeleteRequest: Encodable {
        let walletPubkey: String
        let nonce: String
        let signature: String
    }

    @MainActor
    static func deleteRewardsAccount(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws {
        try await authManager.ensureSession(walletManager: walletManager)

        let nonceResponse = try await fetchDeleteNonce(
            authManager: authManager,
            walletManager: walletManager
        )
        let signed = try await walletManager.signAuthMessage(nonceResponse.messageToSign)

        try await submitSignedDelete(
            walletPubkey: signed.pubkey,
            nonce: nonceResponse.nonce,
            signature: signed.signature
        )
    }

    @MainActor
    private static func fetchDeleteNonce(
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> DeleteNonceResponse {
        var (data, response) = try await sendDeleteNonceRequest()

        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {
            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)
            (data, response) = try await sendDeleteNonceRequest()
        }

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            throw serverError(data: data, statusCode: http.statusCode, fallback: "Account deletion nonce failed")
        }

        guard let decoded = try? JSONDecoder().decode(DeleteNonceResponse.self, from: data) else {
            throw URLError(.badServerResponse)
        }

        return decoded
    }

    private static func sendDeleteNonceRequest() async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(AppConfig.baseURL)/v2/account/delete/nonce") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data("{}".utf8)

        return try await URLSession.shared.data(for: request)
    }

    private static func submitSignedDelete(
        walletPubkey: String,
        nonce: String,
        signature: String
    ) async throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/v2/account/delete") else {
            throw URLError(.badURL)
        }

        let body = SignedDeleteRequest(
            walletPubkey: walletPubkey,
            nonce: nonce,
            signature: signature
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(http.statusCode) else {
            throw serverError(data: data, statusCode: http.statusCode, fallback: "Account deletion failed")
        }
    }

    private static func serverError(data: Data, statusCode: Int, fallback: String) -> Error {
        let raw = String(data: data, encoding: .utf8) ?? ""
        return NSError(
            domain: "RewardsAccountDeletionAPI",
            code: statusCode,
            userInfo: [
                NSLocalizedDescriptionKey: raw.isEmpty
                    ? "\(fallback) (HTTP \(statusCode))"
                    : "\(fallback) (HTTP \(statusCode)): \(raw)"
            ]
        )
    }
}
