import AppKit
import ServiceManagement
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.command, .shift]))
    static let addBookmark = Self("addBookmark", default: .init(.b, modifiers: [.command, .shift]))
}

@main
struct StudentMaxApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("StudentMax", id: "main") {
            MainView()
                .environmentObject(appState)
                .onAppear { appDelegate.setup(appState: appState) }
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {}
        }

        Window("Transcript", id: "transcript") {
            TranscriptView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .defaultSize(width: 700, height: 500)

        Window("Logs", id: "logs") {
            LogsView()
                .frame(minWidth: 600, minHeight: 300)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        }
        .defaultSize(width: 700, height: 450)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow).ignoresSafeArea())
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            guard let state = self?.appState else { return }
            Task { @MainActor in
                if state.audioRecorder.isRecording {
                    state.stopRecording()
                } else {
                    state.startRecording()
                }
            }
        }

        KeyboardShortcuts.onKeyUp(for: .addBookmark) { [weak self] in
            guard let state = self?.appState else { return }
            Task { @MainActor in state.addBookmark() }
        }

        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard let state = appState else { return }
        let sem = DispatchSemaphore(value: 0)
        let task = Task {
            await state.shutdownIfRecording()
            sem.signal()
        }
        if sem.wait(timeout: .now() + 5) == .timedOut {
            task.cancel()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func setup(appState: AppState) {
        guard statusBarController == nil else { return }
        self.appState = appState
        statusBarController = StatusBarController(appState: appState)
    }

    // MARK: - Launch at login

    static var isLaunchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            appLog("Launch-at-login toggle failed: \(error.localizedDescription)", .error)
        }
    }
}

