//
//  MessagePaymentPayloads.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import Foundation

struct PaymentRequestMessagePayload: Codable, Equatable {
    let invoice: String
    let amountSats: UInt64
    let requesterLightningAddress: String?
    let note: String?
}

struct PaymentRequestPaidMessagePayload: Codable, Equatable {
    let requestMessageId: String
    let invoice: String
    let paidAt: Date
}

struct AttachmentMessagePayload: Codable, Equatable {
    let attachmentId: String
    let fileName: String
    let mimeType: String
    let sizeBytes: Int
    let imageWidth: Int?
    let imageHeight: Int?
    let attachmentNonce: String
    let attachmentSenderEphemeralPubkey: String
}

enum MessageReactionKind: String, Codable, CaseIterable, Equatable, Hashable, Identifiable {
    case love
    case like
    case dislike
    case laugh
    case emphasize
    case question
    case remove

    var id: String { rawValue }

    static var selectableCases: [MessageReactionKind] {
        [.love, .like, .dislike, .laugh, .emphasize, .question]
    }

    var menuTitle: String {
        switch self {
        case .love:
            return "Love"
        case .like:
            return "Like"
        case .dislike:
            return "Dislike"
        case .laugh:
            return "Laugh"
        case .emphasize:
            return "Emphasize"
        case .question:
            return "Question"
        case .remove:
            return "Remove Reaction"
        }
    }

    var badgeText: String {
        switch self {
        case .love:
            return "Love"
        case .like:
            return "Like"
        case .dislike:
            return "Dislike"
        case .laugh:
            return "HaHa"
        case .emphasize:
            return "!!"
        case .question:
            return "?"
        case .remove:
            return "Remove"
        }
    }

    var systemImageName: String? {
        switch self {
        case .love:
            return "heart.fill"
        case .like:
            return "hand.thumbsup.fill"
        case .dislike:
            return "hand.thumbsdown.fill"
        case .laugh:
            return nil
        case .emphasize:
            return "exclamationmark.2"
        case .question:
            return "questionmark"
        case .remove:
            return "xmark"
        }
    }

    var previewText: String {
        switch self {
        case .love:
            return "Loved a message"
        case .like:
            return "Liked a message"
        case .dislike:
            return "Disliked a message"
        case .laugh:
            return "Laughed at a message"
        case .emphasize:
            return "Emphasized a message"
        case .question:
            return "Questioned a message"
        case .remove:
            return "Removed a reaction"
        }
    }
}

struct MessageReactionPayload: Codable, Equatable {
    let targetMessageId: String
    let reactionKey: String
}

enum MessagePayloadCodec {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static func encodePaymentRequest(_ payload: PaymentRequestMessagePayload) throws -> String {
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "MessagePayloadCodec",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode payment request payload."]
            )
        }
        return string
    }

    static func decodePaymentRequest(from body: String) -> PaymentRequestMessagePayload? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? decoder.decode(PaymentRequestMessagePayload.self, from: data)
    }

    static func encodePaymentRequestPaid(_ payload: PaymentRequestPaidMessagePayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "MessagePayloadCodec",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode payment status payload."]
            )
        }
        return string
    }

    static func decodePaymentRequestPaid(from body: String) -> PaymentRequestPaidMessagePayload? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = body.data(using: .utf8) else { return nil }
        return try? decoder.decode(PaymentRequestPaidMessagePayload.self, from: data)
    }

    static func encodeAttachment(_ payload: AttachmentMessagePayload) throws -> String {
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "MessagePayloadCodec",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode attachment payload."]
            )
        }
        return string
    }

    static func decodeAttachment(from body: String) -> AttachmentMessagePayload? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? decoder.decode(AttachmentMessagePayload.self, from: data)
    }

    static func encodeReaction(_ payload: MessageReactionPayload) throws -> String {
        let data = try encoder.encode(payload)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NSError(
                domain: "MessagePayloadCodec",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode reaction payload."]
            )
        }
        return string
    }

    static func decodeReaction(from body: String) -> MessageReactionPayload? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? decoder.decode(MessageReactionPayload.self, from: data)
    }

    static func decodeReactionKind(from body: String) -> MessageReactionKind? {
        guard let payload = decodeReaction(from: body) else { return nil }
        return MessageReactionKind(rawValue: payload.reactionKey)
    }

    static func previewText(for message: StoredMessage) -> String {
        switch message.messageType {
        case "payment_request":
            guard let payload = decodePaymentRequest(from: message.body) else {
                return "Payment request"
            }
            return "Payment request: \(formattedSats(payload.amountSats)) sats"
        case "payment_request_paid":
            return "Payment request paid"
        case "attachment":
            guard let payload = decodeAttachment(from: message.body) else {
                return "Attachment"
            }
            if payload.mimeType.lowercased().hasPrefix("image/") {
                return "Photo: \(payload.fileName)"
            }
            if payload.mimeType.lowercased().hasPrefix("video/") {
                return "Video: \(payload.fileName)"
            }
            return "File: \(payload.fileName)"
        case "reaction":
            return decodeReactionKind(from: message.body)?.previewText ?? "Reacted to a message"
        default:
            return message.body
        }
    }

    static func searchableText(for message: StoredMessage) -> String {
        switch message.messageType {
        case "payment_request":
            guard let payload = decodePaymentRequest(from: message.body) else {
                return "payment request"
            }

            return [
                "payment request",
                formattedSats(payload.amountSats),
                "sats",
                payload.requesterLightningAddress ?? "",
                payload.note ?? ""
            ]
            .joined(separator: " ")

        case "payment_request_paid":
            guard let payload = decodePaymentRequestPaid(from: message.body) else {
                return "payment request paid"
            }

            return [
                "payment request paid",
                payload.invoice
            ]
            .joined(separator: " ")

        case "attachment":
            guard let payload = decodeAttachment(from: message.body) else {
                return "attachment"
            }

            return [
                payload.mimeType.lowercased().hasPrefix("image/") ? "photo" :
                    (payload.mimeType.lowercased().hasPrefix("video/") ? "video" : "file"),
                "attachment",
                payload.fileName,
                payload.mimeType
            ]
            .joined(separator: " ")

        case "reaction":
            return decodeReactionKind(from: message.body)?.previewText ?? "reacted to a message"

        default:
            return message.body
        }
    }

    static func formattedSats(_ amountSats: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amountSats)) ?? "\(amountSats)"
    }
}
