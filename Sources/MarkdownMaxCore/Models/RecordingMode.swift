import Foundation

public enum RecordingMode: String, CaseIterable, Codable {
    case privacy   = "privacy"   // nothing recorded
    case passive   = "passive"   // light model, always-on
    case important = "important" // best available model

    public var displayName: String {
        switch self {
        case .privacy:   return "Privacy"
        case .passive:   return "Passive"
        case .important: return "Important"
        }
    }

    public var systemImage: String {
        switch self {
        case .privacy:   return "mic.slash.fill"
        case .passive:   return "mic.fill"
        case .important: return "star.fill"
        }
    }
}
