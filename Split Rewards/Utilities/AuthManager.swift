//  AuthManager.swift
//  Split Rewards
//
//  Wallet-based opportunistic auth:
//  - When wallet is .ready, we can fetch a nonce, sign a message, and exchange for a JWT cookie.
//  - Cookie is HttpOnly; subsequent requests use it automatically.
//  - This manager keeps an in-memory "session valid until" to avoid re-signing too often,
//    and can optionally confirm cookie validity via /session.
//
//  Created by TeeVee on 12/17/25.
//
import Foundation
import BreezSdkSpark

@MainActor
final class AuthManager: ObservableObject {

    enum AuthState: Equatable {
        case idle
        case authenticating
        case authenticated
        case failed(String)
    }

    enum AuthError: Error, LocalizedError {
        case walletNotReady
        case missingSigningProvider
        case nonceExpiredOrInvalid
        case serverRejected(String)
        case invalidResponse
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .walletNotReady:
                return "Wallet is not ready."
            case .missingSigningProvider:
                return "Wallet signing provider is not available."
            case .nonceExpiredOrInvalid:
                return "Nonce expired or invalid."
            case .serverRejected(let msg):
                return "Server rejected auth: \(msg)"
            case .invalidResponse:
                return "Invalid response from server."
            case .requestFailed(let msg):
                return msg
            }
        }
    }

    // MARK: - Published

    @Published var state: AuthState = .idle
    @Published var hasValidSession: Bool = false
    @Published var lastError: String?

    // MARK: - Config

    /// Default: 1 hour session validity as you described.
    /// (We still recommend the server be the source of truth.)
    private let assumedSessionLifetimeSeconds: TimeInterval = 60 * 60

    /// If true, ensureSession() will call GET /session to confirm the cookie
    /// before doing a sign-in handshake.
    /// Turn this on if you want to avoid re-signing on every cold launch.
    var prefersServerSessionCheck: Bool = true

    // MARK: - Internal

    private var sessionValidUntil: Date?
    private var inFlightAuthTask: Task<Void, Error>?

    init() {}

    // MARK: - Public API

    /// Ensures we have a valid cookie session.
    ///
    /// Strategy:
    /// - If our in-memory session is still valid, return immediately.
    /// - If prefersServerSessionCheck is enabled:
    ///   - Call GET /session to confirm the cookie is valid.
    ///   - If valid, extend local window and return.
    /// - Otherwise (or if /session indicates no cookie), do full wallet-login handshake.
    func ensureSession(walletManager: WalletManager) async throws {
        guard case .ready = walletManager.state else {
            throw AuthError.walletNotReady
        }

        // Fast path: in-memory validity window
        if let until = sessionValidUntil, until > Date() {
            hasValidSession = true
            state = .authenticated
            return
        }

        // If an auth attempt is already running, wait on it.
        if let task = inFlightAuthTask {
            _ = try await task.value
            return
        }

        let task = Task<Void, Error> {
            await MainActor.run {
                self.state = .authenticating
                self.lastError = nil
            }

            do {
                if prefersServerSessionCheck {
                    let ok = try await checkSessionCookieOnServer()
                    if ok {
                        await MainActor.run {
                            self.hasValidSession = true
                            self.state = .authenticated
                            self.sessionValidUntil = Date().addingTimeInterval(self.assumedSessionLifetimeSeconds)
                        }
                        return
                    }
                }

                // Fall back: do wallet-login handshake.
                try await loginWithWallet(walletManager: walletManager)

                await MainActor.run {
                    self.hasValidSession = true
                    self.state = .authenticated
                    self.sessionValidUntil = Date().addingTimeInterval(self.assumedSessionLifetimeSeconds)
                }
            } catch {
                await MainActor.run {
                    self.hasValidSession = false
                    self.state = .failed(error.localizedDescription)
                    self.lastError = error.localizedDescription
                    self.sessionValidUntil = nil
                }
                throw error
            }
        }

        inFlightAuthTask = task
        defer { inFlightAuthTask = nil }

        _ = try await task.value
    }

    /// Clears only local session knowledge.
    /// (Does not clear server cookies; you can add a /logout endpoint later if desired.)
    func resetLocalSession() {
        hasValidSession = false
        sessionValidUntil = nil
        state = .idle
        lastError = nil
    }

    func clearSessionCookies() {
        let cookieStorage = HTTPCookieStorage.shared
        cookieStorage.cookies?.forEach { cookie in
            cookieStorage.deleteCookie(cookie)
        }
    }

    /// Call this when the server returns 401/403 to force a re-auth on the next request.
    /// (Alias for resetLocalSession, but reads better at call sites.)
    func invalidateSession() {
        resetLocalSession()
    }

    // MARK: - Core handshake

    private func loginWithWallet(walletManager: WalletManager) async throws {
        // 1) Get nonce + canonical messageToSign from server
        let nonceResp = try await fetchNonce()

        // 2) Sign the server-provided message using the wallet.
        //    IMPORTANT: do NOT re-construct the message locally, or verification may fail.
        guard let sdk = walletManager.sdk else {
            throw AuthError.missingSigningProvider
        }

        let signed = try await sdk.signMessage(
            request: SignMessageRequest(message: nonceResp.messageToSign, compact: true)
        )

        // 2.5) Fetch Spark address (required; no caching; fail if it can't be fetched)
        let sparkAddress = try await fetchSparkAddress(sdk: sdk)

        // 3) Exchange for cookie JWT (server verifies signature against stored messageToSign)
        let iat = Int(Date().timeIntervalSince1970)
        try await exchangeSignatureForCookie(
            pubkey: signed.pubkey,
            nonce: nonceResp.nonce,
            signature: signed.signature,
            iat: iat,
            sparkAddress: sparkAddress
        )
    }

    // MARK: - Spark address retrieval

    /// Fetches the wallet's static Spark address from the Breez Spark SDK.
    /// Required for auth in your flow.
    private func fetchSparkAddress(sdk: BreezSdk) async throws -> String {
        let response = try await sdk.receivePayment(
            request: ReceivePaymentRequest(paymentMethod: ReceivePaymentMethod.sparkAddress)
        )
        return response.paymentRequest
    }

    // MARK: - Server calls

    private struct NonceResponse: Codable {
        let nonce: String
        let expiresAt: String?       // optional; server may include ISO string
        let messageToSign: String    // canonical message supplied by server
    }

    private struct WalletLoginRequest: Codable {
        let pubkey: String
        let nonce: String
        let signature: String
        let iat: Int
        let sparkAddress: String
        // NOTE: no `message` field; server should verify against its stored canonical message.
    }

    /// If you return anything besides 2xx, include a JSON error message if you can.
    private struct ErrorResponse: Codable {
        let error: String?
        let message: String?
    }

    /// GET /session – cookie-only validity check (recommended).
    /// Returns true if cookie valid (200).
    private func checkSessionCookieOnServer() async throws -> Bool {
        guard let url = URL(string: "\(AppConfig.baseURL)/session") else {
            throw AuthError.requestFailed("Invalid /session URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.httpShouldHandleCookies = true

        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.invalidResponse }

        return http.statusCode == 200
    }

    /// POST /auth/nonce
    private func fetchNonce() async throws -> NonceResponse {
        guard let url = URL(string: "\(AppConfig.baseURL)/auth/nonce") else {
            throw AuthError.requestFailed("Invalid /auth/nonce URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = true
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.invalidResponse }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw decodeServerError(data: data, status: http.statusCode, fallback: "Unauthorized")
            }
            throw decodeServerError(data: data, status: http.statusCode, fallback: "Nonce request failed")
        }

        guard let decoded = try? JSONDecoder().decode(NonceResponse.self, from: data) else {
            throw AuthError.invalidResponse
        }

        return decoded
    }

    /// POST /auth/wallet-login
    private func exchangeSignatureForCookie(
        pubkey: String,
        nonce: String,
        signature: String,
        iat: Int,
        sparkAddress: String
    ) async throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/auth/wallet-login") else {
            throw AuthError.requestFailed("Invalid /auth/wallet-login URL")
        }

        let body = WalletLoginRequest(
            pubkey: pubkey,
            nonce: nonce,
            signature: signature,
            iat: iat,
            sparkAddress: sparkAddress
        )

        print("📤 Sending wallet-login with sparkAddress:", sparkAddress)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpShouldHandleCookies = true
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AuthError.invalidResponse }

        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw decodeServerError(data: data, status: http.statusCode, fallback: "Unauthorized")
            }
            throw decodeServerError(data: data, status: http.statusCode, fallback: "Wallet login failed")
        }

        // Cookie should now be set in HTTPCookieStorage by URLSession automatically.
    }

    private func decodeServerError(data: Data, status: Int, fallback: String) -> Error {
        if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            let msg = err.error ?? err.message ?? "\(fallback) (HTTP \(status))"
            return AuthError.serverRejected(msg)
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return AuthError.serverRejected("\(fallback) (HTTP \(status)): \(raw)")
        }
        return AuthError.serverRejected("\(fallback) (HTTP \(status))")
    }
}


