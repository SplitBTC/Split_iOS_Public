//
//  MessageRecipientRecord.swift
//  Split Rewards
//
//  Created by TeeVee on 4/5/26.
//

import Foundation

struct MessageRecipientRecord: Equatable, Identifiable, Hashable {
    enum Source: String, Codable {
        case contact
        case conversation
    }

    let lightningAddress: String
    let displayName: String
    let profilePicURL: String?
    let lastInteractedAt: Date?
    let source: Source

    var id: String { lightningAddress }
}
