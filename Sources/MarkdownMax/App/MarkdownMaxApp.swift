import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.command]))
    static let openLastTranscript = Self("openLastTranscript", default: .init(.t, modifiers: [.command, .shift]))
}

@main
struct MarkdownMaxApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("MarkdownMax", id: "main") {
            MainView()
                .environmentObject(appState)
                .onAppear { appDelegate.setup(appState: appState) }
        }
        .defaultSize(width: 900, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {}
        }

        Window("Transcript", id: "transcript") {
            TranscriptView()
                .environmentObject(appState)
                .frame(minWidth: 600, minHeight: 400)
        }
        .defaultSize(width: 700, height: 500)

        Window("Logs", id: "logs") {
            LogsView()
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 700, height: 450)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        KeyboardShortcuts.onKeyUp(for: .toggleRecording) {
            NotificationCenter.default.post(name: .toggleRecordingShortcut, object: nil)
        }
        KeyboardShortcuts.onKeyUp(for: .openLastTranscript) {
            NotificationCenter.default.post(name: .openLastTranscriptShortcut, object: nil)
        }

        DispatchQueue.main.async {
            for window in NSApp.windows {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @MainActor
    func setup(appState: AppState) {
        guard statusBarController == nil else { return }
        statusBarController = StatusBarController(appState: appState)
    }
}

extension Notification.Name {
    static let toggleRecordingShortcut = Notification.Name("toggleRecordingShortcut")
    static let openLastTranscriptShortcut = Notification.Name("openLastTranscriptShortcut")
}
