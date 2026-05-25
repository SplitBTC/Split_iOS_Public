//
//  RemoteNodeTransport.swift
//  Split Rewards
//
//  Created by TeeVee on 5/19/26.
//

import Foundation

enum RemoteNodeTransport: String, Codable, Equatable {
    case direct
    case tor

    static func preferred(forHost host: String) -> RemoteNodeTransport {
        normalizedHost(host).hasSuffix(".onion") ? .tor : .direct
    }

    static func preferred(forURL url: URL) -> RemoteNodeTransport {
        preferred(forHost: url.host ?? "")
    }

    static func isOnionHost(_ host: String) -> Bool {
        normalizedHost(host).hasSuffix(".onion")
    }

    private static func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum RemoteNodeTransportError: LocalizedError, Equatable {
    case torUnavailable
    case torBootstrapTimedOut

    var errorDescription: String? {
        switch self {
        case .torUnavailable:
            return "This build of Split does not include Tor support."
        case .torBootstrapTimedOut:
            return "Tor did not finish connecting in time."
        }
    }
}
