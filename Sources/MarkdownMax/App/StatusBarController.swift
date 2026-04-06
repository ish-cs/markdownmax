import AppKit
import Combine
import MarkdownMaxCore

final class StatusBarController {
    private var statusItem: NSStatusItem
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    @MainActor
    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        appState.audioRecorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.updateIcon(isRecording: isRecording, duration: 0)
                self?.updateMenu(isRecording: isRecording)
            }
            .store(in: &cancellables)

        appState.audioRecorder.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] duration in
                guard let self, self.appState.audioRecorder.isRecording else { return }
                self.updateIcon(isRecording: true, duration: duration)
            }
            .store(in: &cancellables)

        updateIcon(isRecording: false, duration: 0)
        updateMenu(isRecording: false)
    }

    private func updateMenu(isRecording: Bool) {
        let menu = NSMenu()
        let title = isRecording ? "Stop Recording" : "Start Recording"
        let item = NSMenuItem(title: title, action: #selector(handleToggle), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        statusItem.menu = menu
    }

    @objc private func handleToggle() {
        Task { @MainActor [weak self] in
            self?.appState.toggleRecording()
        }
    }

    private func updateIcon(isRecording: Bool, duration: TimeInterval) {
        let color: NSColor = isRecording ? .systemRed : .labelColor
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [color]))
        let name = isRecording ? "waveform.circle.fill" : "waveform.circle"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = !isRecording
            statusItem.button?.image = image
        }
        statusItem.button?.title = isRecording ? " \(duration.durationFormatted)" : ""
        statusItem.length = isRecording ? NSStatusItem.variableLength : NSStatusItem.squareLength
    }
}
