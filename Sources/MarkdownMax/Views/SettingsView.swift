import AppKit
import MarkdownMaxCore
import ServiceManagement
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
        .frame(width: 520, height: 380)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow))
    }
}

// MARK: - General tab

struct GeneralTab: View {
    @EnvironmentObject var appState: AppState
    @State private var launchAtLogin: Bool = AppDelegate.isLaunchAtLoginEnabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, val in AppDelegate.setLaunchAtLogin(val) }
            } footer: {
                Text("Automatically starts StudentMax when you log in.")
                    .foregroundStyle(.secondary).font(.caption)
            }

            Section {
                Toggle("Ghost mode", isOn: $appState.ghostMode)
            } footer: {
                Text("Hides the recording timer from the menu bar — the icon still changes while recording.")
                    .foregroundStyle(.secondary).font(.caption)
            }

            Section {
                if appState.installedModels.isEmpty {
                    Text("No models installed — download one in the Models tab.")
                        .foregroundStyle(.secondary).font(.callout)
                } else {
                    Picker("Transcription model", selection: $appState.selectedModelName) {
                        Text("Auto (best available)").tag(nil as WhisperModelSize?)
                        ForEach(appState.installedModels, id: \.id) { m in
                            Text(m.modelName.displayLabel).tag(Optional(m.modelName))
                        }
                    }
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("Model used to transcribe lectures after each recording stops. Auto selects the best installed model.")
                    .foregroundStyle(.secondary).font(.caption)
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
                    .font(.headline).padding(.top, 4)

                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                    ModelManagementRow(model: model)
                        .environmentObject(appState)
                }

                if let active = appState.activeModel {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "mic.fill").foregroundStyle(.red).font(.caption)
                        Text("Active model:")
                            .foregroundStyle(.secondary)
                        Text(active.modelName.displayLabel).bold()
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

    private var isInstalled: Bool {
        appState.installedModels.contains { $0.modelName == model }
    }
    private var isActiveModel: Bool {
        appState.activeModel?.modelName == model
    }
    private var downloadState: ModelDownloadState? {
        appState.modelDownloadManager.downloadStates[model]
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayLabel).font(.callout.bold())
                    Text(model.sizeFormatted).font(.caption).foregroundStyle(.secondary)
                    if model == .largeV3Turbo {
                        Text("Recommended")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.mmGreen.opacity(0.15))
                            .foregroundStyle(Color.mmGreen)
                            .clipShape(Capsule())
                    }
                }
                Text("WER \(model.werPercent) · \(model.speedDescription)")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            if isActiveModel {
                Circle().fill(Color.mmGreen).frame(width: 8, height: 8)
            }

            if let ds = downloadState, ds.isDownloading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                    TimelineView(.periodic(from: ds.startedAt ?? Date(), by: 1)) { _ in
                        Text(ds.elapsedFormatted).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    Button("Cancel") { appState.modelDownloadManager.cancelDownload(model) }
                        .buttonStyle(.borderless).font(.caption)
                }
            } else if isInstalled {
                Button("Delete") { appState.deleteModel(model) }
                    .buttonStyle(.bordered).controlSize(.small).foregroundStyle(.red)
            } else {
                Button("Download") { appState.downloadModel(model) }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow).opacity(0.7))
        .cornerRadius(8)
        .help(model.hoverDetail)
    }
}

// MARK: - Shortcuts tab

struct ShortcutsTab: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("Start / Stop recording:", name: .toggleRecording)
            } footer: {
                Text("Works globally — even when StudentMax is in the background.")
                    .foregroundStyle(.secondary).font(.caption)
            }
            Section {
                KeyboardShortcuts.Recorder("Add bookmark during recording:", name: .addBookmark)
            } footer: {
                Text("Marks the current moment while recording so you can jump back to it later.")
                    .foregroundStyle(.secondary).font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
}

// MARK: - Storage tab

struct StorageTab: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmDelete: Int? = nil

    private var totalModelSize: Int { appState.installedModels.reduce(0) { $0 + $1.sizeMB } }
    private var recordingCount: Int { appState.recordings.count }

    private let retentionOptions: [(label: String, days: Int)] = [
        ("Delete recordings older than 1 week",  7),
        ("Delete recordings older than 2 weeks", 14),
        ("Delete recordings older than 1 month", 30),
        ("Delete recordings older than 3 months",90),
        ("Delete ALL recordings",               -1),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Storage").font(.headline).padding(.top, 4)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Recordings", value: "\(recordingCount) file\(recordingCount == 1 ? "" : "s")")
                LabeledContent("Installed models",
                               value: ByteCountFormatter.string(
                                fromByteCount: Int64(totalModelSize) * 1024 * 1024, countStyle: .file))
            }
            .font(.callout)

            Divider()

            Text("No auto-deletion — remove old recordings manually below.")
                .font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(retentionOptions, id: \.days) { opt in
                    Button(opt.label, role: opt.days == -1 ? .destructive : nil) {
                        confirmDelete = opt.days
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.recordings.isEmpty)
                }
            }

            Divider()

            Button("Open Recordings Folder") { openRecordingsFolder() }.buttonStyle(.bordered)

            if !appState.installedModels.isEmpty {
                Divider()
                Button("Clear All Models", role: .destructive) {
                    for m in appState.installedModels { appState.deleteModel(m.modelName) }
                }
            }

            Spacer()
        }
        .padding(20)
        .confirmationDialog(deleteTitle, isPresented: .init(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button(deleteButtonLabel, role: .destructive) {
                if let d = confirmDelete {
                    if d == -1 {
                        for r in appState.recordings { appState.deleteRecording(r) }
                    } else {
                        appState.deleteRecordingsOlderThan(days: d)
                    }
                }
                confirmDelete = nil
            }
            Button("Cancel", role: .cancel) { confirmDelete = nil }
        }
    }

    private var deleteTitle: String {
        guard let d = confirmDelete else { return "" }
        if d == -1 { return "Delete ALL recordings? This cannot be undone." }
        return "Delete recordings older than \(d < 30 ? "\(d) day\(d == 1 ? "" : "s")" : "\(d/30) month\(d/30 == 1 ? "" : "s")")?"
    }

    private var deleteButtonLabel: String {
        guard let d = confirmDelete else { return "Delete" }
        return d == -1 ? "Delete All" : "Delete"
    }

    private func openRecordingsFolder() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudentMax/recordings")
        NSWorkspace.shared.open(folder)
    }
}
