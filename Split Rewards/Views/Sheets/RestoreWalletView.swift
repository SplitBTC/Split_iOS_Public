//
//  RestoreWalletView.swift
//  Split Rewards
//
//  Created by TeeVee on 12/17/25.
//
import SwiftUI

struct RestoreWalletView: View {
    @EnvironmentObject var walletManager: WalletManager
    @EnvironmentObject var authManager: AuthManager
    @Binding var isPresented: Bool

    let pink: Color

    @State private var restoreWordCount: Int = 12
    @State private var phraseText: String = ""
    @State private var isRestoring: Bool = false

    @FocusState private var phraseFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {

                Text("Restore Wallet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("Paste or type your recovery phrase. Use a single space between each word.")
                    .font(.footnote)
                    .foregroundColor(.gray)

                Picker("", selection: $restoreWordCount) {
                    Text("12 words").tag(12)
                    Text("24 words").tag(24)
                }
                .pickerStyle(.segmented)
                .onChange(of: restoreWordCount) { _, _ in
                    // Keep what they typed; validation will update immediately.
                    // Optional: if switching to 12, you could trim extras.
                }

                HStack(spacing: 8) {
                    Text("\(words.count)/\(restoreWordCount) words")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    Spacer()

                    if !validationMessage.isEmpty {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                // Single, stable input (no grid, no per-word focus, no scrollTo hacks).
                TextEditor(text: $phraseText)
                    .focused($phraseFocused)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .keyboardType(.asciiCapable)
                    .foregroundColor(.white)
                    .padding(12)
                    .frame(minHeight: 140)
                    .background(Color.splitInputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(editorBorderColor, lineWidth: 1.5)
                    )
                    .scrollContentBackground(.hidden)
                    .onChange(of: phraseText) { _, newValue in
                        // Keep it feeling “clean” as they paste/type.
                        // Don’t aggressively rewrite while they’re typing; just normalize newlines/tabs.
                        let softened = newValue
                            .replacingOccurrences(of: "\t", with: " ")
                            .replacingOccurrences(of: "\n", with: " ")
                        if softened != newValue {
                            phraseText = softened
                        }

                        if walletManager.lastErrorMessage != nil {
                            walletManager.lastErrorMessage = nil
                        }
                    }

                if let errorMessage = walletManager.lastErrorMessage,
                   !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ErrorBox(message: errorMessage)
                    }

                Spacer()

                Button {
                    let seed = normalizedWords.prefix(restoreWordCount).joined(separator: " ")
                    guard !seed.isEmpty else { return }

                    Task {
                        isRestoring = true
                        defer { isRestoring = false }

                        await walletManager.restoreWallet(fromMnemonic: seed, authManager: authManager)

                        if case .ready = walletManager.state {
                            isPresented = false
                            try? await authManager.ensureSession(walletManager: walletManager)
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isRestoring { ProgressView().tint(.white) }
                        Text("Restore")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pink)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(!isPhraseValid || isRestoring)
                .opacity((isPhraseValid && !isRestoring) ? 1.0 : 0.45)
            }
            .padding()
            .background(Color.black.opacity(0.95).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .foregroundColor(.white)
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { phraseFocused = false }
                }
            }
            .onAppear {
                // Focus immediately so the user can paste without extra taps.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    phraseFocused = true
                }
            }
        }
    }

    // MARK: - Parsing + Validation

    private var normalizedWords: [String] {
        phraseText
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })
            .map { normalizeSeedWord(String($0)) }
            .filter { !$0.isEmpty }
    }

    private var words: [String] { normalizedWords }

    private var isPhraseValid: Bool {
        guard words.count == restoreWordCount else { return false }
        return words.allSatisfy(isSeedTokenReasonable)
    }

    private var validationMessage: String {
        if words.isEmpty { return "" }
        if words.count < restoreWordCount { return "Incomplete" }
        if words.count > restoreWordCount { return "Too many words" }
        if words.contains(where: { !isSeedTokenReasonable($0) }) { return "Check spelling" }
        return ""
    }

    private var editorBorderColor: Color {
        if words.isEmpty { return Color.clear }
        if isPhraseValid { return Color.clear }
        return Color.red.opacity(0.9)
    }

    private func normalizeSeedWord(_ s: String) -> String {
        let trimmed = s
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:\"'()[]{}"))
    }

    private func isSeedTokenReasonable(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        return word.allSatisfy { ch in (ch >= "a" && ch <= "z") }
    }
}
