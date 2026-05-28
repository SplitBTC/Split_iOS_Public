//
//  SparkSubwalletSetupView.swift
//  Split Rewards
//
//  Created by TeeVee on 5/12/26.
//

import SwiftUI

struct SparkSubwalletSetupView: View {
    @EnvironmentObject private var sparkSubwalletManager: SparkSubwalletManager
    @EnvironmentObject private var activeSpendWalletStore: ActiveSpendWalletStore
    @Environment(\.dismiss) private var dismiss

    let onWalletAdded: () -> Void

    private enum Mode {
        case overview
        case create
        case restore
    }

    @State private var mode: Mode = .overview
    @State private var walletName = ""
    @State private var restoreWords = Array(repeating: "", count: 12)
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showSeedPhrase = false
    @FocusState private var focusedRestoreWordIndex: Int?

    private let background = Color.splitSoftBackground
    private let cardSurface = Color.splitInputSurfaceTertiary
    private let cardStroke = Color.white.opacity(0.06)
    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    switch mode {
                    case .overview:
                        overviewContent
                    case .create:
                        createContent
                    case .restore:
                        restoreContent
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(pink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }

            if isWorking {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .tint(.white)
                    }
            }
        }
        .navigationTitle("Spark Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showSeedPhrase, onDismiss: {
            if sparkSubwalletManager.pendingSeedWords.isEmpty {
                mode = .overview
            }
        }) {
            SeedPhraseBackupView(
                words: sparkSubwalletManager.pendingSeedWords,
                onConfirm: confirmCreateWallet,
                onCancel: {
                    sparkSubwalletManager.cancelPendingWalletSeed()
                },
                title: "Subwallet Recovery Phrase",
                subtitle: "These 12 words back up this Spark subwallet only. Your root Split wallet is separate.",
                warningText: "This is the only time Split will show this subwallet recovery phrase. Save it before continuing.",
                acknowledgementText: "I understand this subwallet needs this recovery phrase to restore funds.",
                confirmTitle: "I saved this phrase",
                discardTitle: "Discard this subwallet?",
                discardMessage: "This subwallet has not been saved yet. If you cancel, this recovery phrase and setup will be discarded."
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(headerTitle)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(.white)

            Text(headerSubtitle)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white.opacity(0.60))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerTitle: String {
        switch mode {
        case .overview:
            return "Spark Wallet"
        case .create:
            return "Name Wallet"
        case .restore:
            return "Restore Wallet"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .overview:
            return "Add a Spark wallet as a subwallet under this Split account."
        case .create:
            return "Choose a name before Split creates a new Spark subwallet."
        case .restore:
            return "Enter a name and the 12-word recovery phrase for the Spark wallet."
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoCard

            primaryButton(title: "Create New Spark Wallet", systemName: "plus.circle.fill") {
                mode = .create
                errorMessage = nil
            }

            secondaryButton(title: "Restore Existing Spark Wallet", systemName: "arrow.clockwise.circle.fill") {
                mode = .restore
                errorMessage = nil
            }
        }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your original Spark wallet remains the root wallet for this Split account.")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Text("You can add an existing Spark wallet or create a new one. A Spark wallet created as a subwallet can later become a root wallet if it is used through restore during app startup, this would link the wallet with a new user account.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.72))

            Text("Spark wallets associated with one root account can also be added as subwallets under another root account. Most Split account data is stored on this device, so recovery phrase storage and deletion matter.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.72))
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(cardStroke, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var createContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            nameField

            primaryButton(title: "Continue", systemName: "arrow.right.circle.fill") {
                startCreateFlow()
            }
            .disabled(!canSubmitName || isWorking)
            .opacity(canSubmitName ? 1 : 0.55)
        }
    }

    private var restoreContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            nameField
            seedGrid

            primaryButton(title: "Restore Spark Wallet", systemName: "checkmark.circle.fill") {
                restoreWallet()
            }
            .disabled(!canSubmitName || !canRestore || isWorking)
            .opacity(canSubmitName && canRestore ? 1 : 0.55)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallet Name")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white.opacity(0.62))

            TextField("Required", text: $walletName)
                .textInputAutocapitalization(.words)
                .foregroundColor(.white)
                .font(.headline.weight(.semibold))
                .padding(14)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var seedGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
            ForEach(restoreWords.indices, id: \.self) { index in
                HStack(spacing: 8) {
                    Text("\(index + 1).")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.50))

                    TextField("", text: $restoreWords[index])
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.white)
                        .focused($focusedRestoreWordIndex, equals: index)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedRestoreWordIndex = index
                }
            }
        }
    }

    private var canSubmitName: Bool {
        walletName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank != nil
    }

    private var canRestore: Bool {
        restoreWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count == 12
    }

    private func primaryButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Image(systemName: systemName)
                    .font(.title3.weight(.bold))

                Spacer()
            }
            .foregroundColor(.black)
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(title: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline.weight(.semibold))

                Image(systemName: systemName)
                    .font(.title3.weight(.bold))
                    .foregroundColor(blue)

                Spacer()
            }
            .foregroundColor(.white)
            .padding(16)
            .background(cardSurface)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(cardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func startCreateFlow() {
        guard canSubmitName else { return }
        errorMessage = nil

        do {
            try sparkSubwalletManager.createPendingWalletSeed()
            showSeedPhrase = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func confirmCreateWallet() {
        guard canSubmitName else { return }

        isWorking = true
        errorMessage = nil

        Task {
            do {
                _ = try await sparkSubwalletManager.createWallet(label: walletName)
                await MainActor.run {
                    activeSpendWalletStore.reconcileWithStoredWallets()
                    isWorking = false
                    onWalletAdded()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func restoreWallet() {
        guard canSubmitName, canRestore else { return }

        isWorking = true
        errorMessage = nil

        let phrase = restoreWords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .joined(separator: " ")

        Task {
            do {
                _ = try await sparkSubwalletManager.restoreWallet(seedPhrase: phrase, label: walletName)
                await MainActor.run {
                    activeSpendWalletStore.reconcileWithStoredWallets()
                    isWorking = false
                    onWalletAdded()
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
