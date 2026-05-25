//
//  RemoteNodeTorManager.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation
import Combine

#if canImport(SwiftTor)
import SwiftTor
#endif

@MainActor
final class RemoteNodeTorManager: ObservableObject {
    static let shared = RemoteNodeTorManager()

    enum BootstrapState: Equatable {
        case idle
        case starting
        case ready
        case failed(String)

        var isStarting: Bool {
            if case .starting = self {
                return true
            }

            return false
        }
    }

    @Published private(set) var bootstrapState: BootstrapState = .idle

    #if targetEnvironment(simulator)
    private let socksPort = 19052
    #else
    private let socksPort = 19050
    #endif

    private let socksHost = "127.0.0.1"
    private let bootstrapTimeoutNanos: UInt64 = 45_000_000_000

    #if canImport(SwiftTor)
    private var tor: SwiftTor?
    #endif

    private init() {}

    func sessionConfiguration(
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        waitsForConnectivity: Bool
    ) async throws -> URLSessionConfiguration {
        try await bootstrapIfNeeded()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.waitsForConnectivity = waitsForConnectivity
        configuration.connectionProxyDictionary = [
            kCFProxyTypeKey as String: kCFProxyTypeSOCKS,
            kCFStreamPropertySOCKSProxyHost as String: socksHost,
            kCFStreamPropertySOCKSProxyPort as String: socksPort,
        ]
        return configuration
    }

    func bootstrapIfNeeded() async throws {
        #if canImport(SwiftTor)
        let tor = tor ?? SwiftTor(start: true)
        self.tor = tor

        if tor.state.rawValue == "connected" {
            bootstrapState = .ready
            return
        }

        bootstrapState = .starting

        if tor.started == false {
            tor.start()
        }

        let startedAt = DispatchTime.now().uptimeNanoseconds
        do {
            while tor.state.rawValue != "connected" {
                try Task.checkCancellation()

                let elapsed = DispatchTime.now().uptimeNanoseconds - startedAt
                if elapsed >= bootstrapTimeoutNanos {
                    throw RemoteNodeTransportError.torBootstrapTimedOut
                }

                try await Task.sleep(nanoseconds: 300_000_000)
            }

            bootstrapState = .ready
        } catch {
            bootstrapState = .failed(error.localizedDescription)
            throw error
        }
        #else
        bootstrapState = .failed(RemoteNodeTransportError.torUnavailable.localizedDescription)
        throw RemoteNodeTransportError.torUnavailable
        #endif
    }
}

enum RemoteNodeURLSessionFactory {
    static func configuration(
        transport: RemoteNodeTransport,
        requestTimeout: TimeInterval,
        resourceTimeout: TimeInterval,
        waitsForConnectivity: Bool
    ) async throws -> URLSessionConfiguration {
        switch transport {
        case .direct:
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = requestTimeout
            configuration.timeoutIntervalForResource = resourceTimeout
            configuration.waitsForConnectivity = waitsForConnectivity
            return configuration
        case .tor:
            return try await RemoteNodeTorManager.shared.sessionConfiguration(
                requestTimeout: requestTimeout,
                resourceTimeout: resourceTimeout,
                waitsForConnectivity: waitsForConnectivity
            )
        }
    }
}
