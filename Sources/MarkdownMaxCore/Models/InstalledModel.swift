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
    case tiny   = "tiny"
    case small  = "small"
    case medium = "medium"
    case large  = "large"

    public var displayName: String {
        switch self {
        case .tiny:   return "Tiny (39 MB)"
        case .small:  return "Small (244 MB)"
        case .medium: return "Medium (1.5 GB)"
        case .large:  return "Large (3 GB)"
        }
    }

    public var sizeMB: Int {
        switch self {
        case .tiny:   return 39
        case .small:  return 244
        case .medium: return 1500
        case .large:  return 3000
        }
    }

    public var sizeFormatted: String {
        sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB"
    }

    public var werPercent: String {
        switch self {
        case .tiny:   return "4–5%"
        case .small:  return "3–4%"
        case .medium: return "2–3%"
        case .large:  return "~1%"
        }
    }

    public var speedDescription: String {
        switch self {
        case .tiny:   return "~8 sec / 10 min"
        case .small:  return "~45 sec / 10 min"
        case .medium: return "2–3 min / 10 min"
        case .large:  return "5–7 min / 10 min"
        }
    }

    public var whisperKitName: String {
        switch self {
        case .tiny:   return "openai_whisper-tiny"
        case .small:  return "openai_whisper-small"
        case .medium: return "openai_whisper-medium"
        case .large:  return "openai_whisper-large-v3"
        }
    }
}
