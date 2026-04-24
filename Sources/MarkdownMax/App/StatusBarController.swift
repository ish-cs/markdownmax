import AppKit
import Combine

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
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        appState.audioRecorder.$isPaused
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        appState.audioRecorder.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        appState.$ghostMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &cancellables)

        update()
        buildMenu()
    }

    // MARK: - Update icon

    @MainActor
    private func update() {
        let isRecording = appState.audioRecorder.isRecording
        let isPaused = appState.audioRecorder.isPaused
        let duration = appState.audioRecorder.duration

        let (name, color): (String, NSColor) = {
            if isRecording && isPaused { return ("pause.circle.fill", .systemOrange) }
            if isRecording             { return ("waveform.circle.fill", .systemRed) }
            return ("mic.circle", .secondaryLabelColor)
        }()

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(.init(paletteColors: [color]))
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = false
            statusItem.button?.image = image
        }

        if isRecording && !isPaused && !appState.ghostMode {
            statusItem.button?.title = " \(duration.durationFormatted)"
            statusItem.length = NSStatusItem.variableLength
        } else {
            statusItem.button?.title = ""
            statusItem.length = NSStatusItem.squareLength
        }

        buildMenu()
    }

    // MARK: - Menu

    @MainActor
    private func buildMenu() {
        let menu = NSMenu()
        let isRecording = appState.audioRecorder.isRecording
        let isPaused = appState.audioRecorder.isPaused

        if isRecording {
            // Pause / Resume
            let pauseTitle = isPaused ? "Resume Recording" : "Pause Recording"
            let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(handlePauseResume), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)

            // Stop
            let stopItem = NSMenuItem(title: "Stop & Transcribe", action: #selector(handleStop), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
        } else {
            // Start
            let startItem = NSMenuItem(title: "Start Recording", action: #selector(handleStart), keyEquivalent: "")
            startItem.target = self
            menu.addItem(startItem)
        }

        menu.addItem(.separator())

        let openItem = NSMenuItem(title: "Open StudentMax", action: #selector(handleOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func handleStart() {
        Task { @MainActor [weak self] in self?.appState.startRecording() }
    }

    @objc private func handlePauseResume() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if appState.audioRecorder.isPaused {
                appState.resumeRecording()
            } else {
                appState.pauseRecording()
            }
        }
    }

    @objc private func handleStop() {
        Task { @MainActor [weak self] in self?.appState.stopRecording() }
    }

    @objc private func handleOpen() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.title == "StudentMax" {
            window.makeKeyAndOrderFront(nil)
            return
        }
        // fallback: open via environment
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
