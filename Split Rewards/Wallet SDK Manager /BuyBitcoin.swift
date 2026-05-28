import Foundation
import BreezSdkSpark

extension WalletManager {
    func createCashAppBuyURL(
        amountSats: UInt64? = nil
    ) async throws -> URL {
        guard let sdk else {
            throw WalletError.sdkNotInitialized
        }

        guard let normalizedAmountSats = amountSats.flatMap({ $0 > 0 ? $0 : nil }) else {
            throw WalletError.invalidAmount
        }

        let response = try await sdk.buyBitcoin(
            request: .cashApp(amountSats: normalizedAmountSats)
        )

        guard let url = URL(string: response.url) else {
            throw URLError(.badURL)
        }

        return url
    }
}
