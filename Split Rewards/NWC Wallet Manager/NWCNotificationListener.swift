//
//  NWCNotificationListener.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation

struct NWCNotification: Equatable {
    let type: String
    let transaction: NWCTransactionResult
    let relayURL: URL
}

final class NWCNotificationListener {
    private let decoder = JSONDecoder()

    func listen(
        wallet: NWCWalletCredentials,
        relayURL: URL,
        onNotification: @escaping @Sendable (NWCNotification) async -> Void
    ) async throws {
        let clientPubkey = try NWCNostrCryptography.publicKeyHex(privateKeyHex: wallet.secret)
        let session = try await makeSession(relayURL: relayURL)
        let socket = session.webSocketTask(with: relayURL)
        let subscriptionId = "split-nwc-notify-\(UUID().uuidString)"

        socket.resume()

        defer {
            let closePayload = try? JSONSerialization.data(withJSONObject: ["CLOSE", subscriptionId])
            if let closePayload,
               let closeMessage = String(data: closePayload, encoding: .utf8) {
                socket.send(.string(closeMessage)) { _ in }
            }
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
        }

        let notificationKinds = wallet.capabilities?.preferredEncryptionMode == .nip04
            ? [23197, 23196]
            : [23197]
        let filter: [String: Any] = [
            "kinds": notificationKinds,
            "authors": [wallet.walletPubkey],
            "#p": [clientPubkey],
            "since": Int(Date().timeIntervalSince1970) - 60,
        ]
        let request: [Any] = ["REQ", subscriptionId, filter]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }

        try await socket.send(.string(requestString))

        while !Task.isCancelled {
            let message = try await socket.receive()
            if let notification = try notification(
                from: message,
                subscriptionId: subscriptionId,
                wallet: wallet,
                clientPubkey: clientPubkey,
                relayURL: relayURL
            ) {
                await onNotification(notification)
            }
        }
    }

    private func notification(
        from message: URLSessionWebSocketTask.Message,
        subscriptionId: String,
        wallet: NWCWalletCredentials,
        clientPubkey: String,
        relayURL: URL
    ) throws -> NWCNotification? {
        let data: Data
        switch message {
        case .string(let string):
            guard let stringData = string.data(using: .utf8) else {
                throw NWCWalletError.invalidRelayResponse
            }
            data = stringData
        case .data(let messageData):
            data = messageData
        @unknown default:
            return nil
        }

        guard let raw = try JSONSerialization.jsonObject(with: data) as? [Any],
              let type = raw.first as? String else {
            throw NWCWalletError.invalidRelayResponse
        }

        guard type == "EVENT" else {
            return nil
        }

        guard raw.count >= 3,
              (raw[1] as? String) == subscriptionId,
              JSONSerialization.isValidJSONObject(raw[2]) else {
            throw NWCWalletError.invalidRelayResponse
        }

        let eventData = try JSONSerialization.data(withJSONObject: raw[2])
        let event = try decoder.decode(NWCNostrEvent.self, from: eventData)
        guard (event.kind == 23197 || event.kind == 23196),
              event.pubkey.lowercased() == wallet.walletPubkey.lowercased(),
              event.tags.contains(where: { $0.count > 1 && $0[0] == "p" && $0[1].lowercased() == clientPubkey.lowercased() }) else {
            return nil
        }

        guard try NWCNostrCryptography.verifyEvent(event) else {
            throw NWCNostrCryptographyError.invalidEvent
        }

        let plaintext: String
        switch wallet.capabilities?.preferredEncryptionMode ?? .nip04 {
        case .nip44V2:
            plaintext = try NWCNostrCryptography.nip44Decrypt(
                payload: event.content,
                recipientPrivateKeyHex: wallet.secret,
                senderPublicKeyHex: event.pubkey
            )
        case .nip04:
            plaintext = try NWCNostrCryptography.nip04Decrypt(
                payload: event.content,
                recipientPrivateKeyHex: wallet.secret,
                senderPublicKeyHex: event.pubkey
            )
        }
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }

        let envelope = try decoder.decode(NWCNotificationEnvelope.self, from: plaintextData)
        return NWCNotification(
            type: envelope.notificationType,
            transaction: envelope.notification,
            relayURL: relayURL
        )
    }

    private func makeSession(relayURL: URL) async throws -> URLSession {
        let transport = RemoteNodeTransport.preferred(forURL: relayURL)
        let configuration = try await RemoteNodeURLSessionFactory.configuration(
            transport: transport,
            requestTimeout: 20,
            resourceTimeout: 0,
            waitsForConnectivity: transport == .tor
        )
        return URLSession(configuration: configuration)
    }
}

private struct NWCNotificationEnvelope: Decodable {
    let notificationType: String
    let notification: NWCTransactionResult

    enum CodingKeys: String, CodingKey {
        case notificationType = "notification_type"
        case notification
    }
}
