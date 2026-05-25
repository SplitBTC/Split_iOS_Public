//
//  GetBTCMapPlaces.swift
//  Split Rewards
//
//  Created by TeeVee on 3/24/26.
//

import Foundation

struct BTCMapPlace: Decodable, Identifiable, Equatable {
    let id: Int
    let lat: Double
    let lon: Double
    let icon: String?
    let name: String?
    let address: String?
    let phone: String?
    let website: String?
    let description: String?
    let image: String?
    let paymentProvider: String?
    let verifiedAt: String?
    let osmURL: String?

    enum CodingKeys: String, CodingKey {
        case id
        case lat
        case lon
        case icon
        case name
        case address
        case phone
        case website
        case description
        case image
        case paymentProvider = "payment_provider"
        case verifiedAt = "verified_at"
        case osmURL = "osm_url"
    }
}

enum GetBTCMapPlacesAPI {
    static func fetchPlaces(
        latitude: Double,
        longitude: Double,
        radiusKilometers: Double
    ) async throws -> [BTCMapPlace] {
        var components = URLComponents(string: "https://api.btcmap.org/v4/places/search/")
        components?.queryItems = [
            URLQueryItem(name: "lat", value: String(latitude)),
            URLQueryItem(name: "lon", value: String(longitude)),
            URLQueryItem(name: "radius_km", value: String(radiusKilometers)),
            URLQueryItem(
                name: "fields",
                value: "id,lat,lon,icon,name,address,phone,website,description,image,payment_provider,verified_at,osm_url"
            )
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "GetBTCMapPlacesAPI",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        raw.isEmpty
                        ? "BTC Map returned HTTP \(httpResponse.statusCode)."
                        : "BTC Map returned HTTP \(httpResponse.statusCode): \(raw)"
                ]
            )
        }

        let decoder = JSONDecoder()
        return try decoder.decode([BTCMapPlace].self, from: data)
    }
}
