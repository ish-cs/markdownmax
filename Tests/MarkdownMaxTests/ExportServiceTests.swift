import XCTest
@testable import MarkdownMaxCore

final class ExportServiceTests: XCTestCase {
    var service: ExportService!
    var recording: Recording!
    var segments: [Transcript]!

    override func setUp() {
        service = ExportService()
        recording = Recording(
            id: 1,
            filename: "lecture_2026.wav",
            filePath: "/tmp/lecture_2026.wav",
            durationSeconds: 185.0,
            dateCreated: Date(timeIntervalSince1970: 1_700_000_000),
            waveformData: nil,
            transcribedWithModel: "medium",
            transcriptionStatus: .complete
        )
        segments = [
            Transcript(id: 1, recordingID: 1, text: "Hello everyone.", confidenceScore: 0.98, startTime: 0.0, endTime: 2.0),
            Transcript(id: 2, recordingID: 1, text: "Today we discuss Swift concurrency.", confidenceScore: 0.95, startTime: 2.0, endTime: 5.5),
            Transcript(id: 3, recordingID: 1, text: "Let's start with async/await.", confidenceScore: 0.92, startTime: 5.5, endTime: 9.0),
        ]
    }

    // MARK: - Markdown

    func testMarkdownContainsHeader() {
        let md = service.markdownContent(recording: recording, segments: segments)
        XCTAssertTrue(md.contains("# Transcript"), "Should have H1 header")
    }

    func testMarkdownContainsDuration() {
        let md = service.markdownContent(recording: recording, segments: segments)
        XCTAssertTrue(md.contains("3:05"), "185 seconds → 3:05")
    }

    func testMarkdownContainsModel() {
        let md = service.markdownContent(recording: recording, segments: segments)
        XCTAssertTrue(md.contains("medium"))
    }

    func testMarkdownContainsSegmentText() {
        let md = service.markdownContent(recording: recording, segments: segments)
        XCTAssertTrue(md.contains("Hello everyone."))
        XCTAssertTrue(md.contains("Today we discuss Swift concurrency."))
        XCTAssertTrue(md.contains("Let's start with async/await."))
    }

    func testMarkdownContainsTimestamps() {
        let md = service.markdownContent(recording: recording, segments: segments)
        XCTAssertTrue(md.contains("[0:00"), "Should include start timestamp")
    }

    func testMarkdownIsDivided() {
        let md = service.markdownContent(recording: recording, segments: segments)
        XCTAssertTrue(md.contains("---"), "Should have divider")
    }

    // MARK: - Plain text

    func testPlainTextContainsHeader() {
        let txt = service.plainTextContent(recording: recording, segments: segments)
        XCTAssertTrue(txt.contains("Transcript"))
        XCTAssertTrue(txt.contains("=========="))
    }

    func testPlainTextContainsSegments() {
        let txt = service.plainTextContent(recording: recording, segments: segments)
        XCTAssertTrue(txt.contains("Hello everyone."))
        XCTAssertTrue(txt.contains("async/await"))
    }

    func testPlainTextContainsDuration() {
        let txt = service.plainTextContent(recording: recording, segments: segments)
        XCTAssertTrue(txt.contains("3:05"))
    }

    // MARK: - Full text

    func testFullTextJoinsSegments() {
        let full = service.fullText(segments: segments)
        XCTAssertTrue(full.contains("Hello everyone."))
        XCTAssertTrue(full.contains("Swift concurrency"))
        XCTAssertTrue(full.contains("async/await"))
        // Should be space-joined, no timestamps
        XCTAssertFalse(full.contains("["))
    }

    func testFullTextEmptySegments() {
        let full = service.fullText(segments: [])
        XCTAssertEqual(full, "")
    }

    // MARK: - File writing

    func testSaveMarkdownToFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_export_\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = ExportDocument(recording: recording, segments: segments, format: .markdown)
        try service.save(document: doc, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("# Transcript"))
        XCTAssertTrue(content.contains("Hello everyone."))
    }

    func testSavePlainTextToFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_export_\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }

        let doc = ExportDocument(recording: recording, segments: segments, format: .plainText)
        try service.save(document: doc, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("Transcript"))
        XCTAssertTrue(content.contains("Hello everyone."))
    }

    // MARK: - Suggested filenames

    func testSuggestedMarkdownFilename() {
        let doc = ExportDocument(recording: recording, segments: segments, format: .markdown)
        XCTAssertEqual(doc.suggestedFilename, "lecture_2026.md")
    }

    func testSuggestedTextFilename() {
        let doc = ExportDocument(recording: recording, segments: segments, format: .plainText)
        XCTAssertEqual(doc.suggestedFilename, "lecture_2026.txt")
    }

    func testSuggestedPDFFilename() {
        let doc = ExportDocument(recording: recording, segments: segments, format: .pdf)
        XCTAssertEqual(doc.suggestedFilename, "lecture_2026.pdf")
    }
}
