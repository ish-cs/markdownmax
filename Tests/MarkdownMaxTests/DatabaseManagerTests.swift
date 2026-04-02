import XCTest
@testable import MarkdownMaxCore

final class DatabaseManagerTests: XCTestCase {
    var db: DatabaseManager!
    var tempURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownMaxTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempURL = dir.appendingPathComponent("test.sqlite")
        db = try DatabaseManager(url: tempURL)
    }

    override func tearDownWithError() throws {
        db = nil
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
    }

    // MARK: - Recordings

    func testInsertAndFetchRecording() throws {
        let id = try db.insertRecording(filename: "test.wav", filePath: "/tmp/test.wav", duration: 120.5)
        XCTAssertGreaterThan(id, 0)

        let recordings = try db.fetchAllRecordings()
        XCTAssertEqual(recordings.count, 1)
        let rec = recordings[0]
        XCTAssertEqual(rec.filename, "test.wav")
        XCTAssertEqual(rec.filePath, "/tmp/test.wav")
        XCTAssertEqual(rec.durationSeconds, 120.5, accuracy: 0.001)
        XCTAssertEqual(rec.transcriptionStatus, .pending)
    }

    func testInsertMultipleRecordings() throws {
        try db.insertRecording(filename: "a.wav", filePath: "/tmp/a.wav")
        try db.insertRecording(filename: "b.wav", filePath: "/tmp/b.wav")
        try db.insertRecording(filename: "c.wav", filePath: "/tmp/c.wav")

        let recordings = try db.fetchAllRecordings()
        XCTAssertEqual(recordings.count, 3)
    }

    func testUpdateRecordingStatus() throws {
        let id = try db.insertRecording(filename: "test.wav", filePath: "/tmp/test.wav")
        try db.updateRecordingStatus(id, status: .transcribing)

        var recordings = try db.fetchAllRecordings()
        XCTAssertEqual(recordings[0].transcriptionStatus, .transcribing)

        try db.updateRecordingStatus(id, status: .complete, model: "medium", duration: 300.0)
        recordings = try db.fetchAllRecordings()
        XCTAssertEqual(recordings[0].transcriptionStatus, .complete)
        XCTAssertEqual(recordings[0].transcribedWithModel, "medium")
        XCTAssertEqual(recordings[0].durationSeconds, 300.0, accuracy: 0.001)
    }

    func testDeleteRecording() throws {
        let id = try db.insertRecording(filename: "test.wav", filePath: "/tmp/test.wav")
        let seg = TranscriptSegment(text: "Hello world", startTime: 0, endTime: 5)
        try db.insertTranscripts([seg], forRecording: id)

        try db.deleteRecording(id)

        let recordings = try db.fetchAllRecordings()
        XCTAssertEqual(recordings.count, 0)

        // Transcripts should be cascade-deleted
        let transcripts = try db.fetchTranscripts(forRecording: id)
        XCTAssertEqual(transcripts.count, 0)
    }

    func testWaveformData() throws {
        let id = try db.insertRecording(filename: "test.wav", filePath: "/tmp/test.wav")
        let waveform = Data([0, 128, 255, 64, 200])
        try db.updateRecordingWaveform(id, waveformData: waveform)

        let recordings = try db.fetchAllRecordings()
        XCTAssertEqual(recordings[0].waveformData, waveform)
    }

    // MARK: - Transcripts

    func testInsertAndFetchTranscripts() throws {
        let id = try db.insertRecording(filename: "test.wav", filePath: "/tmp/test.wav")
        let segments = [
            TranscriptSegment(text: "Hello world", startTime: 0.0, endTime: 2.5),
            TranscriptSegment(text: "This is a test", startTime: 2.5, endTime: 5.0, confidence: 0.95),
        ]
        try db.insertTranscripts(segments, forRecording: id)

        let transcripts = try db.fetchTranscripts(forRecording: id)
        XCTAssertEqual(transcripts.count, 2)
        XCTAssertEqual(transcripts[0].text, "Hello world")
        XCTAssertEqual(transcripts[0].startTime, 0.0, accuracy: 0.001)
        XCTAssertEqual(transcripts[0].endTime, 2.5, accuracy: 0.001)
        XCTAssertEqual(transcripts[1].text, "This is a test")
        XCTAssertEqual(transcripts[1].confidenceScore ?? 0, 0.95, accuracy: 0.001)
    }

    func testTranscriptsOrderedByStartTime() throws {
        let id = try db.insertRecording(filename: "test.wav", filePath: "/tmp/test.wav")
        let segments = [
            TranscriptSegment(text: "Third", startTime: 10.0, endTime: 15.0),
            TranscriptSegment(text: "First", startTime: 0.0, endTime: 5.0),
            TranscriptSegment(text: "Second", startTime: 5.0, endTime: 10.0),
        ]
        try db.insertTranscripts(segments, forRecording: id)

        let transcripts = try db.fetchTranscripts(forRecording: id)
        XCTAssertEqual(transcripts[0].text, "First")
        XCTAssertEqual(transcripts[1].text, "Second")
        XCTAssertEqual(transcripts[2].text, "Third")
    }

    // MARK: - FTS5 Search

    func testFullTextSearch() throws {
        let id1 = try db.insertRecording(filename: "r1.wav", filePath: "/tmp/r1.wav")
        let id2 = try db.insertRecording(filename: "r2.wav", filePath: "/tmp/r2.wav")

        try db.insertTranscripts([TranscriptSegment(text: "The quick brown fox", startTime: 0, endTime: 3)], forRecording: id1)
        try db.insertTranscripts([TranscriptSegment(text: "Hello world today", startTime: 0, endTime: 3)], forRecording: id2)

        let results = try db.searchTranscripts(query: "quick")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].recordingID, id1)
        XCTAssertTrue(results[0].text.contains("quick"))
    }

    func testSearchReturnsMultipleResults() throws {
        let id = try db.insertRecording(filename: "r.wav", filePath: "/tmp/r.wav")
        try db.insertTranscripts([
            TranscriptSegment(text: "Meeting starts now", startTime: 0, endTime: 3),
            TranscriptSegment(text: "The meeting agenda is full", startTime: 3, endTime: 6),
        ], forRecording: id)

        let results = try db.searchTranscripts(query: "meeting")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchNoResults() throws {
        let id = try db.insertRecording(filename: "r.wav", filePath: "/tmp/r.wav")
        try db.insertTranscripts([TranscriptSegment(text: "Hello world", startTime: 0, endTime: 3)], forRecording: id)

        let results = try db.searchTranscripts(query: "xyzzy")
        XCTAssertEqual(results.count, 0)
    }

    func testSearchPrefixMatching() throws {
        let id = try db.insertRecording(filename: "r.wav", filePath: "/tmp/r.wav")
        try db.insertTranscripts([TranscriptSegment(text: "transcription is amazing", startTime: 0, endTime: 3)], forRecording: id)

        let results = try db.searchTranscripts(query: "trans")
        XCTAssertEqual(results.count, 1)
    }

    // MARK: - Models

    func testUpsertAndFetchModels() throws {
        let model = InstalledModel(id: 0, modelName: .medium, version: "1.0", filePath: "/models/medium",
                                   sizeMB: 1500, isActive: true, downloadedAt: Date())
        try db.upsertModel(model)

        let models = try db.fetchInstalledModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].modelName, .medium)
        XCTAssertEqual(models[0].sizeMB, 1500)
        XCTAssertTrue(models[0].isActive)
    }

    func testSetActiveModel() throws {
        let m1 = InstalledModel(id: 0, modelName: .tiny, version: nil, filePath: "/models/tiny", sizeMB: 39, isActive: true, downloadedAt: nil)
        let m2 = InstalledModel(id: 0, modelName: .medium, version: nil, filePath: "/models/medium", sizeMB: 1500, isActive: false, downloadedAt: nil)
        try db.upsertModel(m1)
        try db.upsertModel(m2)

        try db.setActiveModel(.medium)

        let models = try db.fetchInstalledModels()
        let tiny = models.first { $0.modelName == .tiny }!
        let medium = models.first { $0.modelName == .medium }!
        XCTAssertFalse(tiny.isActive)
        XCTAssertTrue(medium.isActive)
    }

    func testDeleteModel() throws {
        let model = InstalledModel(id: 0, modelName: .small, version: nil, filePath: "/models/small", sizeMB: 244, isActive: false, downloadedAt: nil)
        try db.upsertModel(model)
        XCTAssertEqual((try db.fetchInstalledModels()).count, 1)

        db.deleteModel(.small)
        XCTAssertEqual((try db.fetchInstalledModels()).count, 0)
    }

    func testUpsertUpdatesExisting() throws {
        var model = InstalledModel(id: 0, modelName: .medium, version: "1.0", filePath: "/models/medium", sizeMB: 1500, isActive: false, downloadedAt: nil)
        try db.upsertModel(model)

        model = InstalledModel(id: 0, modelName: .medium, version: "2.0", filePath: "/models/medium-v2", sizeMB: 1600, isActive: true, downloadedAt: nil)
        try db.upsertModel(model)

        let models = try db.fetchInstalledModels()
        XCTAssertEqual(models.count, 1)
        XCTAssertEqual(models[0].version, "2.0")
        XCTAssertEqual(models[0].filePath, "/models/medium-v2")
    }
}
