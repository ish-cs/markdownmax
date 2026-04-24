import Foundation

public struct Transcript: Identifiable, Equatable {
    public let id: Int64
    public let recordingID: Int64
    public var text: String
    public var confidenceScore: Double?
    public var startTime: Double
    public var endTime: Double
    public init(id: Int64, recordingID: Int64, text: String, confidenceScore: Double?,
                startTime: Double, endTime: Double) {
        self.id = id
        self.recordingID = recordingID
        self.text = text
        self.confidenceScore = confidenceScore
        self.startTime = startTime
        self.endTime = endTime
    }

    public var timeRangeFormatted: String {
        "\(startTime.durationFormatted) → \(endTime.durationFormatted)"
    }
}

public struct TranscriptSegment: Equatable {
    public var text: String
    public var startTime: Double
    public var endTime: Double
    public var confidence: Double?

    public init(text: String, startTime: Double, endTime: Double, confidence: Double? = nil) {
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.confidence = confidence
    }
}
