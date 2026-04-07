import AppKit
import MarkdownMaxCore
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            ModelsTab()
                .environmentObject(appState)
                .tabItem { Label("Models", systemImage: "cube.box") }
                .tag(1)

            ShortcutsTab()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(2)

            StorageTab()
                .environmentObject(appState)
                .tabItem { Label("Storage", systemImage: "internaldrive") }
                .tag(3)
        }
        .frame(width: 520, height: 360)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow))
    }
}

// MARK: - General tab

struct GeneralTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section {
                Toggle("Live transcription", isOn: $appState.liveTranscriptionEnabled)
                Toggle("Open window when recording starts", isOn: $appState.autoOpenWindowOnRecord)
                    .disabled(!appState.liveTranscriptionEnabled)
            } footer: {
                Text("Live transcription shows text as you speak. When off, transcription runs after you stop recording.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

// MARK: - Models tab

struct ModelsTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Installed Models")
                    .font(.headline)
                    .padding(.top, 4)

                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                    ModelManagementRow(model: model)
                        .environmentObject(appState)
                }

                if let active = appState.activeModel {
                    Divider()
                    HStack {
                        Text("Active model:")
                            .foregroundStyle(.secondary)
                        Text(active.modelName.displayLabel)
                            .bold()
                    }
                    .font(.callout)
                }
            }
            .padding(20)
        }
    }
}

struct ModelManagementRow: View {
    let model: WhisperModelSize
    @EnvironmentObject var appState: AppState

    private var installedModel: InstalledModel? {
        appState.installedModels.first { $0.modelName == model }
    }

    private var isInstalled: Bool { installedModel != nil }
    private var isActive: Bool { installedModel?.isActive == true }
    private var downloadState: ModelDownloadState? { appState.modelDownloadManager.downloadStates[model] }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayLabel)
                        .font(.callout.bold())
                    Text(model.sizeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model == .largeV3Turbo {
                        Text("Recommended")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text("WER \(model.werPercent) · \(model.speedDescription)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            if let ds = downloadState, ds.isDownloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    TimelineView(.periodic(from: ds.startedAt ?? Date(), by: 1)) { _ in
                        Text(ds.elapsedFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button("Cancel") { appState.modelDownloadManager.cancelDownload(model) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            } else if isInstalled {
                HStack(spacing: 6) {
                    if isActive {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Button("Use") { appState.setActiveModel(model) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("Delete") { appState.deleteModel(model) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                }
            } else {
                Button("Download") { appState.downloadModel(model) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow).opacity(0.7))
        .cornerRadius(8)
        .help(model.hoverDetail)
    }
}

// MARK: - Shortcuts tab

struct ShortcutsTab: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder("Toggle recording:", name: .toggleRecording)
            KeyboardShortcuts.Recorder("Open last transcript:", name: .openLastTranscript)
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

// MARK: - Storage tab

struct StorageTab: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    private var totalModelSize: Int {
        appState.installedModels.reduce(0) { $0 + $1.sizeMB }
    }

    private var recordingCount: Int { appState.recordings.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage")
                .font(.headline)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Recordings", value: "\(recordingCount) file\(recordingCount == 1 ? "" : "s")")
                LabeledContent("Installed models", value: ByteCountFormatter.string(fromByteCount: Int64(totalModelSize) * 1024 * 1024, countStyle: .file))
            }
            .font(.callout)

            Divider()

            HStack(spacing: 12) {
                Button("Open Recordings Folder") { openRecordingsFolder() }
                    .buttonStyle(.bordered)
                Button("View Logs") { openWindow(id: "logs") }
                    .buttonStyle(.bordered)
            }

            Divider()

            Button("Clear All Models", role: .destructive) {
                for model in appState.installedModels {
                    appState.deleteModel(model.modelName)
                }
            }
            .disabled(appState.installedModels.isEmpty)

            Spacer()
        }
        .padding(20)
    }

    private func openRecordingsFolder() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MarkdownMax/recordings")
        NSWorkspace.shared.open(folder)
    }
}
