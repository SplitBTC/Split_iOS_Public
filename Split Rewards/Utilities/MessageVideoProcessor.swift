//
//  MessageVideoProcessor.swift
//  Split Rewards
//
//  Created by TeeVee on 3/30/26.
//

import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct PreparedVideoAttachment {
    let fileData: Data
    let fileName: String
    let mimeType: String
}

enum MessageVideoProcessor {
    enum VideoProcessingError: LocalizedError {
        case unsupportedVideo
        case failedToReadVideo
        case failedToPrepareExport
        case failedToExportVideo
        case fileTooLarge(maxBytes: Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVideo:
                return "This video format isn't supported for messaging."
            case .failedToReadVideo:
                return "Failed to read the selected video."
            case .failedToPrepareExport:
                return "Could not prepare the selected video."
            case .failedToExportVideo:
                return "Could not compress the selected video."
            case .fileTooLarge(let maxBytes):
                return "Videos must be smaller than \(ByteCountFormatter.string(fromByteCount: Int64(maxBytes), countStyle: .file))."
            }
        }
    }

    private static let preferredExportPresets: [String] = [
        AVAssetExportPreset1280x720,
        AVAssetExportPreset960x540,
        AVAssetExportPresetMediumQuality,
        AVAssetExportPreset640x480
    ]

    static func prepareVideoAttachment(
        from sourceURL: URL,
        maximumBytes: Int
    ) async throws -> PreparedVideoAttachment {
        let asset = AVURLAsset(url: sourceURL)

        var lastOversizedError = false

        for presetName in preferredExportPresets {
            let isCompatible = await AVAssetExportSession.compatibility(
                ofExportPreset: presetName,
                with: asset,
                outputFileType: nil
            )

            guard isCompatible else {
                continue
            }

            let exported = try await exportVideo(asset: asset, presetName: presetName)
            defer {
                try? FileManager.default.removeItem(at: exported.url)
            }

            let data = try Data(contentsOf: exported.url)
            guard !data.isEmpty else {
                throw VideoProcessingError.failedToReadVideo
            }

            if data.count <= maximumBytes {
                return PreparedVideoAttachment(
                    fileData: data,
                    fileName: makeFileName(extension: exported.fileExtension),
                    mimeType: exported.mimeType
                )
            }

            lastOversizedError = true
        }

        let originalData = try Data(contentsOf: sourceURL)
        if !originalData.isEmpty, originalData.count <= maximumBytes {
            let contentType = UTType(filenameExtension: sourceURL.pathExtension) ?? .movie
            let fileExtension = contentType.preferredFilenameExtension ?? fallbackFileExtension(for: contentType)
            return PreparedVideoAttachment(
                fileData: originalData,
                fileName: makeFileName(extension: fileExtension),
                mimeType: contentType.preferredMIMEType ?? "video/quicktime"
            )
        }

        if lastOversizedError || originalData.count > maximumBytes {
            throw VideoProcessingError.fileTooLarge(maxBytes: maximumBytes)
        }

        throw VideoProcessingError.failedToExportVideo
    }

    private static func exportVideo(
        asset: AVAsset,
        presetName: String
    ) async throws -> (url: URL, mimeType: String, fileExtension: String) {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw VideoProcessingError.failedToPrepareExport
        }

        let fileType: AVFileType
        let mimeType: String
        let fileExtension: String

        if exportSession.supportedFileTypes.contains(.mp4) {
            fileType = .mp4
            mimeType = "video/mp4"
            fileExtension = "mp4"
        } else if exportSession.supportedFileTypes.contains(.mov) {
            fileType = .mov
            mimeType = "video/quicktime"
            fileExtension = "mov"
        } else {
            throw VideoProcessingError.unsupportedVideo
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("split-video-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = fileType
        exportSession.shouldOptimizeForNetworkUse = true
        try await exportSession.export(to: outputURL, as: fileType)

        return (outputURL, mimeType, fileExtension)
    }

    private static func makeFileName(extension fileExtension: String) -> String {
        "video-\(Int(Date().timeIntervalSince1970)).\(fileExtension)"
    }

    private static func fallbackFileExtension(for type: UTType) -> String {
        if type.conforms(to: .mpeg4Movie) {
            return "mp4"
        }
        return "mov"
    }
}
