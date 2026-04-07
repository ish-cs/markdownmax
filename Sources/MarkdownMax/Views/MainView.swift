import AVFoundation
import MarkdownMaxCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var selectedID: Int64?
    @State private var showDeleteConfirmation = false
    @FocusState private var searchFocused: Bool

    private var selectionBinding: Binding<Int64?> {
        Binding(
            get: { selectedID },
            set: { id in
                guard let id else { return }
                if id == -1 { selectedID = -1; return }  // live recording row
                guard let rec = appState.recordings.first(where: { $0.id == id }) else { return }
                appState.loadTranscript(for: rec)
                selectedID = id
            }
        )
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Search bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                    TextField("Search transcripts…", text: $appState.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .focused($searchFocused)
                        .onChange(of: appState.searchQuery) { _, _ in appState.performSearch() }
                    if !appState.searchQuery.isEmpty {
                        Button { appState.searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial)

                Divider()

                if !appState.searchQuery.isEmpty {
                    searchResultsSidebar
                } else if appState.recordings.isEmpty && !appState.audioRecorder.isRecording {
                    ContentUnavailableView("No Recordings",
                                           systemImage: "waveform.slash",
                                           description: Text("Click the menu bar icon to start recording."))
                } else {
                    List(selection: selectionBinding) {
                        if appState.audioRecorder.isRecording {
                            HStack(spacing: 8) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Recording…").font(.callout)
                                    Text(appState.audioRecorder.duration.durationFormatted)
                                        .font(.caption).foregroundStyle(.red).monospacedDigit()
                                }
                            }
                            .tag(Int64(-1))
                            .listRowBackground(Color.red.opacity(0.08))
                        }
                        ForEach(appState.recordings) { recording in
                            RecordingSidebarRow(recording: recording)
                                .tag(recording.id)
                                .environmentObject(appState)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
            .toolbar {
                if appState.audioRecorder.isRecording {
                    ToolbarItem(placement: .primaryAction) {
                        Text(appState.audioRecorder.duration.durationFormatted)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: appState.toggleRecording) {
                        Image(systemName: appState.audioRecorder.isRecording ? "waveform.circle.fill" : "waveform.circle")
                            .foregroundStyle(appState.audioRecorder.isRecording ? .red : .primary)
                            .font(.title3)
                    }
                    .help(appState.audioRecorder.isRecording ? "Stop recording" : "Start recording")
                }
            }
        } detail: {
            if selectedID == -1 {
                LiveRecordingView()
                    .environmentObject(appState)
            } else if let id = selectedID,
               let recording = appState.recordings.first(where: { $0.id == id }) {
                RecordingDetailView(recording: recording)
                    .environmentObject(appState)
                    .id(id)
            } else {
                ContentUnavailableView("Select a Recording",
                                       systemImage: "waveform",
                                       description: Text("Choose a recording from the list."))
            }
        }
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { openSettings() }) {
                    Image(systemName: "gear")
                }
                .help("Settings")
            }
        }
        .background(VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow))
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .onAppear {
            if selectedID == nil, let first = appState.recordings.first {
                appState.loadTranscript(for: first)
                selectedID = first.id
            }
        }
        .onChange(of: appState.audioRecorder.isRecording) { _, isRecording in
            if isRecording { selectedID = -1 }
        }
        .onChange(of: appState.selectedRecording?.id) { _, id in
            // Auto-switch only when viewing live view (selectedID == -1)
            guard let id, selectedID == -1 || selectedID == nil else { return }
            selectedID = id
        }
        .onDeleteCommand {
            guard selectedID != nil else { return }
            showDeleteConfirmation = true
        }
        .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
        .background(
            Button("") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .hidden()
        )
    }

    private func deleteSelected() {
        guard let id = selectedID,
              let recording = appState.recordings.first(where: { $0.id == id }) else { return }
        let next = appState.recordings.first(where: { $0.id != id })
        if let next {
            appState.loadTranscript(for: next)
            selectedID = next.id
        } else {
            selectedID = nil
        }
        appState.deleteRecording(recording)
    }

    private var searchResultsSidebar: some View {
        Group {
            if appState.searchResults.isEmpty {
                ContentUnavailableView.search(text: appState.searchQuery)
            } else {
                List(Array(appState.searchResults.enumerated()), id: \.offset, selection: $selectedID) { _, result in
                    VStack(alignment: .leading, spacing: 3) {
                        if let rec = appState.recordings.first(where: { $0.id == result.recordingID }) {
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
                    .tag(result.recordingID)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedID = result.recordingID
                        if let rec = appState.recordings.first(where: { $0.id == result.recordingID }) {
                            appState.loadTranscript(for: rec)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func formatTime(_ s: Double) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }

}

// MARK: - Sidebar row

struct RecordingSidebarRow: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState
    @State private var isEditing = false
    @State private var draftName = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 8) {
            statusIcon.frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.callout)
                        .onSubmit { commitRename() }
                        .onExitCommand { isEditing = false }
                } else {
                    Text(recording.displayName)
                        .font(.callout)
                        .onTapGesture(count: 2) {
                            draftName = recording.displayName
                            isEditing = true
                        }
                }
                HStack(spacing: 4) {
                    Text(recording.durationFormatted)
                        .monospacedDigit()
                    Text("·").foregroundStyle(.tertiary)
                    Text(recording.dateFormatted)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("Rename") {
                draftName = recording.displayName
                isEditing = true
            }
            Button("Retranscribe") {
                appState.retranscribeRecording(recording)
            }
            Divider()
            Button("Delete", role: .destructive) {
                showDeleteConfirm = true
            }
        }
        .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { appState.deleteRecording(recording) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func commitRename() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        guard !name.isEmpty, name != recording.displayName else { return }
        appState.renameRecording(recording, name: name)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch recording.transcriptionStatus {
        case .complete:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .transcribing:
            ProgressView().scaleEffect(0.6)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption)
        case .pending:
            Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
        }
    }
}

// MARK: - Detail view

struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState
    @StateObject private var player = AudioPlayer()
    @State private var copyFeedback = false
    @State private var isSeeking = false
    @State private var seekTime: Double = 0
    @State private var isEditingTitle = false
    @State private var titleDraft = ""

    private var segments: [Transcript] {
        appState.transcriptSegments.filter { $0.recordingID == recording.id }
    }

    private var fullText: String {
        segments.map(\.text).joined(separator: " ")
    }

    private var activeSegment: Transcript? {
        segments.first { $0.startTime <= player.currentTime && player.currentTime < $0.endTime }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if isEditingTitle {
                        TextField("Name", text: $titleDraft)
                            .font(.headline)
                            .textFieldStyle(.plain)
                            .onSubmit { commitTitleRename() }
                            .onExitCommand { isEditingTitle = false }
                    } else {
                        Text(recording.displayName)
                            .font(.headline)
                            .onTapGesture {
                                titleDraft = recording.displayName
                                isEditingTitle = true
                            }
                    }
                    Text(recording.durationFormatted).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    appState.showTimestamps.toggle()
                } label: {
                    Image(systemName: "timer")
                        .opacity(appState.showTimestamps ? 1 : 0.35)
                }
                .buttonStyle(.bordered)
                .help(appState.showTimestamps ? "Hide timestamps" : "Show timestamps")
                if !fullText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullText, forType: .string)
                        copyFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyFeedback = false }
                    } label: {
                        Label(copyFeedback ? "Copied!" : "Copy", systemImage: copyFeedback ? "checkmark" : "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            Divider()

            // Playback controls
            if player.duration > 0 {
                playbackBar
                Divider()
            }

            contentBody
        }
        .onAppear {
            player.load(url: URL(fileURLWithPath: recording.filePath))
        }
        .onDisappear { player.stop() }
        .background(
            Button("") { if player.duration > 0 { player.togglePlayback() } }
                .keyboardShortcut(.space, modifiers: [])
                .hidden()
        )
    }

    private var playbackBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isSeeking ? seekTime : player.currentTime },
                    set: { seekTime = $0 }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    isSeeking = editing
                    if !editing { player.seek(to: seekTime) }
                }
            )
            .padding(.horizontal, 16)

            HStack {
                Text(formatTime(player.currentTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .leading)

                Spacer()

                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(formatTime(player.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow))
    }

    @ViewBuilder
    private var contentBody: some View {
        switch recording.transcriptionStatus {
        case .complete:
            if segments.isEmpty {
                ContentUnavailableView("No Transcript", systemImage: "doc.text")
            } else {
                TranscriptTextView(
                    segments: segments,
                    activeSegmentID: activeSegment?.id,
                    showTimestamps: appState.showTimestamps,
                    onSeek: { time in
                        player.seek(to: time)
                        if !player.isPlaying { player.togglePlayback() }
                    }
                )
            }
        case .transcribing:
            TimelineView(.periodic(from: Date(), by: 1)) { _ in
                let svc = appState.transcriptionService
                let progress = svc.progress
                let elapsed = svc.transcriptionStartDate.map { Date().timeIntervalSince($0) } ?? 0
                // Prefer service's RTF-based estimate; fall back to elapsed-ratio formula
                let remaining: TimeInterval? = svc.estimatedRemainingSeconds
                    ?? (progress > 0.02 && elapsed > 3 ? (elapsed / progress) * (1 - progress) : nil)

                VStack(spacing: 12) {
                    Text("Transcribing…").foregroundStyle(.secondary)
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)
                    HStack(spacing: 16) {
                        Label(elapsed.durationFormatted, systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        if let remaining {
                            Label("\(remaining.durationFormatted) left", systemImage: "hourglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    if !svc.currentSegmentText.isEmpty {
                        Text(svc.currentSegmentText)
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .pending:
            ContentUnavailableView("Pending", systemImage: "clock",
                                   description: Text("Waiting to transcribe."))
        case .failed:
            ContentUnavailableView("Transcription Failed", systemImage: "exclamationmark.triangle",
                                   description: Text("Transcription could not be completed."))
        }
    }

    private func commitTitleRename() {
        let name = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        guard !name.isEmpty, name != recording.displayName else { return }
        appState.renameRecording(recording, name: name)
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Live Recording View

struct LiveRecordingView: View {
    @EnvironmentObject var appState: AppState

    private var live: LiveTranscriptionService { appState.liveTranscriptionService }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .opacity(0.9)
                Text("Recording")
                    .font(.headline)
                Text(appState.audioRecorder.duration.durationFormatted)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.red)
                Spacer()
                if !live.isActive {
                    Label("No model loaded", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            Divider()

            if !appState.liveTranscriptionEnabled {
                VStack(spacing: 8) {
                    Image(systemName: "waveform.slash")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Live transcription off")
                        .font(.callout.bold())
                        .foregroundStyle(.secondary)
                    Text("Transcript will load after recording ends.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if live.confirmedSegments.isEmpty && !live.isSpeaking {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text(live.isActive ? "Listening…" : "Transcription unavailable\nNo model loaded")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(live.confirmedSegments.enumerated()), id: \.offset) { _, seg in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(formatSec(seg.startTime))
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                        .frame(width: 36, alignment: .trailing)
                                    Text(seg.text)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 3)
                            }

                            if live.isTranscribingChunk || live.isSpeaking {
                                HStack(spacing: 8) {
                                    Text("  ").frame(width: 36)
                                    if live.isTranscribingChunk {
                                        HStack(spacing: 6) {
                                            ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                            Text("Transcribing…")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } else {
                                        HStack(spacing: 4) {
                                            ForEach(0..<3) { i in
                                                Circle()
                                                    .fill(.secondary)
                                                    .frame(width: 5, height: 5)
                                                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2), value: live.isSpeaking)
                                            }
                                        }
                                    }
                                }
                                .padding(.vertical, 6)
                                .id("speaking")
                            }
                        }
                        .textSelection(.enabled)
                        .padding(16)
                    }
                    .onChange(of: live.isSpeaking) { _, _ in
                        withAnimation { proxy.scrollTo("speaking") }
                    }
                    .onChange(of: live.confirmedSegments.count) { _, _ in
                        withAnimation { proxy.scrollTo("speaking") }
                    }
                }
            }
        }
    }

    private func formatSec(_ s: Double) -> String {
        let m = Int(s) / 60; let sec = Int(s) % 60
        return String(format: "%d:%02d", m, sec)
    }
}
