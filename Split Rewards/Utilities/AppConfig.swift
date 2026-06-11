// AppConfig.swift

import Foundation

struct AppConfig {
    static let baseURL: String = {
        let legacyValue = (Bundle.main.object(forInfoDictionaryKey: "SplitBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let legacyValue, !legacyValue.isEmpty, URL(string: legacyValue) != nil {
            return legacyValue
        }

        guard let rawScheme = Bundle.main.object(forInfoDictionaryKey: "SplitBaseScheme") as? String else {
            preconditionFailure("SplitBaseScheme is missing from the app configuration.")
        }

        guard let rawHost = Bundle.main.object(forInfoDictionaryKey: "SplitBaseHost") as? String else {
            preconditionFailure("SplitBaseHost is missing from the app configuration.")
        }

        let scheme = rawScheme.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !scheme.isEmpty, !host.isEmpty else {
            preconditionFailure("Split base URL config is empty. Configure BASE_SCHEME and BASE_HOST in the xcconfig files.")
        }

        let value = "\(scheme)://\(host)"
        guard URL(string: value) != nil else {
            preconditionFailure("Split base URL config is invalid. Check BASE_SCHEME and BASE_HOST in the xcconfig files.")
        }

        return value
    }()

    static let messagingPushEnvironment: String = {
        let configuredValue = (Bundle.main.object(forInfoDictionaryKey: "SplitMessagingPushEnvironment") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let configuredValue, ["dev", "prod"].contains(configuredValue) {
            return configuredValue
        }

        guard let url = URL(string: baseURL),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return "prod"
        }

        if host == "localhost" || host.hasSuffix(".local") || host.contains("dev") || host.contains("ngrok") {
            return "dev"
        }

        return "prod"
    }()

}
