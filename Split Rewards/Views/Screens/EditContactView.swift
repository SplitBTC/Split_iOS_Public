//
//  EditContactView.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import SwiftUI

struct EditContactView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var walletManager: WalletManager

    let contact: WalletManager.WalletContact
    var onUpdated: ((WalletManager.WalletContact) -> Void)? = nil
    var onDeleted: (() -> Void)? = nil

    @State private var name: String
    @State private var isSaving = false
    @State private var isDeleting = false
    @State private var errorMessage: String?
    @State private var showDeleteConfirmation = false

    private let background = Color.black
    private let fieldSurface = Color.splitInputSurface

    init(
        contact: WalletManager.WalletContact,
        onUpdated: ((WalletManager.WalletContact) -> Void)? = nil,
        onDeleted: (() -> Void)? = nil
    ) {
        self.contact = contact
        self.onUpdated = onUpdated
        self.onDeleted = onDeleted
        _name = State(initialValue: contact.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        trimmedName != contact.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && hasChanges && !isSaving && !isDeleting
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()

                    Button {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.red.opacity(0.92))
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || isDeleting)
                }

                VStack(spacing: 10) {
                    TextField("Contact name", text: $name)
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)

                    Text(contact.paymentIdentifier)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white.opacity(0.62))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

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

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }

                Spacer()

                VStack(spacing: 12) {
                    Button(action: {
                        Task { await saveChanges() }
                    }) {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Save")
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
                    .disabled(isSaving || isDeleting)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete Contact?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await deleteContact() }
            }
        } message: {
            Text("This will remove \(contact.name) from your saved contacts.")
        }
    }

    @MainActor
    private func saveChanges() async {
        guard canSave else { return }

        isSaving = true
        errorMessage = nil

        do {
            let updated = try await walletManager.updateContact(
                id: contact.id,
                name: trimmedName,
                paymentIdentifier: contact.paymentIdentifier
            )
            onUpdated?(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSaving = false
    }

    @MainActor
    private func deleteContact() async {
        guard !isDeleting else { return }

        isDeleting = true
        errorMessage = nil

        do {
            try await walletManager.deleteContact(id: contact.id)
            dismiss()
            DispatchQueue.main.async {
                onDeleted?()
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isDeleting = false
    }
}

#Preview {
    NavigationStack {
        EditContactView(
            contact: WalletManager.WalletContact(
                id: "1",
                name: "Alice",
                paymentIdentifier: "alice@example.com",
                createdAt: .now,
                updatedAt: .now
            )
        )
        .environmentObject(WalletManager())
    }
}
