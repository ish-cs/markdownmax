import MarkdownMaxCore
import Foundation
import Combine

enum DownloadError: Error, LocalizedError {
    case networkError(Error)
    case checksumMismatch
    case fileSystemError(Error)
    case invalidResponse(Int)

    var errorDescription: String? {
        switch self {
        case .networkError(let e):    return "Download failed: \(e.localizedDescription)"
        case .checksumMismatch:       return "Download corrupted — checksum mismatch. Please try again."
        case .fileSystemError(let e): return "File system error: \(e.localizedDescription)"
        case .invalidResponse(let code): return "Server returned error \(code)"
        }
    }
}

struct ModelDownloadState: Equatable {
    var modelName: WhisperModelSize
    var bytesReceived: Int64
    var totalBytes: Int64
    var isDownloading: Bool
    var isComplete: Bool
    var error: String?
    var startedAt: Date? = nil

    var elapsedFormatted: String {
        guard let start = startedAt else { return "" }
        let s = Int(-start.timeIntervalSinceNow)
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }
}

@MainActor
final class ModelDownloadManager: NSObject, ObservableObject {
    @Published private(set) var downloadStates: [WhisperModelSize: ModelDownloadState] = [:]

    private var activeTasks: [WhisperModelSize: URLSessionDownloadTask] = [:]
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 7200  // 2 hours for large models
        return URLSession(configuration: config, delegate: nil, delegateQueue: .main)
    }()

    var modelsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarkdownMax/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    func modelDirectory(for model: WhisperModelSize) -> URL {
        modelsDirectory.appendingPathComponent(model.rawValue, isDirectory: true)
    }

    /// Where WhisperKit + Hub place files for a variant (matches `WhisperKit.download` → `HubApi.localRepoLocation` + variant folder).
    func resolvedModelFolder(for model: WhisperModelSize) -> URL {
        modelsDirectory
            .appending(component: "models")
            .appending(component: "argmaxinc/whisperkit-coreml")
            .appending(path: model.whisperKitName)
    }

    func isInstalled(_ model: WhisperModelSize) -> Bool {
        let mel = resolvedModelFolder(for: model).appendingPathComponent("MelSpectrogram.mlmodelc")
        return FileManager.default.fileExists(atPath: mel.path)
    }

    // MARK: - Download

    /// - Returns: On-disk folder that contains `MelSpectrogram.mlmodelc` (pass to `WhisperKitConfig` / DB `filePath`).
    @discardableResult
    func downloadModel(_ model: WhisperModelSize) async throws -> URL {
        guard !isInstalled(model) else { return resolvedModelFolder(for: model) }

        downloadStates[model] = ModelDownloadState(
            modelName: model,
            bytesReceived: 0,
            totalBytes: Int64(model.sizeMB) * 1024 * 1024,
            isDownloading: true,
            isComplete: false,
            startedAt: Date()
        )

        do {
            let modelFolder = try await downloadWhisperKitModel(model)
            downloadStates[model] = ModelDownloadState(
                modelName: model,
                bytesReceived: Int64(model.sizeMB) * 1024 * 1024,
                totalBytes: Int64(model.sizeMB) * 1024 * 1024,
                isDownloading: false,
                isComplete: true
            )
            return modelFolder
        } catch {
            downloadStates[model] = nil
            throw error
        }
    }

    private func downloadWhisperKitModel(_ model: WhisperModelSize) async throws -> URL {
        let modelName = model.whisperKitName
        return try await WhisperKitDownloader.download(model: modelName, downloadBase: modelsDirectory)
    }

    func cancelDownload(_ model: WhisperModelSize) {
        activeTasks[model]?.cancel()
        activeTasks[model] = nil
        downloadStates[model] = nil
    }

    // MARK: - Deletion

    /// Removes the downloaded Hub folder for this variant (actual path from `WhisperKit.download`).
    func deleteDownloadedModel(folderPath: String, model: WhisperModelSize) throws {
        let url = URL(fileURLWithPath: folderPath)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // Legacy bug: empty `models/<tiny|small|...>/` dirs were created; remove if present.
        let legacy = modelDirectory(for: model)
        if FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.removeItem(at: legacy)
        }
    }

    func removeDownloadState(for model: WhisperModelSize) {
        downloadStates[model] = nil
    }

    func installedModels() -> [WhisperModelSize] {
        WhisperModelSize.allCases.filter { isInstalled($0) }
    }
}

// MARK: - WhisperKit Download Bridge

/// Bridges to WhisperKit's built-in model downloader
private enum WhisperKitDownloader {
    static func download(model: String, downloadBase: URL) async throws -> URL {
        try await WhisperKit.download(
            variant: model,
            downloadBase: downloadBase,
            useBackgroundSession: false
        )
    }
}

// Forward import for the above
import WhisperKit
