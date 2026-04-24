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
    @Published private(set) var isPaused = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var peakLevel: Float = 0

    /// Native microphone sample rate — available after startRecording()
    private(set) var nativeSampleRate: Double = 48000
    /// Called with raw Float32 samples at nativeSampleRate (non-main thread)
    var sampleCallback: (([Float]) -> Void)?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var fileWriteConverter: AVAudioConverter?
    private(set) var currentRecordingURL: URL?
    private var startTime: Date?
    private var pausedAccumulated: TimeInterval = 0
    private var durationTimer: Timer?

    private(set) var waveformSamples: [Float] = []
    private var sampleCounter = 0
    private let waveformDownsample = 512

    private var recordingsDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudentMax/recordings", isDirectory: true)
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
        guard granted else { throw AudioRecorderError.permissionDenied }

        let filename = "recording_\(Int(Date().timeIntervalSince1970)).wav"
        let url = recordingsDirectory.appendingPathComponent(filename)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        nativeSampleRate = inputFormat.sampleRate

        let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: inputFormat.sampleRate,
                                      channels: 1,
                                      interleaved: false)!

        let fileStorageSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        do {
            audioFile = try AVAudioFile(forWriting: url,
                                        settings: fileStorageSettings,
                                        commonFormat: .pcmFormatFloat32,
                                        interleaved: false)
        } catch {
            throw AudioRecorderError.fileCreationFailed(error)
        }

        let fileInputFmt = tapFormat
        let fileOutputFmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: 16000,
                                          channels: 1,
                                          interleaved: false)!
        fileWriteConverter = AVAudioConverter(from: fileInputFmt, to: fileOutputFmt)

        waveformSamples = []
        sampleCounter = 0
        pausedAccumulated = 0
        currentRecordingURL = url

        let mixerNode = AVAudioMixerNode()
        engine.attach(mixerNode)
        engine.connect(inputNode, to: mixerNode, format: inputFormat)

        mixerNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] buffer, _ in
            guard let self, !self.isPaused else { return }

            // Write to file at 16 kHz Int16 via converter
            if let converter = self.fileWriteConverter, let file = self.audioFile {
                let inRate = buffer.format.sampleRate
                let outCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000.0 / inRate))
                if let outBuf = AVAudioPCMBuffer(pcmFormat: converter.outputFormat,
                                                  frameCapacity: max(outCapacity, 1)) {
                    var error: NSError?
                    var provided = false
                    converter.convert(to: outBuf, error: &error) { _, status in
                        if !provided {
                            provided = true
                            status.pointee = .haveData
                            return buffer
                        }
                        status.pointee = .noDataNow
                        return nil
                    }
                    if error == nil, outBuf.frameLength > 0 {
                        try? file.write(from: outBuf)
                    }
                }
            }

            if let channelData = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var peak: Float = 0
                for i in 0..<frameCount {
                    let abs = Swift.abs(channelData[i])
                    if abs > peak { peak = abs }
                    self.sampleCounter += 1
                    if self.sampleCounter >= self.waveformDownsample {
                        self.waveformSamples.append(abs)
                        self.sampleCounter = 0
                    }
                }
                Task { @MainActor in self.peakLevel = min(peak, 1.0) }

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
        isPaused = false
        duration = 0

        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, let start = self.startTime else { return }
                self.duration = self.pausedAccumulated + Date().timeIntervalSince(start)
            }
        }

        return url
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        pausedAccumulated = duration
        startTime = nil   // stops timer update
        isPaused = true
    }

    func resumeRecording() {
        guard isRecording, isPaused else { return }
        isPaused = false
        startTime = Date()  // timer picks back up from pausedAccumulated
    }

    func stopRecording() throws -> (url: URL, duration: TimeInterval, waveform: Data) {
        guard isRecording, let url = currentRecordingURL else {
            throw AudioRecorderError.notRecording
        }

        durationTimer?.invalidate()
        durationTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        for node in engine.attachedNodes where node is AVAudioMixerNode {
            (node as? AVAudioMixerNode)?.removeTap(onBus: 0)
            engine.detach(node)
        }
        engine.stop()

        audioFile = nil
        fileWriteConverter = nil

        let elapsed = isPaused ? pausedAccumulated : (startTime.map { pausedAccumulated + Date().timeIntervalSince($0) } ?? duration)
        let waveformData = WaveformUtils.encode(waveformSamples)

        isRecording = false
        isPaused = false
        peakLevel = 0
        currentRecordingURL = nil
        startTime = nil
        pausedAccumulated = 0
        sampleCallback = nil

        return (url: url, duration: elapsed, waveform: waveformData)
    }
}
