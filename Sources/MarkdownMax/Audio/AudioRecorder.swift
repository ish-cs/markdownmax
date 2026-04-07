import MarkdownMaxCore
import AVFoundation
import Combine
import Foundation

enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case engineStartFailed(Error)
    case fileCreationFailed(Error)
    case notRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied:         return "Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone."
        case .engineStartFailed(let e): return "Audio engine failed to start: \(e.localizedDescription)"
        case .fileCreationFailed(let e): return "Could not create audio file: \(e.localizedDescription)"
        case .notRecording:             return "Not currently recording."
        }
    }
}

@MainActor
final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var peakLevel: Float = 0  // 0–1 for UI meter

    /// Native microphone sample rate — available after startRecording()
    private(set) var nativeSampleRate: Double = 48000
    /// Called with raw Float32 samples at nativeSampleRate (non-main thread)
    var sampleCallback: (([Float]) -> Void)?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var currentRecordingURL: URL?
    private var startTime: Date?
    private var durationTimer: Timer?

    // Waveform samples (downsampled for visualization)
    private(set) var waveformSamples: [Float] = []
    private var sampleCounter = 0
    private let waveformDownsample = 512  // keep one sample per N frames

    private var recordingsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarkdownMax/recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support
    }

    // MARK: - Permission

    func requestPermission() async -> Bool {
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    func checkPermission() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    // MARK: - Recording

    func startRecording() async throws -> URL {
        let status = checkPermission()
        let granted: Bool
        if status == .authorized {
            granted = true
        } else {
            granted = await requestPermission()
        }
        guard granted else {
            throw AudioRecorderError.permissionDenied
        }

        let filename = "recording_\(Int(Date().timeIntervalSince1970)).wav"
        let url = recordingsDirectory.appendingPathComponent(filename)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        nativeSampleRate = inputFormat.sampleRate

        // Target: 16kHz mono (optimal for Whisper); record at native rate, we'll resample on export
        // Actually record at native rate and let WhisperKit handle resampling
        let recordFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: inputFormat.sampleRate,
                                         channels: 1,
                                         interleaved: false)!

        do {
            audioFile = try AVAudioFile(forWriting: url,
                                        settings: recordFormat.settings,
                                        commonFormat: .pcmFormatFloat32,
                                        interleaved: false)
        } catch {
            throw AudioRecorderError.fileCreationFailed(error)
        }

        waveformSamples = []
        sampleCounter = 0
        currentRecordingURL = url

        let mixerNode = AVAudioMixerNode()
        engine.attach(mixerNode)
        engine.connect(inputNode, to: mixerNode, format: inputFormat)

        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: recordFormat) { [weak self] buffer, _ in
            guard let self, let file = self.audioFile else { return }
            try? file.write(from: buffer)

            // Compute peak for level meter
            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var peak: Float = 0
                for i in 0..<frameCount {
                    let abs = Swift.abs(channelData[i])
                    if abs > peak { peak = abs }

                    // Downsample for waveform
                    self.sampleCounter += 1
                    if self.sampleCounter >= self.waveformDownsample {
                        self.waveformSamples.append(abs)
                        self.sampleCounter = 0
                    }
                }
                Task { @MainActor in self.peakLevel = min(peak, 1.0) }

                // Feed raw samples to live transcription (non-main thread OK)
                if let cb = self.sampleCallback {
                    let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))
                    cb(samples)
                }
            }
        }

        do {
            try engine.start()
        } catch {
            mixerNode.removeTap(onBus: 0)
            engine.detach(mixerNode)
            throw AudioRecorderError.engineStartFailed(error)
        }

        startTime = Date()
        isRecording = true
        duration = 0

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, let start = self.startTime else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }

        return url
    }

    func stopRecording() throws -> (url: URL, duration: TimeInterval, waveform: Data) {
        guard isRecording, let url = currentRecordingURL else {
            throw AudioRecorderError.notRecording
        }

        durationTimer?.invalidate()
        durationTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        // Remove mixer tap if attached
        for node in engine.attachedNodes where node is AVAudioMixerNode {
            (node as? AVAudioMixerNode)?.removeTap(onBus: 0)
            engine.detach(node)
        }
        engine.stop()

        audioFile = nil  // closes the file

        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? duration
        let waveformData = encodeWaveform(waveformSamples)

        isRecording = false
        peakLevel = 0
        currentRecordingURL = nil
        startTime = nil
        sampleCallback = nil

        return (url: url, duration: elapsed, waveform: waveformData)
    }

    // MARK: - Waveform encoding (delegates to WaveformUtils in Core)

    private func encodeWaveform(_ samples: [Float]) -> Data {
        WaveformUtils.encode(samples)
    }
}
