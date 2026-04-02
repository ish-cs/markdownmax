import MarkdownMaxCore
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var showingSearch = false

    var body: some View {
        VStack(spacing: 0) {
            // Header: record button + status
            recordingHeader
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            // Search bar
            searchBar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            // Recordings list or search results
            if showingSearch && !appState.searchQuery.isEmpty {
                searchResultsList
            } else {
                recentRecordingsList
            }

            Divider()

            // Footer actions
            footerActions
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 340)
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView()
                .environmentObject(appState)
        }
        .alert("MarkdownMax", isPresented: $appState.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.alertMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleRecordingShortcut)) { _ in
            appState.toggleRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLastTranscriptShortcut)) { _ in
            if let latest = appState.recordings.first {
                appState.loadTranscript(for: latest)
                openWindow(id: "transcript")
            }
        }
        .onChange(of: appState.showTranscriptWindow) { _, show in
            if show { openWindow(id: "transcript") }
        }
    }

    // MARK: - Recording header

    private var recordingHeader: some View {
        HStack {
            RecordingIndicator(
                isRecording: appState.audioRecorder.isRecording,
                peakLevel: appState.audioRecorder.peakLevel
            )

            VStack(alignment: .leading, spacing: 2) {
                if appState.audioRecorder.isRecording {
                    Text("Recording…")
                        .font(.headline)
                    Text(appState.audioRecorder.duration.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text("MarkdownMax")
                        .font(.headline)
                    Text(appState.activeModel.map { "Model: \($0.modelName.rawValue)" } ?? "No model installed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: appState.toggleRecording) {
                Image(systemName: appState.audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.title2)
                    .foregroundStyle(appState.audioRecorder.isRecording ? .red : .accentColor)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("r", modifiers: .command)
            .help(appState.audioRecorder.isRecording ? "Stop recording (⌘R)" : "Start recording (⌘R)")
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search transcripts…", text: $appState.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onSubmit { appState.performSearch() }
                .onChange(of: appState.searchQuery) { _, q in
                    showingSearch = !q.isEmpty
                    appState.performSearch()
                }
            if !appState.searchQuery.isEmpty {
                Button(action: {
                    appState.searchQuery = ""
                    showingSearch = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Recordings list

    private var recentRecordingsList: some View {
        Group {
            if appState.recordings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(appState.recordings) { recording in
                            RecordingRow(recording: recording)
                                .environmentObject(appState)
                        }
                    }
                }
                .frame(maxHeight: 300)
            }
        }
    }

    // MARK: - Search results

    private var searchResultsList: some View {
        Group {
            if appState.searchResults.isEmpty {
                Text("No results for \"\(appState.searchQuery)\"")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(appState.searchResults.prefix(10).enumerated()), id: \.offset) { _, result in
                            SearchResultRow(result: result)
                                .environmentObject(appState)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.slash")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No recordings yet")
                .foregroundStyle(.secondary)
                .font(.callout)
            Text("Press ⌘R to start recording")
                .foregroundStyle(.tertiary)
                .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footerActions: some View {
        HStack {
            Button("Settings") { openSettings() }
                .buttonStyle(.plain)
                .font(.callout)
                .keyboardShortcut(",", modifiers: .command)

            Button("All Recordings") { openWindow(id: "recordings") }
                .buttonStyle(.plain)
                .font(.callout)

            Button("Logs") { openWindow(id: "logs") }
                .buttonStyle(.plain)
                .font(.callout)

            Spacer()

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

// MARK: - Recording indicator with level meter

struct RecordingIndicator: View {
    let isRecording: Bool
    let peakLevel: Float
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? Color.red.opacity(0.2) : Color.clear)
                .frame(width: 28, height: 28)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .opacity(pulse ? 0 : 1)
                .animation(isRecording ? .easeOut(duration: 0.8).repeatForever(autoreverses: false) : .default, value: pulse)

            Circle()
                .fill(isRecording ? Color.red : Color.gray.opacity(0.4))
                .frame(width: 12, height: 12)
        }
        .frame(width: 28, height: 28)
        .onAppear { if isRecording { pulse = true } }
        .onChange(of: isRecording) { _, rec in pulse = rec }
    }
}

// MARK: - Recording row

struct RecordingRow: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.displayName)
                    .font(.callout)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(recording.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let model = recording.transcribedWithModel {
                        Text("·")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 4) {
                    if recording.transcriptionStatus == .complete {
                        Button(action: {
                            appState.loadTranscript(for: recording)
                            openWindow(id: "transcript")
                        }) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .help("View transcript")

                        Menu {
                            Button("Export as Markdown") { appState.exportTranscript(recording: recording, format: .markdown) }
                            Button("Export as Text") { appState.exportTranscript(recording: recording, format: .plainText) }
                            Button("Export as PDF") { appState.exportTranscript(recording: recording, format: .pdf) }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Export")
                    }

                    Button(action: { appState.deleteRecording(recording) }) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var statusIcon: some View {
        Group {
            switch recording.transcriptionStatus {
            case .complete:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            case .transcribing:
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            case .pending:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .frame(width: 14)
    }
}

// MARK: - Search result row

struct SearchResultRow: View {
    let result: (recordingID: Int64, text: String, startTime: Double)
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var isHovered = false

    var recording: Recording? {
        appState.recordings.first { $0.id == result.recordingID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let rec = recording {
                Text(rec.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(result.text)
                .font(.callout)
                .lineLimit(2)
            Text(formatTime(result.startTime))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHovered ? Color.primary.opacity(0.06) : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if let rec = recording {
                appState.loadTranscript(for: rec)
                openWindow(id: "transcript")
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}

