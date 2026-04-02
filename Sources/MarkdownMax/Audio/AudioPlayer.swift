import AVFoundation
import Foundation

@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func load(url: URL) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.delegate = self
        p.prepareToPlay()
        player = p
        duration = p.duration
        currentTime = 0
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func stop() {
        player?.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.stopTimer()
        }
    }
}
