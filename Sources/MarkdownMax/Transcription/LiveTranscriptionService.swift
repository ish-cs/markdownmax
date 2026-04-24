import AVFoundation
import Foundation
import MarkdownMaxCore
import WhisperKit

// MARK: - Thread-safe sample buffer

private final class SampleBuffer: @unchecked Sendable {
    private var _samples: [Float] = []
    private var _committed: Int = 0
    private let lock = NSLock()

    var totalCount: Int { lock.withLock { _samples.count } }
    var committedCount: Int { lock.withLock { _committed } }

    func append(_ new: [Float]) {
        lock.withLock { _samples.append(contentsOf: new) }
    }

    func slice(from: Int, count: Int) -> [Float] {
        lock.withLock {
            let end = min(from + count, _samples.count)
            guard from < end else { return [] }
            return Array(_samples[from..<end])
        }
    }

    func commit(upTo index: Int) {
        lock.withLock { _committed = min(index, _samples.count) }
    }

    func drain() -> [Float] {
        lock.withLock {
            guard _committed < _samples.count else { return [] }
            let result = Array(_samples[_committed...])
            _committed = _samples.count
            return result
        }
    }

    func reset() {
        lock.withLock { _samples = []; _committed = 0 }
    }
}

// MARK: - Simple resampler

private final class Resampler: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat

    init?(inputRate: Double) {
        guard let inFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate, channels: 1, interleaved: false),
              let outFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(WhisperKit.sampleRate), channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: inFmt, to: outFmt) else { return nil }
        self.inputFormat = inFmt
        self.outputFormat = outFmt
        self.converter = conv
    }

    func resample(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        inputBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            inputBuffer.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count)
        }
        let outCapacity = AVAudioFrameCount(ceil(Double(samples.count) * Double(WhisperKit.sampleRate) / inputFormat.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else { return [] }
        var error: NSError?
        var didProvide = false
        converter.convert(to: outputBuffer, error: &error) { _, status in
            if !didProvide {
                didProvide = true
                status.pointee = .haveData
                return inputBuffer
            }
            status.pointee = .noDataNow
            return nil
        }
        guard error == nil, outputBuffer.frameLength > 0 else { return [] }
        return Array(UnsafeBufferPointer(start: outputBuffer.floatChannelData![0], count: Int(outputBuffer.frameLength)))
    }
}

// MARK: - Thread-safe resampler holder

private final class ResamplerBox: @unchecked Sendable {
    private var _resampler: Resampler?
    private let lock = NSLock()

    func set(_ r: Resampler?) { lock.withLock { _resampler = r } }
    func resample(_ samples: [Float]) -> [Float] { lock.withLock { _resampler?.resample(samples) } ?? [] }
}

// MARK: - LiveTranscriptionService

@MainActor
final class LiveTranscriptionService: ObservableObject {
    @Published private(set) var confirmedSegments: [TranscriptSegment] = []
    @Published private(set) var isSpeaking: Bool = false
    @Published private(set) var isActive: Bool = false
    @Published private(set) var isTranscribingChunk: Bool = false

    private let sampleBuffer = SampleBuffer()
    private let resamplerBox = ResamplerBox()
    private var whisper: WhisperKit?
    private var loopTask: Task<Void, Never>?

    // VAD constants
    private let sampleRate = WhisperKit.sampleRate          // 16000
    private let vadWindowSec: Double = 0.2                  // energy window
    private let silenceCommitSec: Double = 0.6              // silence → commit
    private let maxChunkSec: Double = 6.0                   // force commit
    private let energyThreshold: Float = 0.008              // VAD onset sensitivity
    /// Minimum RMS for an entire chunk to be worth sending to Whisper.
    /// Filters distant TV, HVAC, low ambient noise without stopping VAD detection.
    private let minTranscribeRMS: Float = 0.02

    // MARK: - Public API

    /// Removes and returns all confirmed segments, clearing the in-memory list.
    /// Call after `stop()` to drain the final batch, or periodically to flush to DB.
    func drainConfirmedSegments() -> [TranscriptSegment] {
        let result = confirmedSegments
        confirmedSegments = []
        return result
    }

    func start(whisper: WhisperKit, inputSampleRate: Double) {
        self.whisper = whisper
        resamplerBox.set(Resampler(inputRate: inputSampleRate))
        sampleBuffer.reset()
        confirmedSegments = []
        isSpeaking = false
        isActive = true
        loopTask = Task { [weak self] in await self?.vadLoop() }
    }

    /// Called from the audio tap (non-main thread safe).
    nonisolated func appendSamples(_ samples: [Float]) {
        let resampled = resamplerBox.resample(samples)
        guard !resampled.isEmpty else { return }
        sampleBuffer.append(resampled)
    }

    /// Stop live transcription and return any uncommitted samples for a final flush.
    func stop() async {
        loopTask?.cancel()
        loopTask = nil
        isSpeaking = false

        // Flush remaining uncommitted samples
        let remaining = sampleBuffer.drain()
        if remaining.count >= sampleRate, whisper != nil {
            await transcribeAndCommit(samples: remaining,
                                      timeOffset: Double(sampleBuffer.committedCount) / Double(sampleRate))
        }

        isActive = false
        whisper = nil
        resamplerBox.set(nil)
    }

    // MARK: - VAD loop

    private func vadLoop() async {
        let vadWindow = Int(vadWindowSec * Double(sampleRate))
        let silenceSamples = Int(silenceCommitSec * Double(sampleRate))
        let maxChunkSamples = Int(maxChunkSec * Double(sampleRate))

        var speechStartSample: Int? = nil
        var lastSpeechSample: Int = 0

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 80_000_000)   // 80ms tick

            let total = sampleBuffer.totalCount
            let committed = sampleBuffer.committedCount

            // Energy check on recent window
            let windowStart = max(committed, total - vadWindow)
            let window = sampleBuffer.slice(from: windowStart, count: total - windowStart)
            let energy = rms(window)
            let speech = energy > energyThreshold

            await MainActor.run { self.isSpeaking = speech }

            if speech {
                if speechStartSample == nil { speechStartSample = total }
                lastSpeechSample = total
            }

            let silenceLen = total - lastSpeechSample
            let chunkLen = speechStartSample.map { total - $0 } ?? 0

            // Commit if: silence long enough, or chunk too long
            guard speechStartSample != nil,
                  lastSpeechSample > committed,
                  silenceLen >= silenceSamples || chunkLen >= maxChunkSamples
            else { continue }

            let chunk = sampleBuffer.slice(from: committed, count: lastSpeechSample - committed)
            guard chunk.count >= sampleRate / 2 else { continue }

            let offset = Double(committed) / Double(sampleRate)
            sampleBuffer.commit(upTo: lastSpeechSample)
            speechStartSample = nil

            await transcribeAndCommit(samples: chunk, timeOffset: offset)
        }
    }

    // MARK: - Transcription

    private func transcribeAndCommit(samples: [Float], timeOffset: Double) async {
        guard rms(samples) >= minTranscribeRMS else { return }  // too quiet — skip Whisper
        guard let whisper else { return }
        isTranscribingChunk = true
        defer { isTranscribingChunk = false }
        do {
            let options = DecodingOptions(
                task: .transcribe,
                temperature: 0,
                temperatureFallbackCount: 1,
                usePrefillPrompt: true,
                withoutTimestamps: false,
                wordTimestamps: false
            )
            let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
            let newSegs: [TranscriptSegment] = results.flatMap { r in
                r.segments.compactMap { seg in
                    let clean = seg.text.strippingWhisperTokens
                    guard !clean.isEmpty else { return nil }
                    return TranscriptSegment(
                        text: clean,
                        startTime: Double(seg.start) + timeOffset,
                        endTime: Double(seg.end) + timeOffset,
                        confidence: Double(seg.avgLogprob)
                    )
                }
            }
            guard !newSegs.isEmpty else { return }
            confirmedSegments.append(contentsOf: newSegs)
        } catch {
            // Non-fatal — just skip this chunk
        }
    }

    // MARK: - Helpers

    private func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return sqrt(sum / Float(samples.count))
    }
}
