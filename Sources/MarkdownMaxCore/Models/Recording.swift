import Foundation

public struct Recording: Identifiable, Equatable {
    public let id: Int64
    public var filename: String
    public var filePath: String
    public var durationSeconds: Double
    public var dateCreated: Date
    public var waveformData: Data?
    public var transcribedWithModel: String?
    public var transcriptionStatus: TranscriptionStatus
    public var customName: String?

    public init(id: Int64, filename: String, filePath: String, durationSeconds: Double,
                dateCreated: Date, waveformData: Data?, transcribedWithModel: String?,
                transcriptionStatus: TranscriptionStatus, customName: String? = nil) {
        self.id = id
        self.filename = filename
        self.filePath = filePath
        self.durationSeconds = durationSeconds
        self.dateCreated = dateCreated
        self.waveformData = waveformData
        self.transcribedWithModel = transcribedWithModel
        self.transcriptionStatus = transcriptionStatus
        self.customName = customName
    }

    public enum TranscriptionStatus: String, Codable {
        case pending
        case transcribing
        case complete
        case failed
    }

    public var displayName: String {
        if let name = customName, !name.isEmpty { return name }
        return "Recording \(id)"
    }

    public var dateFormatted: String {
        let cal = Calendar.current
        let day = cal.component(.day, from: dateCreated)
        let ordinal: String
        switch day % 10 {
        case 1 where day != 11: ordinal = "st"
        case 2 where day != 12: ordinal = "nd"
        case 3 where day != 13: ordinal = "rd"
        default: ordinal = "th"
        }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mma"
        let monthYearFmt = DateFormatter()
        monthYearFmt.dateFormat = "MMM yyyy"
        return "\(timeFmt.string(from: dateCreated)) \(day)\(ordinal) \(monthYearFmt.string(from: dateCreated))".uppercased()
    }

    public var durationFormatted: String {
        let minutes = Int(durationSeconds) / 60
        let seconds = Int(durationSeconds) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    public var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }
}
