import Foundation
import Combine
import SwiftUI
import UserNotifications
import MarkdownMaxCore

@MainActor
final class AppState: ObservableObject {
    // MARK: - Published state
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var installedModels: [InstalledModel] = []
    @Published var selectedRecording: Recording?
    @Published var transcriptSegments: [Transcript] = []
    @Published var searchQuery: String = ""
    @Published var searchResults: [(recordingID: Int64, text: String, startTime: Double)] = []
    @Published var showOnboarding: Bool = false
    @Published var showTranscriptWindow: Bool = false
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false
    @Published var showTimestamps: Bool = true
    @Published private(set) var currentRecordingID: Int64?
    /// Set briefly after a recording finishes so the UI can navigate to it.
    @Published var lastFinishedRecordingID: Int64?
    /// The currently selected transcription model (nil = auto / best available).
    @Published var selectedModelName: WhisperModelSize?
    /// Ghost mode: hides the recording timer from the menu bar status item.
    @Published var ghostMode: Bool = UserDefaults.standard.bool(forKey: "ghostMode")
    /// Bookmarks for the currently viewed recording.
    @Published var bookmarks: [Bookmark] = []
    /// Subject tag filter for the sidebar (nil = show all).
    @Published var subjectFilter: String? = nil

    // MARK: - Services
    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let modelDownloadManager = ModelDownloadManager()
    let exportService = ExportService()
    var db: DatabaseManager?
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        if let raw = UserDefaults.standard.string(forKey: "selectedModelName"),
           let model = WhisperModelSize(rawValue: raw) {
            selectedModelName = model
        }

        do {
            db = try DatabaseManager()
        } catch {
            appLog("Database init failed: \(error.localizedDescription)", .error)
        }

        audioRecorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        transcriptionService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        modelDownloadManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        $selectedModelName
            .dropFirst()
            .sink { name in UserDefaults.standard.set(name?.rawValue, forKey: "selectedModelName") }
            .store(in: &cancellables)

        $ghostMode
            .dropFirst()
            .sink { val in UserDefaults.standard.set(val, forKey: "ghostMode") }
            .store(in: &cancellables)

        Task { await bootstrap() }
    }

    private func bootstrap() async {
        await loadRecordings()
        await loadInstalledModels()
        await repairInstalledModelPathsIfNeeded()
        await autoDiscoverModels()
        showOnboarding = installedModels.isEmpty
        setupNotificationObservers()
        appLog("App started. \(recordings.count) recording(s), \(installedModels.count) model(s).")

        Task {
            try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }

        // Auto-transcribe any recordings that were left pending (e.g. app quit mid-recording)
        let pending = recordings.filter { $0.transcriptionStatus == .pending }
        if !pending.isEmpty {
            Task {
                for r in pending {
                    await transcribeRecording(id: r.id, url: URL(fileURLWithPath: r.filePath))
                }
            }
        }
    }

    private func repairInstalledModelPathsIfNeeded() async {
        guard let db else { return }
        var changed = false
        for m in installedModels {
            let storedMel = URL(fileURLWithPath: m.filePath).appendingPathComponent("MelSpectrogram.mlmodelc")
            if FileManager.default.fileExists(atPath: storedMel.path) { continue }
            let fixed = modelDownloadManager.resolvedModelFolder(for: m.modelName)
            let fixedMel = fixed.appendingPathComponent("MelSpectrogram.mlmodelc")
            guard FileManager.default.fileExists(atPath: fixedMel.path) else { continue }
            var updated = m
            updated.filePath = fixed.path
            try? db.upsertModel(updated)
            changed = true
        }
        if changed { await loadInstalledModels() }
    }

    private func autoDiscoverModels() async {
        guard let db else { return }
        let known = Set(installedModels.map(\.modelName))
        var found = false
        for model in WhisperModelSize.allCases where !known.contains(model) {
            let folder = modelDownloadManager.resolvedModelFolder(for: model)
            let mel = folder.appendingPathComponent("MelSpectrogram.mlmodelc")
            guard FileManager.default.fileExists(atPath: mel.path) else { continue }
            let installed = InstalledModel(
                id: 0, modelName: model, version: nil,
                filePath: folder.path, sizeMB: model.sizeMB,
                isActive: false, downloadedAt: nil
            )
            try? db.upsertModel(installed)
            appLog("Auto-discovered model: \(model.rawValue)")
            found = true
        }
        if found { await loadInstalledModels() }
    }

    private func setupNotificationObservers() {
        // No notification-based shortcuts — handled directly in AppDelegate via KeyboardShortcuts.
    }

    // MARK: - Active model

    /// The model to use for transcription. Falls back to best installed if no selection.
    var activeModel: InstalledModel? {
        if let name = selectedModelName,
           let m = installedModels.first(where: { $0.modelName == name }) {
            return m
        }
        let order: [WhisperModelSize] = [.largeV3Turbo, .distilLargeV3, .large, .medium, .small, .tiny]
        return order.compactMap { sz in installedModels.first { $0.modelName == sz } }.first
    }

    // MARK: - Recording

    func startRecording() {
        Task {
            guard let db else { return }
            do {
                let url = try await audioRecorder.startRecording()
                let id = try db.insertRecording(
                    filename: url.lastPathComponent,
                    filePath: url.path,
                    duration: 0
                )
                currentRecordingID = id
                await loadRecordings()
                appLog("Recording started: ID \(id)")
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    func pauseRecording() {
        audioRecorder.pauseRecording()
    }

    func resumeRecording() {
        audioRecorder.resumeRecording()
    }

    func stopRecording() {
        Task {
            guard let id = currentRecordingID, let db else { return }
            do {
                let result = try audioRecorder.stopRecording()
                try db.updateRecordingWaveform(id, waveformData: result.waveform)
                try db.updateRecordingStatus(id, status: .pending, model: nil, duration: result.duration)
                currentRecordingID = nil
                await loadRecordings()
                lastFinishedRecordingID = id
                appLog("Recording stopped: ID \(id), \(String(format: "%.0f", result.duration))s")
                await transcribeRecording(id: id, url: result.url)
            } catch {
                currentRecordingID = nil
                presentAlert(error.localizedDescription)
            }
        }
    }

    /// Best-effort save when app quits during recording (no transcription).
    func shutdownIfRecording() async {
        guard audioRecorder.isRecording, let id = currentRecordingID, let db else { return }
        do {
            let result = try audioRecorder.stopRecording()
            try? db.updateRecordingWaveform(id, waveformData: result.waveform)
            try? db.updateRecordingStatus(id, status: .pending, model: nil, duration: result.duration)
            currentRecordingID = nil
            appLog("Shutdown: saved recording \(id) as pending for later transcription.")
        } catch {}
    }

    // MARK: - Recordings

    func loadRecordings() async {
        guard let db else { return }
        do {
            let all = try db.fetchAllRecordings()
            for recording in all
                where recording.id != currentRecordingID
                   && !FileManager.default.fileExists(atPath: recording.filePath) {
                try? db.deleteRecording(recording.id)
                appLog("Removed orphaned recording from DB: \(recording.displayName)")
            }
            recordings = try db.fetchAllRecordings()
        } catch {
            presentAlert(error.localizedDescription)
        }
    }

    func loadInstalledModels() async {
        guard let db else { return }
        do {
            installedModels = try db.fetchInstalledModels()
        } catch {
            presentAlert(error.localizedDescription)
        }
    }

    // MARK: - Transcript loading

    func loadTranscript(for recording: Recording) {
        selectedRecording = recording
        guard let db else { return }
        transcriptSegments = (try? db.fetchTranscripts(forRecording: recording.id)) ?? []
        bookmarks = (try? db.fetchBookmarks(forRecording: recording.id)) ?? []
        showTranscriptWindow = true
    }

    // MARK: - Search

    func performSearch() {
        searchTask?.cancel()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let db else { searchResults = []; return }
        searchTask = Task {
            do {
                let results = try db.searchTranscripts(query: q)
                if !Task.isCancelled { searchResults = results }
            } catch {
                searchResults = []
            }
        }
    }

    // MARK: - Model management

    func downloadModel(_ model: WhisperModelSize) {
        Task {
            do {
                let folder = try await modelDownloadManager.downloadModel(model)
                let installed = InstalledModel(
                    id: 0, modelName: model, version: nil,
                    filePath: folder.path, sizeMB: model.sizeMB,
                    isActive: false, downloadedAt: Date()
                )
                try? db?.upsertModel(installed)
                await loadInstalledModels()
                showOnboarding = false
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    func deleteModel(_ model: WhisperModelSize) {
        Task {
            do {
                if let row = installedModels.first(where: { $0.modelName == model }) {
                    try modelDownloadManager.deleteDownloadedModel(folderPath: row.filePath, model: model)
                }
                db?.deleteModel(model)
                transcriptionService.unloadModel()
                modelDownloadManager.removeDownloadState(for: model)
                await loadInstalledModels()
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    // MARK: - Retranscribe

    func retranscribeRecording(_ recording: Recording) {
        Task {
            guard let db else { return }
            appLog("Retranscribing: \(recording.displayName)")
            try? db.deleteTranscripts(forRecording: recording.id)
            try? db.updateRecordingStatus(recording.id, status: .pending)
            if selectedRecording?.id == recording.id { transcriptSegments = [] }
            await loadRecordings()
            await transcribeRecording(id: recording.id, url: URL(fileURLWithPath: recording.filePath))
        }
    }

    func transcribeRecording(id: Int64, url: URL) async {
        guard let db else { return }
        guard let model = activeModel else {
            appLog("Transcription skipped: no model installed.", .warning)
            try? db.updateRecordingStatus(id, status: .failed)
            presentAlert("No model installed. Download one in Settings → Models.")
            await loadRecordings()
            return
        }

        do {
            appLog("Transcribing with '\(model.modelName.rawValue)'…")
            try? db.updateRecordingStatus(id, status: .transcribing)
            await loadRecordings()

            try await transcriptionService.loadModel(model.filePath, modelName: model.modelName.rawValue)
            let duration = recordings.first(where: { $0.id == id })?.durationSeconds
            let segments = try await transcriptionService.transcribe(audioURL: url, audioDuration: duration)
            appLog("Transcription complete: \(segments.count) segment(s).")

            try db.insertTranscripts(segments, forRecording: id)
            try db.updateRecordingStatus(id, status: .complete,
                                         model: model.modelName.rawValue,
                                         duration: nil)
            await loadRecordings()
            let recName = recordings.first(where: { $0.id == id })?.displayName ?? "Recording"
            sendTranscriptionNotification(name: recName)
            if selectedRecording?.id == id,
               let recording = recordings.first(where: { $0.id == id }) {
                loadTranscript(for: recording)
            }
        } catch {
            appLog("Transcription failed: \(error.localizedDescription)", .error)
            try? db.updateRecordingStatus(id, status: .failed)
            await loadRecordings()
            presentAlert("Transcription failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Merge

    func mergeRecordings(_ ids: Set<Int64>) {
        Task {
            guard let db, ids.count >= 2 else { return }

            // Sort oldest → newest
            let sorted = recordings
                .filter { ids.contains($0.id) }
                .sorted { $0.dateCreated < $1.dateCreated }
            guard sorted.count >= 2 else { return }

            let keeper = sorted[0]
            let masterURL = URL(fileURLWithPath: keeper.filePath)

            for rec in sorted.dropFirst() {
                // Use the exact WAV sample-count duration as the transcript offset so that
                // click-to-seek and active-segment highlighting stay in sync after merging.
                let offset = wavAudioDurationSeconds(at: masterURL) ?? keeper.durationSeconds

                // Shift and copy transcripts into keeper
                let segs = (try? db.fetchTranscripts(forRecording: rec.id)) ?? []
                if !segs.isEmpty {
                    let shifted = segs.map {
                        TranscriptSegment(
                            text: $0.text,
                            startTime: $0.startTime + offset,
                            endTime: $0.endTime + offset,
                            confidence: $0.confidenceScore
                        )
                    }
                    try? db.insertTranscripts(shifted, forRecording: keeper.id)
                }

                // Append audio then delete the source
                let srcURL = URL(fileURLWithPath: rec.filePath)
                if FileManager.default.fileExists(atPath: srcURL.path) {
                    appendWAV(from: srcURL, to: masterURL)
                    try? FileManager.default.removeItem(at: srcURL)
                }

                try? db.deleteRecording(rec.id)
            }

            // Store the exact merged duration from the WAV file's sample count, not wall-clock time.
            let mergedDuration = wavAudioDurationSeconds(at: masterURL)
                ?? sorted.reduce(0) { $0 + $1.durationSeconds }

            // Determine merged status
            let allComplete = sorted.allSatisfy { $0.transcriptionStatus == .complete }
            let status: Recording.TranscriptionStatus = allComplete ? .complete : .pending
            try? db.updateRecordingStatus(keeper.id, status: status,
                                          model: keeper.transcribedWithModel,
                                          duration: mergedDuration)
            await loadRecordings()
            if let merged = recordings.first(where: { $0.id == keeper.id }) {
                loadTranscript(for: merged)
                lastFinishedRecordingID = merged.id
            }
            appLog("Merged \(sorted.count) recordings into ID \(keeper.id), total \(String(format: "%.1f", mergedDuration))s")
        }
    }

    // MARK: - Rename

    func renameRecording(_ recording: Recording, name: String) {
        Task {
            do {
                try db?.renameRecording(recording.id, name: name)
                await loadRecordings()
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    // MARK: - Deletion

    func deleteRecording(_ recording: Recording) {
        Task {
            do {
                appLog("Deleting recording: \(recording.displayName)")
                let url = URL(fileURLWithPath: recording.filePath)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                try db?.deleteRecording(recording.id)
                await loadRecordings()
            } catch {
                appLog("Failed to delete: \(error.localizedDescription)", .error)
                presentAlert(error.localizedDescription)
            }
        }
    }

    func deleteRecordingsOlderThan(days: Int) {
        Task {
            guard let db else { return }
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            do {
                let paths = try db.deleteRecordingsOlderThan(cutoff)
                for path in paths {
                    try? FileManager.default.removeItem(atPath: path)
                }
                appLog("Deleted \(paths.count) recording(s) older than \(days) day(s).")
                await loadRecordings()
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    // MARK: - Export

    func exportTranscript(recording: Recording, format: ExportFormat) {
        Task {
            guard let db else { return }
            do {
                let segments = try db.fetchTranscripts(forRecording: recording.id)
                let doc = ExportDocument(recording: recording, segments: segments, format: format)
                if let url = await exportService.showSavePanel(suggestedName: doc.suggestedFilename, format: format) {
                    try exportService.save(document: doc, to: url)
                }
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    // MARK: - Bookmarks

    func addBookmark() {
        guard let id = currentRecordingID, let db else { return }
        let time = audioRecorder.duration
        Task {
            do {
                try db.insertBookmark(recordingID: id, time: time)
                appLog("Bookmark added at \(time.durationFormatted)")
            } catch {
                appLog("Bookmark insert failed: \(error.localizedDescription)", .error)
            }
        }
    }

    func deleteBookmark(_ bookmark: Bookmark) {
        db?.deleteBookmark(bookmark.id)
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    // MARK: - Subject

    func setSubject(for recording: Recording, subject: String?) {
        Task {
            do {
                try db?.updateRecordingSubject(recording.id, subject: subject)
                await loadRecordings()
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    var allSubjects: [String] {
        Array(Set(recordings.compactMap(\.subject))).sorted()
    }

    var filteredRecordings: [Recording] {
        guard let filter = subjectFilter else { return recordings }
        return recordings.filter { $0.subject == filter }
    }

    // MARK: - Notifications

    private func sendTranscriptionNotification(name: String) {
        let content = UNMutableNotificationContent()
        content.title = "Transcription Complete"
        content.body = "\(name) is ready to review."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { appLog("Notification error: \(error.localizedDescription)", .warning) }
        }
    }

    // MARK: - Alerts

    func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "MarkdownMax"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    // MARK: - Computed

    var recentRecordings: [Recording] {
        Array(recordings.prefix(5))
    }

    var hasInstalledModels: Bool {
        !installedModels.isEmpty
    }
}
