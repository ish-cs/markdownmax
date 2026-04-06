import MarkdownMaxCore
import Foundation
import WhisperKit

enum TranscriptionError: Error, LocalizedError {
    case noModelInstalled
    case modelLoadFailed(String)
    case transcriptionFailed(String)
    case fileNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .noModelInstalled:             return "No Whisper model installed. Download one in Settings."
        case .modelLoadFailed(let msg):     return "Model load failed: \(msg)"
        case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
        case .fileNotFound(let url):        return "Audio file not found: \(url.lastPathComponent)"
        }
    }
}

@MainActor
final class TranscriptionService: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var isTranscribing = false
    @Published private(set) var currentSegmentText: String = ""
    @Published private(set) var transcriptionStartDate: Date? = nil

    private var whisper: WhisperKit?
    private var loadedModelName: String?

    // MARK: - Model Loading

    func loadModel(_ modelPath: String, modelName: String) async throws {
        if loadedModelName == modelName { return }

        isTranscribing = false
        progress = 0
        whisper = nil

        let config = WhisperKitConfig(modelFolder: modelPath)
        do {
            whisper = try await WhisperKit(config)
            loadedModelName = modelName
        } catch {
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    func unloadModel() {
        whisper = nil
        loadedModelName = nil
    }

    // MARK: - Transcription

    /// Transcribes the audio file at `audioURL` and returns segments with timestamps.
    func transcribe(audioURL: URL) async throws -> [TranscriptSegment] {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound(audioURL)
        }
        guard let whisper else {
            throw TranscriptionError.noModelInstalled
        }

        isTranscribing = true
        progress = 0
        currentSegmentText = ""
        transcriptionStartDate = Date()
        defer {
            isTranscribing = false
            progress = 1.0
            currentSegmentText = ""
            transcriptionStartDate = nil
        }

        let options = DecodingOptions(
            task: .transcribe,
            language: nil,
            temperature: 0,
            temperatureFallbackCount: 5,
            usePrefillPrompt: true,
            withoutTimestamps: false,
            wordTimestamps: false
        )

        // Callback: ((TranscriptionProgress) -> Bool?)? — return nil to continue
        let progressCallback: TranscriptionCallback = { [weak self] prog in
            let loops = prog.timings.totalDecodingLoops
            Task { @MainActor in
                self?.progress = min(loops / 100.0, 0.99)
            }
            return nil  // nil = continue transcribing
        }

        let results: [TranscriptionResult] = try await whisper.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: progressCallback
        )

        var segments: [TranscriptSegment] = []
        for result in results {
            for seg in result.segments {
                let stripped = seg.text
                    .replacing(#/<\|[^|>]*\|>/#, with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let trimmed = stripped
                guard !trimmed.isEmpty else { continue }
                let segment = TranscriptSegment(
                    text: trimmed,
                    startTime: Double(seg.start),
                    endTime: Double(seg.end),
                    confidence: Double(seg.avgLogprob)
                )
                segments.append(segment)
                currentSegmentText = trimmed
            }
        }
        return segments
    }

    var isModelLoaded: Bool { whisper != nil }
}
