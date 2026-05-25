//
//  GetNearbyCoupons.swift
//  Split Rewards
//
//  Created by OpenAI on 4/14/26.
//

import Foundation

struct NearbyCouponAddress: Decodable, Hashable {
    let formattedAddress: String
    let line1: String
    let line2: String
    let city: String
    let state: String
    let postalCode: String
    let countryCode: String
    let placeId: String
    let latitude: Double
    let longitude: Double
}

struct NearbyCouponSearchOrigin: Decodable, Hashable {
    let source: String
    let latitude: Double
    let longitude: Double
    let postalCode: String?
    let formattedAddress: String?
}

struct NearbyCoupon: Decodable, Identifiable, Hashable {
    let id: String
    let businessName: String
    let businessLogoUrl: String?
    let dealDescription: String
    let appliesToAllLocations: Bool
    var hasRedeemedThisMonth: Bool
    var currentUserRedeemedAt: String?
    let primaryBusinessAddress: NearbyCouponAddress
    let distanceMiles: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case businessName
        case businessLogoUrl
        case dealDescription
        case appliesToAllLocations
        case hasRedeemedThisMonth
        case currentUserRedeemedAt
        case primaryBusinessAddress
        case distanceMiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        businessName = try container.decode(String.self, forKey: .businessName)
        businessLogoUrl = try container.decodeIfPresent(String.self, forKey: .businessLogoUrl)
        dealDescription = try container.decode(String.self, forKey: .dealDescription)
        appliesToAllLocations = try container.decode(Bool.self, forKey: .appliesToAllLocations)
        hasRedeemedThisMonth = try container.decodeIfPresent(Bool.self, forKey: .hasRedeemedThisMonth) ?? false
        currentUserRedeemedAt = try container.decodeIfPresent(String.self, forKey: .currentUserRedeemedAt)
        primaryBusinessAddress = try container.decode(NearbyCouponAddress.self, forKey: .primaryBusinessAddress)
        distanceMiles = try container.decodeIfPresent(Double.self, forKey: .distanceMiles)
    }
}

struct NearbyCouponsResponse: Decodable {
    let coupons: [NearbyCoupon]
    let searchOrigin: NearbyCouponSearchOrigin
    let radiusMiles: Double
}

struct RedeemNearbyCouponResponse: Decodable {
    let ok: Bool
    let didRedeem: Bool
    let alreadyRedeemedThisMonth: Bool
    let redemptionMonth: String
    let redeemedAt: String?
}

private struct NearbyCouponsErrorResponse: Decodable {
    let error: String
}

enum NearbyCouponsAPI {
    static func fetchNearbyCoupons(
        latitude: Double,
        longitude: Double,
        radiusMiles: Double = 25
    ) async throws -> NearbyCouponsResponse {
        var components = URLComponents(string: "\(AppConfig.baseURL)/v1/merchant-coupons/nearby")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "radiusMiles", value: String(radiusMiles))
        ]

        return try await performRequest(with: components)
    }

    static func fetchNearbyCoupons(
        postalCode: String,
        radiusMiles: Double = 25
    ) async throws -> NearbyCouponsResponse {
        var components = URLComponents(string: "\(AppConfig.baseURL)/v1/merchant-coupons/nearby")
        components?.queryItems = [
            URLQueryItem(name: "postalCode", value: postalCode),
            URLQueryItem(name: "radiusMiles", value: String(radiusMiles))
        ]

        return try await performRequest(with: components)
    }

    static func redeemCoupon(couponId: String) async throws -> RedeemNearbyCouponResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/v1/merchant-coupons/\(couponId)/redeem") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15

        let data = try await performDataRequest(with: request)
        return try JSONDecoder().decode(RedeemNearbyCouponResponse.self, from: data)
    }

    private static func performRequest(with components: URLComponents?) async throws -> NearbyCouponsResponse {
        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let data = try await performDataRequest(with: request)
        return try JSONDecoder().decode(NearbyCouponsResponse.self, from: data)
    }

    private static func performDataRequest(with request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(NearbyCouponsErrorResponse.self, from: data)
            let raw = String(data: data, encoding: .utf8) ?? ""
            let message = apiError?.error ?? raw

            throw NSError(
                domain: "NearbyCouponsAPI",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        message.isEmpty
                        ? "Server error (HTTP \(httpResponse.statusCode))"
                        : message
                ]
            )
        }

        return data
    }
}
