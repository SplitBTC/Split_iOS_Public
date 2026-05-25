//
//  SeedPhraseView.swift
//  Split Rewards
//
//  Created by TeeVee on 12/2/25.
//

import SwiftUI

struct SeedPhraseBackupView: View {
    /// Seed phrase split into individual words in order.
    let words: [String]

    /// Called when the user confirms they’ve written the phrase down.
    let onConfirm: () -> Void

    /// Optional cancel handler (if presented modally and you want a custom behavior).
    /// If you don’t care, you can pass nil and it will just dismiss.
    let onCancel: (() -> Void)?

    let title: String
    let subtitle: String
    let warningText: String
    let acknowledgementText: String
    let confirmTitle: String
    let discardTitle: String
    let discardMessage: String

    init(
        words: [String],
        onConfirm: @escaping () -> Void,
        onCancel: (() -> Void)? = nil,
        title: String = "Your Recovery Phrase",
        subtitle: String = "These 12 words are the backup for your wallet and Split account.",
        warningText: String = "This is the only time Split will show you this recovery phrase. Save it now before continuing.",
        acknowledgementText: String = "I understand Split will not show this recovery phrase again.",
        confirmTitle: String = "I saved my recovery phrase",
        discardTitle: String = "Discard this wallet?",
        discardMessage: String = "This recovery phrase has not been saved yet. If you cancel, this wallet setup will be discarded and you will need to create a new wallet."
    ) {
        self.words = words
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.title = title
        self.subtitle = subtitle
        self.warningText = warningText
        self.acknowledgementText = acknowledgementText
        self.confirmTitle = confirmTitle
        self.discardTitle = discardTitle
        self.discardMessage = discardMessage
    }

    @Environment(\.dismiss) private var dismiss

    @State private var hasAcknowledgedOneTimeDisplay = false
    @State private var showDiscardConfirmation = false
    @State private var showCopyConfirmation = false
    @State private var didCopyRecoveryPhrase = false

    private let blue = Color.splitBrandBlue
    private let pink = Color.splitBrandPink
    private var recoveryPhrase: String {
        words.joined(separator: " ")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.opacity(0.95)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(title)
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)

                                Text(subtitle)
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }

                            Text(warningText)
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.white)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.splitBrandPink.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.splitBrandPink.opacity(0.40), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                                spacing: 8
                            ) {
                                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                                    HStack(spacing: 8) {
                                        Text("\(index + 1).")
                                            .font(.footnote)
                                            .foregroundColor(.gray)

                                        Text(word)
                                            .font(.body)
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)

                                        Spacer()
                                    }
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 12)
                                    .background(Color.splitInputSurface)
                                    .cornerRadius(10)
                                }
                            }
                            .padding(4)

                            Button {
                                showCopyConfirmation = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: didCopyRecoveryPhrase ? "checkmark.circle.fill" : "doc.on.doc.fill")
                                        .font(.headline)

                                    Text(didCopyRecoveryPhrase ? "Copied" : "Copy recovery phrase")
                                        .font(.headline.weight(.semibold))

                                    Spacer()
                                }
                                .foregroundColor(.white)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy recovery phrase")

                            VStack(alignment: .leading, spacing: 10) {
                                Text("Anyone with these words can access your wallet funds.")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.yellow)

                                Text("Split cannot recover this phrase for you, and the app will not show it again after setup.")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.74))

                                Text("Do not share it with anyone. Do not store it in screenshots, email, cloud notes, or messages. If copying, paste it only into a trusted password manager.")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.74))
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.splitInputSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                hasAcknowledgedOneTimeDisplay.toggle()
                            } label: {
                                HStack(alignment: .center, spacing: 10) {
                                    Image(systemName: hasAcknowledgedOneTimeDisplay ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(hasAcknowledgedOneTimeDisplay ? pink : .white.opacity(0.70))

                                    Text(acknowledgementText)
                                        .font(.footnote.weight(.semibold))
                                        .foregroundColor(.white.opacity(0.88))
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(acknowledgementText)
                            .accessibilityAddTraits(hasAcknowledgedOneTimeDisplay ? [.isButton, .isSelected] : .isButton)
                        }
                    }

                    Button {
                        guard hasAcknowledgedOneTimeDisplay else { return }
                        onConfirm()
                        dismiss()
                    } label: {
                        Text(confirmTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        blue.opacity(hasAcknowledgedOneTimeDisplay ? 1 : 0.38),
                                        pink.opacity(hasAcknowledgedOneTimeDisplay ? 1 : 0.38)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .foregroundColor(.white.opacity(hasAcknowledgedOneTimeDisplay ? 1 : 0.58))
                            .cornerRadius(12)
                    }
                    .disabled(!hasAcknowledgedOneTimeDisplay)

                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDiscardConfirmation = true
                    }
                    .foregroundColor(.white)
                }
            }
            .alert(discardTitle, isPresented: $showDiscardConfirmation) {
                Button("Keep Viewing", role: .cancel) { }
                Button("Discard Wallet", role: .destructive) {
                    if let onCancel {
                        onCancel()
                    }
                    dismiss()
                }
            } message: {
                Text(discardMessage)
            }
            .alert("Copy recovery phrase?", isPresented: $showCopyConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Copy") {
                    copyRecoveryPhrase()
                }
            } message: {
                Text("Only paste this into a trusted password manager. Your clipboard may be visible to other apps or synced to nearby Apple devices. Split will try to clear it after 60 seconds.")
            }
        }
        .interactiveDismissDisabled(true)
    }

    private func copyRecoveryPhrase() {
        UIPasteboard.general.string = recoveryPhrase
        didCopyRecoveryPhrase = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)

            if UIPasteboard.general.string == recoveryPhrase {
                UIPasteboard.general.string = ""
            }

            didCopyRecoveryPhrase = false
        }
    }
}

// MARK: - Preview

struct SeedPhraseBackupView_Previews: PreviewProvider {
    static var previews: some View {
        SeedPhraseBackupView(
            words: [
                "satoshi", "light", "coffee", "market",
                "rocket", "shadow", "signal", "river",
                "orbit", "tiger", "neon", "window"
            ],
            onConfirm: { },
            onCancel: nil
        )
    }
}
