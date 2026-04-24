import Foundation

public struct Bookmark: Identifiable {
    public let id: Int64
    public let recordingID: Int64
    public var time: Double
    public var label: String?

    public init(id: Int64, recordingID: Int64, time: Double, label: String? = nil) {
        self.id = id
        self.recordingID = recordingID
        self.time = time
        self.label = label
    }
}
