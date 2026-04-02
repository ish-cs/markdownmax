import Foundation
import Combine
import SwiftUI
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

    // MARK: - Services
    let audioRecorder = AudioRecorder()
    let transcriptionService = TranscriptionService()
    let modelDownloadManager = ModelDownloadManager()
    let exportService = ExportService()

    private var db: DatabaseManager?
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init() {
        do {
            db = try DatabaseManager()
        } catch {
            presentAlert("Database error: \(error.localizedDescription)")
        }
        // Forward child ObservableObject changes so views re-render
        audioRecorder.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        transcriptionService.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        modelDownloadManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
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
        appLog("App started. \(recordings.count) recording(s), \(installedModels.count) model(s) installed.")
    }

    /// Earlier builds saved `models/tiny` instead of WhisperKit’s Hub folder; point DB at the real path if files exist there.
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
        if changed {
            await loadInstalledModels()
        }
    }

    /// Scan the models directory and register any found model files not already in the DB.
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
            appLog("Auto-discovered model on disk: \(model.rawValue)")
            found = true
        }
        if found {
            await loadInstalledModels()
            // If nothing was active, make the first discovered model active
            if installedModels.first(where: \.isActive) == nil, let first = installedModels.first {
                try? db.setActiveModel(first.modelName)
                await loadInstalledModels()
            }
        }
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .toggleRecordingShortcut, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.toggleRecording() }
        }
        NotificationCenter.default.addObserver(
            forName: .openLastTranscriptShortcut, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let latest = self.recordings.first else { return }
                self.loadTranscript(for: latest)
                self.showTranscriptWindow = true
            }
        }
    }

    // MARK: - Recordings

    func loadRecordings() async {
        guard let db else { return }
        do {
            let all = try db.fetchAllRecordings()
            // Remove DB entries whose audio file no longer exists on disk
            for recording in all where !FileManager.default.fileExists(atPath: recording.filePath) {
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

    // MARK: - Recording flow

    func startRecording() {
        Task {
            do {
                appLog("Starting recording…")
                _ = try await audioRecorder.startRecording()
                appLog("Recording started.")
            } catch {
                appLog("Failed to start recording: \(error.localizedDescription)", .error)
                presentAlert(error.localizedDescription)
            }
        }
    }

    func stopRecording() {
        Task {
            do {
                appLog("Stopping recording…")
                let result = try audioRecorder.stopRecording()
                appLog("Recording stopped. Duration: \(String(format: "%.1f", result.duration))s, file: \(result.url.lastPathComponent)")
                guard let db else { return }
                let id = try db.insertRecording(
                    filename: result.url.lastPathComponent,
                    filePath: result.url.path,
                    duration: result.duration
                )
                try db.updateRecordingWaveform(id, waveformData: result.waveform)
                await loadRecordings()
                // Auto-select the new recording
                if let recording = recordings.first(where: { $0.id == id }) {
                    selectedRecording = recording
                    transcriptSegments = []
                }
                await transcribeRecording(id: id, url: result.url)
            } catch {
                appLog("Failed to stop recording: \(error.localizedDescription)", .error)
                presentAlert(error.localizedDescription)
            }
        }
    }

    func toggleRecording() {
        if audioRecorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    // MARK: - Transcription

    private func transcribeRecording(id: Int64, url: URL) async {
        guard let db else { return }
        guard let activeModel = installedModels.first(where: \.isActive) else {
            appLog("Transcription skipped: no active model.", .warning)
            try? db.updateRecordingStatus(id, status: .failed)
            presentAlert("No active model. Download one in Settings.")
            await loadRecordings()
            return
        }

        do {
            appLog("Transcribing with model '\(activeModel.modelName.rawValue)'…")
            try? db.updateRecordingStatus(id, status: .transcribing)
            await loadRecordings()

            try await transcriptionService.loadModel(activeModel.filePath, modelName: activeModel.modelName.rawValue)
            let segments = try await transcriptionService.transcribe(audioURL: url) { [weak self] segment in
                Task { @MainActor [weak self] in
                    guard let self, self.selectedRecording?.id == id else { return }
                    let t = Transcript(id: Int64(self.transcriptSegments.count),
                                       recordingID: id,
                                       text: segment.text,
                                       confidenceScore: segment.confidence,
                                       startTime: segment.startTime,
                                       endTime: segment.endTime)
                    self.transcriptSegments.append(t)
                }
            }
            appLog("Transcription complete. \(segments.count) segment(s).")

            try db.insertTranscripts(segments, forRecording: id)
            try db.updateRecordingStatus(id, status: .complete,
                                         model: activeModel.modelName.rawValue,
                                         duration: nil)
            await loadRecordings()
            // Reload transcript from DB with proper IDs if this recording is selected
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

    // MARK: - Transcript loading

    func loadTranscript(for recording: Recording) {
        selectedRecording = recording
        Task {
            guard let db else { return }
            do {
                transcriptSegments = try db.fetchTranscripts(forRecording: recording.id)
                showTranscriptWindow = true
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    // MARK: - Search

    func performSearch() {
        searchTask?.cancel()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let db else {
            searchResults = []
            return
        }
        searchTask = Task {
            do {
                let results = try db.searchTranscripts(query: q)
                if !Task.isCancelled {
                    searchResults = results
                }
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
                    id: 0,
                    modelName: model,
                    version: nil,
                    filePath: folder.path,
                    sizeMB: model.sizeMB,
                    isActive: installedModels.isEmpty,  // first model becomes active
                    downloadedAt: Date()
                )
                try? db?.upsertModel(installed)
                if installed.isActive {
                    try? db?.setActiveModel(model)
                }
                await loadInstalledModels()
                showOnboarding = false
            } catch {
                presentAlert(error.localizedDescription)
            }
        }
    }

    func setActiveModel(_ model: WhisperModelSize) {
        Task {
            do {
                try db?.setActiveModel(model)
                transcriptionService.unloadModel()
                await loadInstalledModels()
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
            // Clear existing transcripts and reset status
            try? db.deleteTranscripts(forRecording: recording.id)
            try? db.updateRecordingStatus(recording.id, status: .pending)
            if selectedRecording?.id == recording.id { transcriptSegments = [] }
            await loadRecordings()
            await transcribeRecording(id: recording.id, url: URL(fileURLWithPath: recording.filePath))
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
                appLog("Failed to delete recording: \(error.localizedDescription)", .error)
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

    // MARK: - Alerts

    func presentAlert(_ message: String) {
        alertMessage = message
        showAlert = true
    }

    // MARK: - Computed

    var activeModel: InstalledModel? {
        installedModels.first(where: \.isActive)
    }

    var recentRecordings: [Recording] {
        Array(recordings.prefix(5))
    }

    var hasInstalledModels: Bool {
        !installedModels.isEmpty
    }
}
