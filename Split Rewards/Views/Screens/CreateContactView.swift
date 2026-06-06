//
//  CreateContactView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import SwiftUI

struct CreateContactView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager

    let isPaymentIdentifierEditable: Bool
    let prefilledName: String
    var onSaved: (() -> Void)? = nil

    @State private var name: String
    @State private var paymentIdentifierValue: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let background = Color.black
    private let fieldSurface = Color.splitInputSurface

    init(
        paymentIdentifier: String,
        isPaymentIdentifierEditable: Bool = false,
        prefilledName: String = "",
        onSaved: (() -> Void)? = nil
    ) {
        self.isPaymentIdentifierEditable = isPaymentIdentifierEditable
        self.prefilledName = prefilledName
        self.onSaved = onSaved
        _name = State(initialValue: prefilledName)
        _paymentIdentifierValue = State(initialValue: paymentIdentifier)
    }

    private var trimmedPaymentIdentifier: String {
        paymentIdentifierValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !trimmedPaymentIdentifier.isEmpty
            && !isSaving
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                Text("Add Contact")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Name")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.72))

                    TextField("Enter contact name", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(fieldSurface)
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Lightning Address")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white.opacity(0.72))

                    if isPaymentIdentifierEditable {
                        TextField("name@domain.com", text: $paymentIdentifierValue)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.emailAddress)
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(fieldSurface)
                            )
                    } else {
                        Text(paymentIdentifierValue)
                            .font(.body.weight(.medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(fieldSurface)
                            )
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }

                VStack(spacing: 12) {
                    Button(action: {
                        Task { await saveContact() }
                    }) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save Contact")
                                    .font(.headline.weight(.semibold))
                            }
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 15)
                        .background(
                            Capsule()
                                .fill(canSave ? Color.splitBrandPink : Color.splitBrandPink.opacity(0.35))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)

                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.headline.weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    @MainActor
    private func saveContact() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPaymentIdentifier.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        do {
            _ = try await walletManager.addContact(
                name: trimmedName,
                paymentIdentifier: trimmedPaymentIdentifier
            )
            onSaved?()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }
}

#Preview {
    NavigationStack {
        CreateContactView(paymentIdentifier: "alice@\(AppConfig.lightningAddressDomain)")
            .environmentObject(WalletManager())
    }
}
