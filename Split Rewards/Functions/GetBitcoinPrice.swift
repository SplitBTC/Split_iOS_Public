//  GetBitcoinPrice.swift
//  Split Rewards
//
//  Created by TeeVee on 1/15/26.
//
import Foundation

// MARK: - Response Models (Spot)

struct CoinbaseSpotPriceResponse: Decodable {
    let data: SpotPriceData

    struct SpotPriceData: Decodable {
        let amount: String
        let currency: String
    }
}

// MARK: - Chart Models

struct BitcoinPricePoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let priceUSD: Double
}

enum BitcoinChartRange: String, CaseIterable {
    case day
    case month
    case year
    case yearToDate
}

private struct CoinbaseCandle: Equatable {
    let time: Date
    let low: Double
    let high: Double
    let open: Double
    let close: Double
    let volume: Double

    init?(array: [Double]) {
        guard array.count >= 6 else { return nil }
        self.time = Date(timeIntervalSince1970: array[0])
        self.low = array[1]
        self.high = array[2]
        self.open = array[3]
        self.close = array[4]
        self.volume = array[5]
    }
}

// MARK: - Spot Price (PUBLIC)

@MainActor
func fetchBitcoinPriceUSD(
    onSuccess: ((Double) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    guard let url = URL(string: "https://api.coinbase.com/v2/prices/BTC-USD/spot") else {
        onError?("Invalid Coinbase price URL")
        return
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 10

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            DispatchQueue.main.async {
                onError?("Network error fetching BTC price: \(error.localizedDescription)")
            }
            return
        }

        guard let data = data else {
            DispatchQueue.main.async { onError?("No data returned from Coinbase") }
            return
        }

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("Coinbase price error \(httpResponse.statusCode): \(body)")
            DispatchQueue.main.async { onError?("Coinbase returned error \(httpResponse.statusCode)") }
            return
        }

        do {
            let decoded = try JSONDecoder().decode(CoinbaseSpotPriceResponse.self, from: data)
            guard let price = Double(decoded.data.amount) else {
                DispatchQueue.main.async { onError?("Invalid BTC price format from Coinbase") }
                return
            }
            DispatchQueue.main.async { onSuccess?(price) }
        } catch {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
            print("Coinbase price decode error: \(error)")
            print("Raw response body: \(body)")
            DispatchQueue.main.async { onError?("Failed to decode BTC price response") }
        }
    }
    .resume()
}

// MARK: - Candles Series (PUBLIC, Coinbase Exchange)

@MainActor
func fetchBitcoinPriceSeriesUSD(
    range: BitcoinChartRange,
    onSuccess: (([BitcoinPricePoint]) -> Void)? = nil,
    onError: ((String) -> Void)? = nil
) {
    Task {
        do {
            let points = try await fetchBitcoinPriceSeriesUSD(range: range)
            onSuccess?(points)
        } catch {
            onError?("Failed to fetch BTC chart data: \(error.localizedDescription)")
        }
    }
}

func fetchBitcoinPriceSeriesUSD(range: BitcoinChartRange) async throws -> [BitcoinPricePoint] {
    let now = Date()
    let calendar = Calendar(identifier: .gregorian)

    let start: Date = {
        switch range {
        case .day:
            return calendar.date(byAdding: .day, value: -1, to: now) ?? now.addingTimeInterval(-86400)
        case .month:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 86400)
        case .year:
            return calendar.date(byAdding: .day, value: -365, to: now) ?? now.addingTimeInterval(-365 * 86400)
        case .yearToDate:
            let comps = calendar.dateComponents([.year], from: now)
            return calendar.date(from: DateComponents(year: comps.year, month: 1, day: 1)) ?? now
        }
    }()

    // Granularity selection
    // day: 5m candles (<= 288)
    // month: 6h candles (~120)
    // year/YTD: 1d candles (needs chunking due to 300 max)
    let granularitySeconds: Int = {
        switch range {
        case .day: return 300
        case .month: return 21600
        case .year, .yearToDate: return 86400
        }
    }()

    let maxCandlesPerRequest = 300
    let maxSpanSeconds = TimeInterval(granularitySeconds * maxCandlesPerRequest)

    var allCandles: [CoinbaseCandle] = []
    var windowStart = start

    while windowStart < now {
        let windowEnd = min(now, windowStart.addingTimeInterval(maxSpanSeconds))

        let candles = try await fetchCoinbaseCandles(
            productId: "BTC-USD",
            start: windowStart,
            end: windowEnd,
            granularitySeconds: granularitySeconds
        )

        allCandles.append(contentsOf: candles)
        windowStart = windowEnd
    }

    // De-dupe by timestamp and sort ascending
    let deduped = allCandles
        .filter { $0.time >= start && $0.time <= now }
        .reduce(into: [TimeInterval: CoinbaseCandle]()) { dict, candle in
            dict[candle.time.timeIntervalSince1970] = candle
        }
        .values
        .sorted { $0.time < $1.time }

    // Use CLOSE
    return deduped.map { BitcoinPricePoint(date: $0.time, priceUSD: $0.close) }
}

func fetchBitcoinPriceUSD(at date: Date) async throws -> Double {
    let now = Date()
    let granularitySeconds = 300
    let windowSeconds: TimeInterval = 3 * 3_600

    let start = min(date, now).addingTimeInterval(-(windowSeconds / 2))
    let end = min(now, date.addingTimeInterval(windowSeconds / 2))

    let candles = try await fetchCoinbaseCandles(
        productId: "BTC-USD",
        start: start,
        end: end,
        granularitySeconds: granularitySeconds
    )

    guard let nearest = candles.min(by: {
        abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
    }) else {
        throw NSError(
            domain: "CoinbaseHistoricalPrice",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No BTC/USD candle found near transaction time."]
        )
    }

    return nearest.close
}

private func fetchCoinbaseCandles(
    productId: String,
    start: Date,
    end: Date,
    granularitySeconds: Int
) async throws -> [CoinbaseCandle] {
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime]
    iso.timeZone = TimeZone(secondsFromGMT: 0)

    guard var comps = URLComponents(string: "https://api.exchange.coinbase.com/products/\(productId)/candles") else {
        throw NSError(domain: "CoinbaseCandles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid candles URL"])
    }

    comps.queryItems = [
        URLQueryItem(name: "start", value: iso.string(from: start)),
        URLQueryItem(name: "end", value: iso.string(from: end)),
        URLQueryItem(name: "granularity", value: String(granularitySeconds))
    ]

    guard let url = comps.url else {
        throw NSError(domain: "CoinbaseCandles", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to build candles URL"])
    }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.timeoutInterval = 12
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let (data, response) = try await URLSession.shared.data(for: request)

    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
        let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        print("Coinbase candles error \(http.statusCode): \(body)")
        throw NSError(domain: "CoinbaseCandles", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Coinbase candles returned error \(http.statusCode)"])
    }

    let json = try JSONSerialization.jsonObject(with: data, options: [])
    guard let rows = json as? [[Double]] else {
        let body = String(data: data, encoding: .utf8) ?? "<non-UTF8>"
        print("Coinbase candles unexpected JSON: \(body)")
        throw NSError(domain: "CoinbaseCandles", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unexpected candles response format"])
    }

    return rows.compactMap { CoinbaseCandle(array: $0) }
}
