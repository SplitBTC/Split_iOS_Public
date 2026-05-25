//
//  PostProfilePic.swift
//  Split Rewards
//
//  Created by TeeVee on 3/18/26.
//

import Foundation

struct PostProfilePicResponse: Decodable {
    let ok: Bool?
    let profilePicUrl: String?
    let error: String?
}

enum PostProfilePicError: LocalizedError {
    case invalidURL
    case emptyFileData
    case invalidResponse
    case serverError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid upload profile picture endpoint URL."
        case .emptyFileData:
            return "Profile picture data is empty."
        case .invalidResponse:
            return "Invalid server response."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}

enum ProfilePicUploadAPI {
    @MainActor
    static func postProfilePic(
        fileData: Data,
        fileName: String = "profile-picture.jpg",
        mimeType: String = "image/jpeg",
        authManager: AuthManager,
        walletManager: WalletManager
    ) async throws -> PostProfilePicResponse {

        guard !fileData.isEmpty else {
            throw PostProfilePicError.emptyFileData
        }

        guard let url = URL(string: "\(AppConfig.baseURL)/Upload_Profile_Pic") else {
            throw PostProfilePicError.invalidURL
        }

        try await authManager.ensureSession(walletManager: walletManager)

        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = true
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = makeMultipartBody(
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            boundary: boundary
        )

        // FIRST ATTEMPT
        var (data, response) = try await URLSession.shared.data(for: request)

        // Retry once on auth failures after refreshing session
        if let http = response as? HTTPURLResponse,
           http.statusCode == 401 || http.statusCode == 403 {

            authManager.invalidateSession()
            try await authManager.ensureSession(walletManager: walletManager)

            request.httpBody = makeMultipartBody(
                fileData: fileData,
                fileName: fileName,
                mimeType: mimeType,
                boundary: boundary
            )

            (data, response) = try await URLSession.shared.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProfilePicError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let serverMessage: String

            if let decoded = try? JSONDecoder().decode(PostProfilePicResponse.self, from: data),
               let error = decoded.error,
               !error.isEmpty {
                serverMessage = error
            } else {
                serverMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
            }

            throw PostProfilePicError.serverError(
                statusCode: httpResponse.statusCode,
                message: serverMessage
            )
        }

        if data.isEmpty {
            return PostProfilePicResponse(
                ok: true,
                profilePicUrl: nil,
                error: nil
            )
        }

        do {
            return try JSONDecoder().decode(PostProfilePicResponse.self, from: data)
        } catch {
            throw PostProfilePicError.invalidResponse
        }
    }

    private static func makeMultipartBody(
        fileData: Data,
        fileName: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"profilePic\"; filename=\"\(fileName)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")

        return body
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
