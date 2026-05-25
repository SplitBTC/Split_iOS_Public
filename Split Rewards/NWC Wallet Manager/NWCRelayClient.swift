//
//  NWCRelayClient.swift
//  Split Rewards
//
//  Created by TeeVee on 5/1/26.
//

import Foundation

final class NWCRelayClient {
    private let relayURL: URL
    private let timeoutNanoseconds: UInt64
    private let decoder = JSONDecoder()

    init(relayURL: URL, timeoutNanoseconds: UInt64 = 12_000_000_000) {
        self.relayURL = relayURL
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func fetchWalletInfo(walletPubkey: String) async throws -> NWCWalletInfoEvent {
        let session = try await makeSession()
        let socket = session.webSocketTask(with: relayURL)
        let subscriptionId = "split-nwc-info-\(UUID().uuidString)"

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

        let filter: [String: Any] = [
            "kinds": [13194],
            "authors": [walletPubkey],
            "limit": 1,
        ]
        let request: [Any] = ["REQ", subscriptionId, filter]
        let requestData = try JSONSerialization.data(withJSONObject: request)
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            throw NWCWalletError.invalidRelayResponse
        }

        try await socket.send(.string(requestString))

        return try await withThrowingTaskGroup(of: NWCWalletInfoEvent.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    if let event = try self.infoEvent(from: message, subscriptionId: subscriptionId) {
                        return event
                    }
                }

                throw CancellationError()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: self.timeoutNanoseconds)
                throw NWCWalletError.relayTimedOut
            }

            guard let event = try await group.next() else {
                throw NWCWalletError.walletInfoUnavailable
            }

            group.cancelAll()
            return event
        }
    }

    private func infoEvent(
        from message: URLSessionWebSocketTask.Message,
        subscriptionId: String
    ) throws -> NWCWalletInfoEvent? {
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

        switch type {
        case "EVENT":
            guard raw.count >= 3,
                  (raw[1] as? String) == subscriptionId,
                  JSONSerialization.isValidJSONObject(raw[2]) else {
                throw NWCWalletError.invalidRelayResponse
            }

            let eventData = try JSONSerialization.data(withJSONObject: raw[2])
            let event = try decoder.decode(NWCWalletInfoEvent.self, from: eventData)
            guard event.kind == 13194 else { return nil }
            guard let nostrEvent = event.nostrEvent,
                  try NWCNostrCryptography.verifyEvent(nostrEvent) else {
                throw NWCWalletError.invalidRelayResponse
            }
            return event

        case "EOSE", "NOTICE", "OK", "CLOSED":
            return nil

        default:
            return nil
        }
    }

    private func makeSession() async throws -> URLSession {
        let configuration = try await RemoteNodeURLSessionFactory.configuration(
            transport: .preferred(forURL: relayURL),
            requestTimeout: 20,
            resourceTimeout: 45,
            waitsForConnectivity: RemoteNodeTransport.preferred(forURL: relayURL) == .tor
        )
        return URLSession(configuration: configuration)
    }
}
