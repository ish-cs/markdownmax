import XCTest
@testable import MarkdownMaxCore

final class RecordingModelTests: XCTestCase {

    func testDurationFormatted() {
        let rec = makeRecording(duration: 185.0)
        XCTAssertEqual(rec.durationFormatted, "3:05")
    }

    func testDurationFormattedZero() {
        let rec = makeRecording(duration: 0)
        XCTAssertEqual(rec.durationFormatted, "0:00")
    }

    func testDurationFormattedSeconds() {
        let rec = makeRecording(duration: 45)
        XCTAssertEqual(rec.durationFormatted, "0:45")
    }

    func testFileURL() {
        let rec = makeRecording(duration: 10)
        XCTAssertEqual(rec.fileURL.path, "/tmp/test.wav")
    }

    private func makeRecording(duration: Double) -> Recording {
        Recording(id: 1, filename: "test.wav", filePath: "/tmp/test.wav",
                  durationSeconds: duration, dateCreated: Date(),
                  waveformData: nil, transcribedWithModel: nil,
                  transcriptionStatus: .pending)
    }
}

final class TranscriptModelTests: XCTestCase {

    func testTimeRangeFormatted() {
        let t = Transcript(id: 1, recordingID: 1, text: "Hello",
                           confidenceScore: nil, startTime: 65.0, endTime: 70.5)
        XCTAssertEqual(t.timeRangeFormatted, "1:05 → 1:10")
    }

    func testTimeRangeZero() {
        let t = Transcript(id: 1, recordingID: 1, text: "Start",
                           confidenceScore: nil, startTime: 0, endTime: 5)
        XCTAssertEqual(t.timeRangeFormatted, "0:00 → 0:05")
    }
}

final class WhisperModelSizeTests: XCTestCase {

    func testAllCasesExist() {
        XCTAssertEqual(WhisperModelSize.allCases.count, 4)
    }

    func testSizeMBValues() {
        XCTAssertEqual(WhisperModelSize.tiny.sizeMB, 39)
        XCTAssertEqual(WhisperModelSize.small.sizeMB, 244)
        XCTAssertEqual(WhisperModelSize.medium.sizeMB, 1500)
        XCTAssertEqual(WhisperModelSize.large.sizeMB, 3000)
    }

    func testWhisperKitNames() {
        XCTAssertEqual(WhisperModelSize.tiny.whisperKitName, "openai_whisper-tiny")
        XCTAssertEqual(WhisperModelSize.large.whisperKitName, "openai_whisper-large-v3")
    }

    func testSizeFormatted() {
        let model = InstalledModel(id: 1, modelName: .medium, version: nil, filePath: "/models/medium",
                                   sizeMB: 1500, isActive: false, downloadedAt: nil, lastUsed: nil)
        XCTAssertEqual(model.sizeFormatted, "1.5 GB")
    }

    func testSizeFormattedMB() {
        let model = InstalledModel(id: 1, modelName: .tiny, version: nil, filePath: "/models/tiny",
                                   sizeMB: 39, isActive: false, downloadedAt: nil, lastUsed: nil)
        XCTAssertEqual(model.sizeFormatted, "39 MB")
    }
}
