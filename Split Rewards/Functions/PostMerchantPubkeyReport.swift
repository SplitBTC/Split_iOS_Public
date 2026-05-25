//
//  PostMerchantPubkeyReport.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import Foundation

struct MerchantPubkeyReportResponse: Decodable {
    let ok: Bool
    let error: String?
}

@MainActor
func postMerchantPubkeyReport(
    walletManager: WalletManager,
    authManager: AuthManager,
    transaction: WalletManager.TransactionRow,
    merchantName: String,
    merchantAddress: String
) async throws {
    try await authManager.ensureSession(walletManager: walletManager)

    guard let destinationPubkey = transaction.destinationPubkey,
          let url = URL(string: "\(AppConfig.baseURL)/ReportMerchantPubkey") else {
        throw MerchantPubkeyReportError.invalidRequest
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpShouldHandleCookies = true

    struct RequestBody: Encodable {
        let merchantName: String
        let merchantAddress: String
        let destinationPubkey: String
    }

    request.httpBody = try JSONEncoder().encode(
        RequestBody(
            merchantName: merchantName.trimmingCharacters(in: .whitespacesAndNewlines),
            merchantAddress: merchantAddress.trimmingCharacters(in: .whitespacesAndNewlines),
            destinationPubkey: destinationPubkey
        )
    )

    let (data, response) = try await URLSession.shared.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
        throw MerchantPubkeyReportError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
        let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
        throw MerchantPubkeyReportError.server(message)
    }

    if !data.isEmpty {
        let decoded = try JSONDecoder().decode(MerchantPubkeyReportResponse.self, from: data)
        if decoded.ok == false {
            throw MerchantPubkeyReportError.server(decoded.error ?? "Report failed")
        }
    }
}

enum MerchantPubkeyReportError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return "This transaction can’t be reported right now."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .server(let message):
            return message
        }
    }
}
