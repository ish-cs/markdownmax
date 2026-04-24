import Foundation
import MarkdownMaxCore

@MainActor
final class AlwaysOnRecordingService: ObservableObject {
    @Published private(set) var mode: RecordingMode
    @Published private(set) var currentRecordingID: Int64?

    // Dependencies (set after init)
    var db: DatabaseManager?
    var installedModels: [InstalledModel] = []
    var onRecordingsChanged: (() async -> Void)?
    /// Called when switching Passive → Important with a snapshot WAV URL, recording ID, and time offset.
    var onRetranscribeSnapshot: ((URL, Int64, Double) async -> Void)?

    private let audioRecorder: AudioRecorder
    private let transcriptionService: TranscriptionService
    private let liveTranscriptionService: LiveTranscriptionService

    private var hourTimer: Timer?
    private var flushTimer: Timer?

    /// Cumulative recorded seconds before this session (for timestamp offsetting).
    /// Internal so AppState / views can read it for live display.
    var sessionTimeOffset: Double = 0
    /// The day's master audio file URL (first session of the day). nil = current session IS the master.
    private var dayMasterAudioURL: URL?

    init(
        mode: RecordingMode,
        audioRecorder: AudioRecorder,
        transcriptionService: TranscriptionService,
        liveTranscriptionService: LiveTranscriptionService
    ) {
        self.mode = mode
        self.audioRecorder = audioRecorder
        self.transcriptionService = transcriptionService
        self.liveTranscriptionService = liveTranscriptionService
    }

    // MARK: - Public API

    func start() async {
        guard mode != .privacy else {
            appLog("AlwaysOn: starting in privacy mode — not recording")
            return
        }
        await beginChunk()
    }

    func setMode(_ newMode: RecordingMode) async {
        guard newMode != mode else { return }
        let old = mode
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "recordingMode")
        appLog("AlwaysOn: mode \(old.rawValue) → \(newMode.rawValue)")

        if old == .privacy {
            await beginChunk()
        } else if newMode == .privacy {
            await endChunk()
        } else {
            // passive ↔ important: swap model, keep recording
            await switchModel(from: old)
        }
    }

    func shutdown() async {
        guard mode != .privacy, audioRecorder.isRecording else { return }
        await endChunk()
    }

    // MARK: - Chunk lifecycle

    private func beginChunk() async {
        do {
            let sessionURL = try await audioRecorder.startRecording()

            if let existing = db?.fetchTodaysRecording() {
                // Continue today's day recording — no new DB row
                currentRecordingID = existing.id
                sessionTimeOffset = existing.durationSeconds
                dayMasterAudioURL = URL(fileURLWithPath: existing.filePath)
                appLog("AlwaysOn: resuming day recording ID \(existing.id), offset \(Int(sessionTimeOffset))s")
            } else {
                // First session of the day — create the day record
                guard let db else { return }
                let id = try db.insertRecording(
                    filename: sessionURL.lastPathComponent,
                    filePath: sessionURL.path,
                    duration: 0
                )
                currentRecordingID = id
                sessionTimeOffset = 0
                dayMasterAudioURL = nil  // session URL becomes the master
                appLog("AlwaysOn: new day recording ID \(id), file: \(sessionURL.lastPathComponent)")
            }

            scheduleHourRotation()
            scheduleFlush()
            Task { await self.startLiveTranscription() }
            await onRecordingsChanged?()
        } catch {
            appLog("AlwaysOn: beginChunk failed: \(error.localizedDescription)", .error)
        }
    }

    private func endChunk() async {
        hourTimer?.invalidate(); hourTimer = nil
        flushTimer?.invalidate(); flushTimer = nil

        audioRecorder.sampleCallback = nil
        await liveTranscriptionService.stop()
        let rawSegments = liveTranscriptionService.drainConfirmedSegments()
        let segments = applyOffset(rawSegments)

        let modelName = selectModel(for: mode)?.modelName.rawValue
        let masterURL = dayMasterAudioURL
        let offset = sessionTimeOffset

        do {
            let result = try audioRecorder.stopRecording()
            if let id = currentRecordingID, let db {
                if !segments.isEmpty {
                    try db.insertTranscripts(segments, forRecording: id)
                }

                // Merge session audio into day master (if this is a continuation session)
                let sessionURL = result.url
                if let master = masterURL, master.path != sessionURL.path {
                    appendWAV(from: sessionURL, to: master)
                    try? FileManager.default.removeItem(at: sessionURL)
                }

                let totalDuration = offset + result.duration
                try db.updateRecordingWaveform(id, waveformData: result.waveform)
                try db.updateRecordingStatus(id, status: .complete,
                                             model: modelName,
                                             duration: totalDuration)
                appLog("AlwaysOn: day recording \(id) saved, \(segments.count) seg(s), total \(String(format: "%.0f", totalDuration))s")
            }
        } catch {
            appLog("AlwaysOn: endChunk audio stop failed: \(error.localizedDescription)", .error)
        }

        currentRecordingID = nil
        sessionTimeOffset = 0
        dayMasterAudioURL = nil
        await onRecordingsChanged?()
    }

    private func rotateChunk() async {
        appLog("AlwaysOn: rotating hour chunk")
        await endChunk()
        if mode != .privacy {
            await beginChunk()
        }
    }

    // MARK: - Model switching (passive ↔ important without stopping audio)

    private func switchModel(from oldMode: RecordingMode) async {
        audioRecorder.sampleCallback = nil
        await liveTranscriptionService.stop()
        // Drain and flush whatever was transcribed under the old model
        let rawSegments = liveTranscriptionService.drainConfirmedSegments()
        if let id = currentRecordingID, let db, !rawSegments.isEmpty {
            try? db.insertTranscripts(applyOffset(rawSegments), forRecording: id)
        }

        // Passive → Important: snapshot recent audio and retranscribe with better model
        if oldMode == .passive, mode == .important,
           let id = currentRecordingID,
           let audioURL = audioRecorder.currentRecordingURL,
           let callback = onRetranscribeSnapshot {
            let hasSegments = db.map { $0.countTranscripts(forRecording: id) > 0 } ?? false
            if hasSegments, let (snapshotURL, timeOffset) = snapshotAudio(from: audioURL, maxSeconds: 300) {
                // globalOffset = session start + offset within session file
                let globalOffset = sessionTimeOffset + timeOffset
                Task { await callback(snapshotURL, id, globalOffset) }
            }
        }

        Task { await self.startLiveTranscription() }
    }

    // MARK: - Audio snapshot helpers

    /// Copies the last `maxSeconds` of a 16kHz Int16 mono WAV to a temp file.
    /// Returns (tempURL, timeOffsetInRecording) so segment timestamps can be offset.
    private func snapshotAudio(from url: URL, maxSeconds: Double) -> (url: URL, offset: Double)? {
        let bytesPerSecond = 32000  // 16 kHz × 2 bytes × 1 channel
        let headerSize = 44

        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              data.count > headerSize else { return nil }

        let audioBytes = data.count - headerSize
        guard audioBytes > 0 else { return nil }

        let maxAudioBytes = (Int(maxSeconds * Double(bytesPerSecond)) / 2) * 2  // 2-byte aligned
        let snapshotData: Data
        let timeOffset: Double

        if audioBytes <= maxAudioBytes {
            snapshotData = data
            timeOffset = 0
        } else {
            let cutBytes = audioBytes - maxAudioBytes
            timeOffset = Double(cutBytes) / Double(bytesPerSecond)
            let audioSlice = data[(headerSize + cutBytes)...]
            snapshotData = buildWAV(from: audioSlice)
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmx_snap_\(UUID().uuidString).wav")
        guard (try? snapshotData.write(to: tempURL)) != nil else { return nil }
        return (tempURL, timeOffset)
    }

    // MARK: - Live transcription

    private func startLiveTranscription() async {
        guard let model = selectModel(for: mode) else {
            appLog("AlwaysOn: no model installed for \(mode.rawValue) — live transcription unavailable", .warning)
            return
        }
        do {
            try await transcriptionService.loadModel(model.filePath, modelName: model.modelName.rawValue)
        } catch {
            appLog("AlwaysOn: model load failed: \(error.localizedDescription)", .error)
            return
        }
        guard audioRecorder.isRecording, let whisper = transcriptionService.whisper else { return }
        liveTranscriptionService.start(whisper: whisper, inputSampleRate: audioRecorder.nativeSampleRate)
        audioRecorder.sampleCallback = { [weak self] samples in
            self?.liveTranscriptionService.appendSamples(samples)
        }
        appLog("AlwaysOn: live transcription running (\(model.modelName.rawValue))")
    }

    // MARK: - Periodic segment flush

    private func scheduleFlush() {
        flushTimer?.invalidate()
        flushTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.flushSegments() }
        }
    }

    private func flushSegments() async {
        guard let id = currentRecordingID, let db else { return }
        let raw = liveTranscriptionService.drainConfirmedSegments()
        guard !raw.isEmpty else { return }
        let segments = applyOffset(raw)
        do {
            try db.insertTranscripts(segments, forRecording: id)
            appLog("AlwaysOn: flushed \(segments.count) segment(s) for recording \(id)")
            await onRecordingsChanged?()
        } catch {
            appLog("AlwaysOn: flush failed: \(error.localizedDescription)", .error)
        }
    }

    // MARK: - Hourly rotation

    private func scheduleHourRotation() {
        hourTimer?.invalidate()
        let cal = Calendar.current
        let now = Date()
        guard var next = cal.nextDate(after: now,
                                      matching: DateComponents(minute: 0, second: 0),
                                      matchingPolicy: .nextTime) else { return }
        // If the next hour boundary is < 2 minutes away, skip to the one after
        if next.timeIntervalSince(now) < 120 {
            next = cal.date(byAdding: .hour, value: 1, to: next) ?? next
        }
        let interval = next.timeIntervalSince(now)
        hourTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.rotateChunk() }
        }
        appLog("AlwaysOn: next rotation in \(Int(interval / 60))m \(Int(interval) % 60)s")
    }

    // MARK: - Helpers

    /// Shifts transcript timestamps by `sessionTimeOffset` (no-op when offset is zero).
    private func applyOffset(_ segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard sessionTimeOffset > 0 else { return segments }
        return segments.map {
            TranscriptSegment(text: $0.text,
                              startTime: $0.startTime + sessionTimeOffset,
                              endTime: $0.endTime + sessionTimeOffset,
                              confidence: $0.confidence)
        }
    }

    // MARK: - Model selection

    /// Selects the best installed model for a given mode.
    func selectModel(for mode: RecordingMode) -> InstalledModel? {
        switch mode {
        case .privacy:
            return nil
        case .passive:
            // Prefer lightest accurate models for minimal CPU impact
            let order: [WhisperModelSize] = [.medium, .small, .tiny, .large, .largeV3Turbo, .distilLargeV3]
            return order.compactMap { sz in installedModels.first { $0.modelName == sz } }.first
        case .important:
            // Prefer highest quality (turbo variants first for speed+quality balance)
            let order: [WhisperModelSize] = [.largeV3Turbo, .distilLargeV3, .large, .medium, .small, .tiny]
            return order.compactMap { sz in installedModels.first { $0.modelName == sz } }.first
        }
    }

    /// The best model available for retranscription jobs.
    var bestModel: InstalledModel? {
        selectModel(for: .important) ?? selectModel(for: .passive)
    }
}
