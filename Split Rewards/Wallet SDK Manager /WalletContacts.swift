//
//  WalletContacts.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import Foundation
import BreezSdkSpark

@MainActor
extension WalletManager {

    struct WalletContact: Identifiable, Equatable {
        let id: String
        let name: String
        let paymentIdentifier: String
        let createdAt: Date
        let updatedAt: Date
    }

    enum WalletContactsError: LocalizedError {
        case sdkNotInitialized
        case duplicatePaymentIdentifier

        var errorDescription: String? {
            switch self {
            case .sdkNotInitialized:
                return "Wallet not initialized."
            case .duplicatePaymentIdentifier:
                return "A contact with this Lightning Address already exists."
            }
        }
    }

    func listContacts(
        offset: UInt32? = nil,
        limit: UInt32? = nil
    ) async throws -> [WalletContact] {
        guard let sdk else {
            throw WalletContactsError.sdkNotInitialized
        }

        let contacts = try await sdk.listContacts(
            request: ListContactsRequest(offset: offset, limit: limit)
        )

        return contacts.map(Self.mapContact)
    }

    func contact(
        forPaymentIdentifier paymentIdentifier: String
    ) async throws -> WalletContact? {
        let normalized = normalizePaymentIdentifier(paymentIdentifier)
        let contacts = try await listContacts()
        return contacts.first { normalizePaymentIdentifier($0.paymentIdentifier) == normalized }
    }

    func hasContact(
        forPaymentIdentifier paymentIdentifier: String
    ) async throws -> Bool {
        try await contact(forPaymentIdentifier: paymentIdentifier) != nil
    }

    func addContact(
        name: String,
        paymentIdentifier: String
    ) async throws -> WalletContact {
        guard let sdk else {
            throw WalletContactsError.sdkNotInitialized
        }

        let normalizedPaymentIdentifier = normalizePaymentIdentifier(paymentIdentifier)
        if try await hasContact(forPaymentIdentifier: normalizedPaymentIdentifier) {
            throw WalletContactsError.duplicatePaymentIdentifier
        }

        let contact = try await sdk.addContact(
            request: AddContactRequest(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                paymentIdentifier: normalizedPaymentIdentifier
            )
        )

        return Self.mapContact(contact)
    }

    func updateContact(
        id: String,
        name: String,
        paymentIdentifier: String
    ) async throws -> WalletContact {
        guard let sdk else {
            throw WalletContactsError.sdkNotInitialized
        }

        let normalizedPaymentIdentifier = normalizePaymentIdentifier(paymentIdentifier)
        let contacts = try await listContacts()
        if contacts.contains(where: {
            normalizePaymentIdentifier($0.paymentIdentifier) == normalizedPaymentIdentifier && $0.id != id
        }) {
            throw WalletContactsError.duplicatePaymentIdentifier
        }

        let contact = try await sdk.updateContact(
            request: UpdateContactRequest(
                id: id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                paymentIdentifier: normalizedPaymentIdentifier
            )
        )

        return Self.mapContact(contact)
    }

    func deleteContact(id: String) async throws {
        guard let sdk else {
            throw WalletContactsError.sdkNotInitialized
        }

        try await sdk.deleteContact(id: id)
    }

    private static func mapContact(_ contact: Contact) -> WalletContact {
        WalletContact(
            id: contact.id,
            name: contact.name,
            paymentIdentifier: contact.paymentIdentifier,
            createdAt: Date(timeIntervalSince1970: TimeInterval(contact.createdAt)),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(contact.updatedAt))
        )
    }

    private func normalizePaymentIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
