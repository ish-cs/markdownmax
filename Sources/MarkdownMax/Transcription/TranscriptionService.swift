import MarkdownMaxCore
import Foundation
import WhisperKit
import SpeakerKit

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
    @Published private(set) var estimatedRemainingSeconds: TimeInterval? = nil

    private(set) var whisper: WhisperKit?
    private var loadedModelName: String?
    private var speakerKit: SpeakerKit?

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

        Task {
            do {
                speakerKit = try await SpeakerKit()
            } catch {
                // SpeakerKit unavailable; diarization will be skipped
            }
        }
    }

    func unloadModel() {
        whisper = nil
        loadedModelName = nil
    }

    // MARK: - Transcription

    /// Transcribes the audio file at `audioURL` and returns segments with timestamps.
    func transcribe(audioURL: URL, audioDuration: TimeInterval? = nil) async throws -> [TranscriptSegment] {
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
        estimatedRemainingSeconds = nil
        defer {
            isTranscribing = false
            progress = 1.0
            currentSegmentText = ""
            transcriptionStartDate = nil
            estimatedRemainingSeconds = nil
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

        // windowId = number of fully-completed 30s windows so far.
        // We compute RTF ourselves from wall-clock elapsed / audio processed,
        // which is accurate as soon as at least one window finishes.
        let startDate = Date()
        let progressCallback: TranscriptionCallback = { [weak self] prog in
            let elapsedWall = -startDate.timeIntervalSinceNow
            let windowsDone = Double(prog.windowId)   // completed 30s windows
            let loops       = prog.timings.totalDecodingLoops

            Task { @MainActor in
                if let total = audioDuration, total > 0 {
                    let totalWindows = max(1.0, ceil(total / 30.0))
                    // Smooth progress: completed windows + rough intra-window loop fraction
                    let intra = totalWindows > 1 ? min(loops / 50.0, 0.99) / totalWindows : min(loops / 50.0, 0.99)
                    self?.progress = min(windowsDone / totalWindows + intra, 0.99)

                    // RTF from actual wall clock; only reliable after ≥1 window done
                    if windowsDone >= 1, elapsedWall > 0 {
                        let processedAudio = windowsDone * 30.0
                        let rtf = elapsedWall / processedAudio
                        self?.estimatedRemainingSeconds = max(0, (total - processedAudio) * rtf)
                    }
                } else {
                    self?.progress = min(loops / 100.0, 0.99)
                }
            }
            return nil
        }

        let results: [TranscriptionResult] = try await whisper.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options,
            callback: progressCallback
        )

        var segments: [TranscriptSegment] = []
        for result in results {
            for seg in result.segments {
                let trimmed = seg.text.strippingWhisperTokens
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

        if let sk = speakerKit {
            do {
                let audioArray = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
                let diarization = try await sk.diarize(audioArray: audioArray)
                let labeled = diarization.addSpeakerInfo(to: results, strategy: .segment)

                var speakerByStart: [Double: String] = [:]
                for speakerTurn in labeled {
                    for seg in speakerTurn {
                        if let id = seg.speaker.speakerId {
                            let label = String(format: "SPEAKER_%02d", id)
                            speakerByStart[Double(seg.startTime)] = label
                        }
                    }
                }

                for i in segments.indices {
                    let t = segments[i].startTime
                    if let speaker = speakerByStart[t] {
                        segments[i].speaker = speaker
                    } else if let match = speakerByStart.first(where: { abs($0.key - t) < 0.5 }) {
                        segments[i].speaker = match.value
                    }
                }
            } catch {
                // Diarization failed; segments return with speaker = nil
            }
        }

        return segments
    }

    var isModelLoaded: Bool { whisper != nil }
}
