import Foundation
import SQLite3

// SQLITE_TRANSIENT is not bridged cleanly to Swift in all SDK versions
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case insertFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg):    return "DB open failed: \(msg)"
        case .prepareFailed(let msg): return "DB prepare failed: \(msg)"
        case .stepFailed(let msg):    return "DB step failed: \(msg)"
        case .insertFailed(let msg):  return "DB insert failed: \(msg)"
        }
    }
}

public final class DatabaseManager {
    private var db: OpaquePointer?
    private let dbURL: URL

    public init(url: URL? = nil) throws {
        if let url {
            dbURL = url
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("StudentMax", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            dbURL = support.appendingPathComponent("database.sqlite")
        }
        try open()
        try createSchema()
        migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    private func open() throws {
        let path = dbURL.path
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw DatabaseError.openFailed(msg)
        }
        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA foreign_keys=ON")
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        var err: UnsafeMutablePointer<CChar>? = nil
        defer { sqlite3_free(err) }
        return sqlite3_exec(db, sql, nil, nil, &err) == SQLITE_OK
    }

    private func createSchema() throws {
        let schema = """
        CREATE TABLE IF NOT EXISTS installed_models (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            model_name TEXT NOT NULL UNIQUE,
            version TEXT,
            file_path TEXT NOT NULL,
            size_mb INTEGER,
            is_active INTEGER DEFAULT 0,
            downloaded_at TEXT,
            last_used TEXT
        );

        CREATE TABLE IF NOT EXISTS recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filename TEXT NOT NULL,
            file_path TEXT NOT NULL,
            duration_seconds REAL DEFAULT 0,
            date_created TEXT NOT NULL,
            waveform_data BLOB,
            transcribed_with_model TEXT,
            transcription_status TEXT DEFAULT 'pending',
            custom_name TEXT
        );

        CREATE TABLE IF NOT EXISTS transcripts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recording_id INTEGER NOT NULL,
            text TEXT NOT NULL,
            confidence_score REAL,
            start_time REAL DEFAULT 0,
            end_time REAL DEFAULT 0,
            FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS bookmarks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recording_id INTEGER NOT NULL,
            time REAL NOT NULL,
            label TEXT,
            FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
        );

        CREATE VIRTUAL TABLE IF NOT EXISTS transcript_search USING fts5(
            text,
            recording_id UNINDEXED,
            content=transcripts,
            content_rowid=id
        );

        CREATE TRIGGER IF NOT EXISTS transcripts_ai AFTER INSERT ON transcripts BEGIN
            INSERT INTO transcript_search(rowid, text, recording_id)
            VALUES (new.id, new.text, new.recording_id);
        END;

        CREATE TRIGGER IF NOT EXISTS transcripts_ad AFTER DELETE ON transcripts BEGIN
            INSERT INTO transcript_search(transcript_search, rowid, text, recording_id)
            VALUES ('delete', old.id, old.text, old.recording_id);
        END;

        CREATE TRIGGER IF NOT EXISTS transcripts_au AFTER UPDATE ON transcripts BEGIN
            INSERT INTO transcript_search(transcript_search, rowid, text, recording_id)
            VALUES ('delete', old.id, old.text, old.recording_id);
            INSERT INTO transcript_search(rowid, text, recording_id)
            VALUES (new.id, new.text, new.recording_id);
        END;
        """
        guard execute(schema) else {
            throw DatabaseError.prepareFailed("Schema creation failed")
        }
    }

    private func migrate() {
        // No-op if columns/tables already exist
        execute("ALTER TABLE recordings ADD COLUMN custom_name TEXT")
        execute("ALTER TABLE recordings ADD COLUMN subject TEXT")
        execute("""
            CREATE TABLE IF NOT EXISTS bookmarks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                recording_id INTEGER NOT NULL,
                time REAL NOT NULL,
                label TEXT,
                FOREIGN KEY (recording_id) REFERENCES recordings(id) ON DELETE CASCADE
            )
        """)
    }

    // MARK: - Recordings

    @discardableResult
    public func insertRecording(filename: String, filePath: String, duration: Double = 0) throws -> Int64 {
        let sql = """
        INSERT INTO recordings (filename, file_path, duration_seconds, date_created, transcription_status)
        VALUES (?, ?, ?, ?, 'pending')
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_text(stmt, 1, filename, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, filePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, duration)
        sqlite3_bind_text(stmt, 4, iso8601(Date()), -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed(dbError())
        }
        return sqlite3_last_insert_rowid(db)
    }

    public func updateRecordingStatus(_ id: Int64, status: Recording.TranscriptionStatus,
                                      model: String? = nil, duration: Double? = nil) throws {
        var sql = "UPDATE recordings SET transcription_status = ?"
        var bindings: [Any] = [status.rawValue]
        if let m = model    { sql += ", transcribed_with_model = ?"; bindings.append(m) }
        if let d = duration { sql += ", duration_seconds = ?"; bindings.append(d) }
        sql += " WHERE id = ?"
        bindings.append(id)

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        for (i, val) in bindings.enumerated() {
            bind(stmt, index: Int32(i + 1), value: val)
        }
        sqlite3_step(stmt)
    }

    public func updateRecordingWaveform(_ id: Int64, waveformData: Data) throws {
        let sql = "UPDATE recordings SET waveform_data = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        waveformData.withUnsafeBytes { ptr in
            sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(waveformData.count), SQLITE_TRANSIENT)
        }
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    public func fetchAllRecordings() throws -> [Recording] {
        let sql = """
        SELECT id, filename, file_path, duration_seconds, date_created,
               waveform_data, transcribed_with_model, transcription_status, custom_name, subject
        FROM recordings ORDER BY date_created DESC
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        var results: [Recording] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(recordingFromStmt(stmt))
        }
        return results
    }

    /// Returns the single recording created today (local calendar day), if any.
    public func fetchTodaysRecording() -> Recording? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let sql = """
        SELECT id, filename, file_path, duration_seconds, date_created,
               waveform_data, transcribed_with_model, transcription_status, custom_name, subject
        FROM recordings
        WHERE date_created >= ? AND date_created < ?
        ORDER BY date_created ASC
        LIMIT 1
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, iso8601(start), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, iso8601(end), -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW ? recordingFromStmt(stmt) : nil
    }

    public func deleteRecording(_ id: Int64) throws {
        execute("DELETE FROM transcripts WHERE recording_id = \(id)")
        execute("DELETE FROM recordings WHERE id = \(id)")
    }

    /// Deletes all recordings created before `date`. Returns file paths of deleted audio files.
    @discardableResult
    public func deleteRecordingsOlderThan(_ date: Date) throws -> [String] {
        let sql = "SELECT id, file_path FROM recordings WHERE date_created < ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_text(stmt, 1, iso8601(date), -1, SQLITE_TRANSIENT)

        var rows: [(id: Int64, path: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let path = String(cString: sqlite3_column_text(stmt, 1))
            rows.append((id: id, path: path))
        }

        for row in rows {
            execute("DELETE FROM recordings WHERE id = \(row.id)")
            // transcripts cascade-delete via FK ON DELETE CASCADE
        }
        return rows.map(\.path)
    }

    public func deleteTranscripts(forRecording id: Int64) {
        execute("DELETE FROM transcripts WHERE recording_id = \(id)")
        execute("DELETE FROM transcript_search WHERE recording_id = \(id)")
    }

    public func deleteTranscripts(forRecording id: Int64, startingFrom startTime: Double) {
        execute("DELETE FROM transcripts WHERE recording_id = \(id) AND start_time >= \(startTime)")
        execute("DELETE FROM transcript_search WHERE recording_id = \(id) AND start_time >= \(startTime)")
    }

    public func countTranscripts(forRecording id: Int64) -> Int {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM transcripts WHERE recording_id = \(id)", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    public func renameRecording(_ id: Int64, name: String) throws {
        let sql = "UPDATE recordings SET custom_name = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    // MARK: - Transcripts

    public func insertTranscripts(_ segments: [TranscriptSegment], forRecording recordingID: Int64) throws {
        execute("BEGIN TRANSACTION")
        let sql = "INSERT INTO transcripts (recording_id, text, confidence_score, start_time, end_time) VALUES (?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            execute("ROLLBACK")
            throw DatabaseError.prepareFailed(dbError())
        }
        for seg in segments {
            sqlite3_reset(stmt)
            sqlite3_bind_int64(stmt, 1, recordingID)
            sqlite3_bind_text(stmt, 2, seg.text, -1, SQLITE_TRANSIENT)
            if let c = seg.confidence { sqlite3_bind_double(stmt, 3, c) } else { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_double(stmt, 4, seg.startTime)
            sqlite3_bind_double(stmt, 5, seg.endTime)
            if sqlite3_step(stmt) != SQLITE_DONE {
                execute("ROLLBACK")
                throw DatabaseError.insertFailed(dbError())
            }
        }
        execute("COMMIT")
    }

    public func fetchTranscripts(forRecording id: Int64) throws -> [Transcript] {
        let sql = """
        SELECT id, recording_id, text, confidence_score, start_time, end_time
        FROM transcripts WHERE recording_id = ? ORDER BY start_time
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_int64(stmt, 1, id)
        var results: [Transcript] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(transcriptFromStmt(stmt))
        }
        return results
    }

    public func searchTranscripts(query: String) throws -> [(recordingID: Int64, text: String, startTime: Double)] {
        let sql = """
        SELECT t.recording_id, t.text, t.start_time
        FROM transcript_search ts
        JOIN transcripts t ON ts.rowid = t.id
        WHERE transcript_search MATCH ?
        ORDER BY rank
        LIMIT 200
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_text(stmt, 1, query + "*", -1, SQLITE_TRANSIENT)
        var results: [(recordingID: Int64, text: String, startTime: Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rid = sqlite3_column_int64(stmt, 0)
            let text = String(cString: sqlite3_column_text(stmt, 1))
            let st = sqlite3_column_double(stmt, 2)
            results.append((recordingID: rid, text: text, startTime: st))
        }
        return results
    }

    // MARK: - Subject

    public func updateRecordingSubject(_ id: Int64, subject: String?) throws {
        let sql = "UPDATE recordings SET subject = ? WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        if let s = subject { sqlite3_bind_text(stmt, 1, s, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 1) }
        sqlite3_bind_int64(stmt, 2, id)
        sqlite3_step(stmt)
    }

    // MARK: - Bookmarks

    @discardableResult
    public func insertBookmark(recordingID: Int64, time: Double, label: String? = nil) throws -> Int64 {
        let sql = "INSERT INTO bookmarks (recording_id, time, label) VALUES (?, ?, ?)"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_int64(stmt, 1, recordingID)
        sqlite3_bind_double(stmt, 2, time)
        if let l = label { sqlite3_bind_text(stmt, 3, l, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 3) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw DatabaseError.insertFailed(dbError()) }
        return sqlite3_last_insert_rowid(db)
    }

    public func fetchBookmarks(forRecording id: Int64) throws -> [Bookmark] {
        let sql = "SELECT id, recording_id, time, label FROM bookmarks WHERE recording_id = ? ORDER BY time"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_int64(stmt, 1, id)
        var results: [Bookmark] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bId = sqlite3_column_int64(stmt, 0)
            let rId = sqlite3_column_int64(stmt, 1)
            let time = sqlite3_column_double(stmt, 2)
            let label = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 3)) : nil
            results.append(Bookmark(id: bId, recordingID: rId, time: time, label: label))
        }
        return results
    }

    public func deleteBookmark(_ id: Int64) {
        execute("DELETE FROM bookmarks WHERE id = \(id)")
    }

    // MARK: - Models

    public func upsertModel(_ model: InstalledModel) throws {
        let sql = """
        INSERT INTO installed_models (model_name, version, file_path, size_mb, is_active, downloaded_at)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(model_name) DO UPDATE SET
            version=excluded.version, file_path=excluded.file_path,
            size_mb=excluded.size_mb, is_active=excluded.is_active,
            downloaded_at=excluded.downloaded_at
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        sqlite3_bind_text(stmt, 1, model.modelName.rawValue, -1, SQLITE_TRANSIENT)
        if let v = model.version { sqlite3_bind_text(stmt, 2, v, -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 2) }
        sqlite3_bind_text(stmt, 3, model.filePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 4, Int32(model.sizeMB))
        sqlite3_bind_int(stmt, 5, model.isActive ? 1 : 0)
        if let d = model.downloadedAt { sqlite3_bind_text(stmt, 6, iso8601(d), -1, SQLITE_TRANSIENT) } else { sqlite3_bind_null(stmt, 6) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.insertFailed(dbError())
        }
    }

    public func setActiveModel(_ name: WhisperModelSize) throws {
        execute("UPDATE installed_models SET is_active = 0")
        let sql = "UPDATE installed_models SET is_active = 1, last_used = ? WHERE model_name = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, iso8601(Date()), -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, name.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    public func fetchInstalledModels() throws -> [InstalledModel] {
        let sql = "SELECT id, model_name, version, file_path, size_mb, is_active, downloaded_at, last_used FROM installed_models"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw DatabaseError.prepareFailed(dbError())
        }
        var results: [InstalledModel] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let name = String(cString: sqlite3_column_text(stmt, 1))
            guard let size = WhisperModelSize(rawValue: name) else { continue }
            let version = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 2)) : nil
            let path = String(cString: sqlite3_column_text(stmt, 3))
            let mb = Int(sqlite3_column_int(stmt, 4))
            let active = sqlite3_column_int(stmt, 5) != 0
            let dlAt = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? parseDate(String(cString: sqlite3_column_text(stmt, 6))) : nil
            let lastUsed = sqlite3_column_type(stmt, 7) != SQLITE_NULL ? parseDate(String(cString: sqlite3_column_text(stmt, 7))) : nil
            results.append(InstalledModel(id: id, modelName: size, version: version, filePath: path,
                                          sizeMB: mb, isActive: active, downloadedAt: dlAt, lastUsed: lastUsed))
        }
        return results
    }

    public func deleteModel(_ name: WhisperModelSize) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "DELETE FROM installed_models WHERE model_name = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, name.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
    }

    // MARK: - Helpers

    private func recordingFromStmt(_ stmt: OpaquePointer?) -> Recording {
        let id = sqlite3_column_int64(stmt, 0)
        let filename = String(cString: sqlite3_column_text(stmt, 1))
        let path = String(cString: sqlite3_column_text(stmt, 2))
        let duration = sqlite3_column_double(stmt, 3)
        let dateStr = String(cString: sqlite3_column_text(stmt, 4))
        let date = parseDate(dateStr) ?? Date()
        var waveform: Data? = nil
        if sqlite3_column_type(stmt, 5) != SQLITE_NULL {
            let bytes = sqlite3_column_bytes(stmt, 5)
            if let ptr = sqlite3_column_blob(stmt, 5) {
                waveform = Data(bytes: ptr, count: Int(bytes))
            }
        }
        let model = sqlite3_column_type(stmt, 6) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 6)) : nil
        let statusStr = String(cString: sqlite3_column_text(stmt, 7))
        let status = Recording.TranscriptionStatus(rawValue: statusStr) ?? .pending
        let customName = sqlite3_column_type(stmt, 8) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 8)) : nil
        let subject = sqlite3_column_type(stmt, 9) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 9)) : nil
        return Recording(id: id, filename: filename, filePath: path, durationSeconds: duration,
                         dateCreated: date, waveformData: waveform, transcribedWithModel: model,
                         transcriptionStatus: status, customName: customName, subject: subject)
    }

    private func transcriptFromStmt(_ stmt: OpaquePointer?) -> Transcript {
        let id = sqlite3_column_int64(stmt, 0)
        let rid = sqlite3_column_int64(stmt, 1)
        let text = String(cString: sqlite3_column_text(stmt, 2))
        let conf = sqlite3_column_type(stmt, 3) != SQLITE_NULL ? sqlite3_column_double(stmt, 3) : nil as Double?
        let start = sqlite3_column_double(stmt, 4)
        let end = sqlite3_column_double(stmt, 5)
        return Transcript(id: id, recordingID: rid, text: text, confidenceScore: conf,
                          startTime: start, endTime: end)
    }

    private func bind(_ stmt: OpaquePointer?, index: Int32, value: Any) {
        switch value {
        case let s as String: sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
        case let d as Double: sqlite3_bind_double(stmt, index, d)
        case let i as Int:    sqlite3_bind_int64(stmt, index, Int64(i))
        case let i as Int64:  sqlite3_bind_int64(stmt, index, i)
        default: sqlite3_bind_null(stmt, index)
        }
    }

    private func dbError() -> String {
        String(cString: sqlite3_errmsg(db))
    }

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func iso8601(_ date: Date) -> String { iso.string(from: date) }
    private func parseDate(_ s: String) -> Date? { iso.date(from: s) }
}
