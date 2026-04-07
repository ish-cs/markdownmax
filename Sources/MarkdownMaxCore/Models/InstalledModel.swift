import Foundation

public struct InstalledModel: Identifiable, Equatable {
    public let id: Int64
    public var modelName: WhisperModelSize
    public var version: String?
    public var filePath: String
    public var sizeMB: Int
    public var isActive: Bool
    public var downloadedAt: Date?
    public var lastUsed: Date?

    public init(id: Int64, modelName: WhisperModelSize, version: String?, filePath: String,
                sizeMB: Int, isActive: Bool, downloadedAt: Date?, lastUsed: Date? = nil) {
        self.id = id
        self.modelName = modelName
        self.version = version
        self.filePath = filePath
        self.sizeMB = sizeMB
        self.isActive = isActive
        self.downloadedAt = downloadedAt
        self.lastUsed = lastUsed
    }

    public var displayName: String { modelName.displayName }
    public var sizeFormatted: String {
        sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB"
    }
}

public enum WhisperModelSize: String, CaseIterable, Codable {
    case tiny          = "tiny"
    case small         = "small"
    case medium        = "medium"
    case large         = "large"
    case largeV3Turbo  = "large-v3-turbo"
    case distilLargeV3 = "distil-large-v3"

    public var displayName: String {
        switch self {
        case .tiny:          return "Tiny (39 MB)"
        case .small:         return "Small (244 MB)"
        case .medium:        return "Medium (1.5 GB)"
        case .large:         return "Large v3 (3 GB)"
        case .largeV3Turbo:  return "Large v3 Turbo (1.6 GB)"
        case .distilLargeV3: return "Distil Large v3 (1.5 GB)"
        }
    }

    public var sizeMB: Int {
        switch self {
        case .tiny:          return 39
        case .small:         return 244
        case .medium:        return 1500
        case .large:         return 3000
        case .largeV3Turbo:  return 1600
        case .distilLargeV3: return 1500
        }
    }

    public var sizeFormatted: String {
        sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB"
    }

    public var werPercent: String {
        switch self {
        case .tiny:          return "4–5%"
        case .small:         return "3–4%"
        case .medium:        return "2–3%"
        case .large:         return "~1%"
        case .largeV3Turbo:  return "~1%"
        case .distilLargeV3: return "~1%"
        }
    }

    public var speedDescription: String {
        switch self {
        case .tiny:          return "~8 sec / 10 min"
        case .small:         return "~45 sec / 10 min"
        case .medium:        return "2–3 min / 10 min"
        case .large:         return "5–7 min / 10 min"
        case .largeV3Turbo:  return "~1 min / 10 min"
        case .distilLargeV3: return "~1 min / 10 min"
        }
    }

    public var hoverDetail: String {
        switch self {
        case .tiny:
            return "Speed: ★★★★★  Quality: ★☆☆☆☆\nFastest model. Good for quick notes or live transcription. Noticeably less accurate on complex speech or accents."
        case .small:
            return "Speed: ★★★★☆  Quality: ★★☆☆☆\nGood balance for live transcription. Handles most accents reasonably well."
        case .medium:
            return "Speed: ★★★☆☆  Quality: ★★★☆☆\nSolid accuracy for most use cases. Slower on long recordings."
        case .large:
            return "Speed: ★★☆☆☆  Quality: ★★★★☆\nHigh accuracy. Slow — best for post-recording transcription, not live use."
        case .largeV3Turbo:
            return "Speed: ★★★★☆  Quality: ★★★★★\nOpenAI's Oct 2024 model. Near-identical accuracy to Large v3 at ~8× the speed. Best overall choice."
        case .distilLargeV3:
            return "Speed: ★★★★☆  Quality: ★★★★☆\nHuggingFace distilled model. ~6× faster than Large v3 with ~1% accuracy trade-off. Great for live use."
        }
    }

    public var displayLabel: String {
        switch self {
        case .tiny:          return "Tiny"
        case .small:         return "Small"
        case .medium:        return "Medium"
        case .large:         return "Large v3"
        case .largeV3Turbo:  return "Large v3 Turbo"
        case .distilLargeV3: return "Distil Large v3"
        }
    }

    public var whisperKitName: String {
        switch self {
        case .tiny:          return "openai_whisper-tiny"
        case .small:         return "openai_whisper-small"
        case .medium:        return "openai_whisper-medium"
        case .large:         return "openai_whisper-large-v3"
        case .largeV3Turbo:  return "openai_whisper-large-v3_turbo"
        case .distilLargeV3: return "distil-whisper_distil-large-v3"
        }
    }
}
