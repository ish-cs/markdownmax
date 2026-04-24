import AVFoundation
import MarkdownMaxCore
import SwiftUI

// MARK: - MainView

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var selectedIDs: Set<Int64> = []
    @State private var showDeleteConfirmation = false
    @State private var showMergeConfirmation = false
    @FocusState private var searchFocused: Bool

    private var mergeTargets: [Recording] {
        appState.recordings
            .filter { selectedIDs.contains($0.id) }
            .sorted { $0.dateCreated < $1.dateCreated }
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
                } else {
                    if !appState.allSubjects.isEmpty {
                        subjectFilterBar
                        Divider()
                    }
                    recordingsSidebar
                }

                Divider()

                // Recording controls — pinned to bottom-left of sidebar
                RecordingControlView()
                    .environmentObject(appState)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.clear.contentShape(Rectangle()).onTapGesture { selectedIDs = [] })
            .navigationTitle("")
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if selectedIDs.contains(-1) {
                RecordingInProgressView()
                    .environmentObject(appState)
            } else if selectedIDs.count == 1, let id = selectedIDs.first,
                      let recording = appState.recordings.first(where: { $0.id == id }) {
                RecordingDetailView(recording: recording)
                    .environmentObject(appState)
                    .id(id)
            } else if selectedIDs.count > 1 {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.badge.plus").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("\(selectedIDs.count) recordings selected").font(.headline)
                    Button("Merge \(selectedIDs.count) Recordings") { showMergeConfirmation = true }
                        .buttonStyle(PebblePillStyle())
                    Text("Oldest to newest · audio and transcripts combined")
                        .font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a Recording",
                                       systemImage: "waveform",
                                       description: Text("Choose a recording from the list, or start a new one."))
            }
        }
        .background(
            Group {
                Button("") { searchFocused = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("") { selectedIDs = [] }
                    .keyboardShortcut(.escape, modifiers: [])
            }
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
            if selectedIDs.isEmpty {
                if appState.audioRecorder.isRecording {
                    selectedIDs = [-1]
                } else if let first = appState.recordings.first(where: { $0.id != appState.currentRecordingID }) {
                    appState.loadTranscript(for: first)
                    selectedIDs = [first.id]
                }
            }
        }
        .onChange(of: selectedIDs) { _, ids in
            guard ids.count == 1, let id = ids.first, id != -1,
                  let rec = appState.recordings.first(where: { $0.id == id }) else { return }
            appState.loadTranscript(for: rec)
        }
        .onChange(of: appState.audioRecorder.isRecording) { _, isRecording in
            if isRecording { selectedIDs = [-1] }
        }
        .onChange(of: appState.lastFinishedRecordingID) { _, id in
            if let id {
                if let recording = appState.recordings.first(where: { $0.id == id }) {
                    appState.loadTranscript(for: recording)
                    selectedIDs = [id]
                } else if let first = appState.recordings.first {
                    appState.loadTranscript(for: first)
                    selectedIDs = [first.id]
                }
                appState.lastFinishedRecordingID = nil
            }
        }
        .onDeleteCommand {
            guard selectedIDs.count == 1, let id = selectedIDs.first, id != -1 else { return }
            showDeleteConfirmation = true
        }
        .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Merge \(mergeTargets.count) recordings?",
            isPresented: $showMergeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Merge") { appState.mergeRecordings(selectedIDs) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Audio and transcripts will be combined oldest to newest. This cannot be undone.")
        }
        .background(
            Button("") { deleteSelected() }
                .keyboardShortcut(.delete, modifiers: .command)
                .hidden()
        )
    }

    // MARK: - Subject filter bar

    private var subjectFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(appState.allSubjects, id: \.self) { subject in
                    let isSelected = appState.subjectFilter == subject
                    Button(action: {
                        appState.subjectFilter = isSelected ? nil : subject
                    }) {
                        Text(subject)
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .foregroundStyle(isSelected ? .black : .secondary)
                            .background(isSelected ? Color.mmGreen : Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Sidebar

    private var recordingsSidebar: some View {
        Group {
            let isCapturing = appState.audioRecorder.isRecording
            let visibleRecordings = appState.filteredRecordings.filter {
                $0.id != appState.currentRecordingID
            }

            if !isCapturing && visibleRecordings.isEmpty {
                ContentUnavailableView("No Recordings",
                                       systemImage: "waveform.slash",
                                       description: Text("Tap Record to start capturing a lecture."))
            } else {
                List(selection: $selectedIDs) {
                    // Live row — always at top when recording
                    if isCapturing {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(appState.audioRecorder.isPaused ? Color.orange : Color.mmRed)
                                .frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(appState.audioRecorder.isPaused ? "Paused" : "Recording…")
                                    .font(.callout.bold())
                                Text(appState.audioRecorder.duration.durationFormatted)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(appState.audioRecorder.isPaused ? .orange : Color.mmRed)
                            }
                        }
                        .tag(Int64(-1))
                        .listRowBackground(
                            (appState.audioRecorder.isPaused ? Color.orange : Color.mmRed).opacity(0.07)
                        )
                    }

                    ForEach(groupedRecordings(visibleRecordings), id: \.label) { group in
                        Section(group.label) {
                            ForEach(group.recordings) { recording in
                                RecordingSidebarRow(
                                    recording: recording,
                                    selectedIDs: selectedIDs,
                                    onMerge: { showMergeConfirmation = true }
                                )
                                .tag(recording.id)
                                .environmentObject(appState)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private struct DayGroup {
        let label: String
        let recordings: [Recording]
    }

    private func groupedRecordings(_ recordings: [Recording]) -> [DayGroup] {
        let cal = Calendar.current
        var buckets: [Date: [Recording]] = [:]
        for r in recordings {
            let day = cal.startOfDay(for: r.dateCreated)
            buckets[day, default: []].append(r)
        }
        return buckets
            .sorted { $0.key > $1.key }
            .map { DayGroup(label: dayLabel($0.key), recordings: $0.value) }
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt.string(from: date)
    }

    // MARK: - Delete

    private func deleteSelected() {
        guard selectedIDs.count == 1, let id = selectedIDs.first, id != -1,
              let recording = appState.recordings.first(where: { $0.id == id }) else { return }
        let next = appState.recordings.first(where: { $0.id != id && $0.id != appState.currentRecordingID })
        if let next {
            appState.loadTranscript(for: next)
            selectedIDs = [next.id]
        } else {
            selectedIDs = appState.audioRecorder.isRecording ? [-1] : []
        }
        appState.deleteRecording(recording)
    }

    // MARK: - Search results

    private var searchResultsSidebar: some View {
        Group {
            if appState.searchResults.isEmpty {
                ContentUnavailableView.search(text: appState.searchQuery)
            } else {
                List(Array(appState.searchResults.enumerated()), id: \.offset, selection: $selectedIDs) { _, result in
                    VStack(alignment: .leading, spacing: 3) {
                        if let rec = appState.recordings.first(where: { $0.id == result.recordingID }) {
                            Text(rec.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(result.text).font(.callout).lineLimit(2)
                        Text(result.startTime.durationFormatted)
                            .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                    }
                    .tag(result.recordingID)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIDs = [result.recordingID]
                        if let rec = appState.recordings.first(where: { $0.id == result.recordingID }) {
                            appState.loadTranscript(for: rec)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}

// MARK: - Recording control buttons

struct RecordingControlView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            if appState.audioRecorder.isRecording {
                TimerPill(
                    text: appState.audioRecorder.duration.durationFormatted,
                    dotColor: appState.audioRecorder.isPaused ? .orange : .mmRed
                )

                Button(action: {
                    if appState.audioRecorder.isPaused { appState.resumeRecording() }
                    else { appState.pauseRecording() }
                }) {
                    Image(systemName: appState.audioRecorder.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(PebbleCircleStyle(fill: .orange))
                .help(appState.audioRecorder.isPaused ? "Resume" : "Pause")

                Button(action: { appState.stopRecording() }) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(PebbleCircleStyle(fill: .mmRed))
                .help("Stop and transcribe")
            } else {
                Button(action: { appState.startRecording() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "mic.fill")
                        Text("Record")
                    }
                }
                .buttonStyle(PebblePillStyle())
                .help("Start recording")
            }
        }
    }
}

// MARK: - Sidebar row

struct RecordingSidebarRow: View {
    let recording: Recording
    let selectedIDs: Set<Int64>
    let onMerge: () -> Void
    @EnvironmentObject var appState: AppState
    @State private var isEditing = false
    @State private var draftName = ""
    @State private var showDeleteConfirm = false
    @State private var showSubjectEditor = false
    @State private var subjectDraft = ""

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
                    Text(recording.durationFormatted).monospacedDigit()
                    Text("·").foregroundStyle(.tertiary)
                    Text(recording.dateFormatted)
                    if let subject = recording.subject {
                        Text("·").foregroundStyle(.tertiary)
                        Text(subject)
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.mmGreen.opacity(0.15))
                            .foregroundStyle(Color.mmGreen)
                            .clipShape(Capsule())
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            if selectedIDs.count >= 2 && selectedIDs.contains(recording.id) {
                Button("Merge \(selectedIDs.count) Recordings") { onMerge() }
                Divider()
            }
            Button("Rename") { draftName = recording.displayName; isEditing = true }
            Button("Retranscribe") { appState.retranscribeRecording(recording) }
            Divider()
            Button(recording.subject == nil ? "Set Subject…" : "Change Subject…") {
                subjectDraft = recording.subject ?? ""
                showSubjectEditor = true
            }
            if recording.subject != nil {
                Button("Clear Subject") { appState.setSubject(for: recording, subject: nil) }
            }
            Divider()
            Button("Delete", role: .destructive) { showDeleteConfirm = true }
        }
        .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { appState.deleteRecording(recording) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSubjectEditor) {
            SubjectEditorSheet(subject: $subjectDraft) {
                let s = subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                appState.setSubject(for: recording, subject: s.isEmpty ? nil : s)
                showSubjectEditor = false
            } onCancel: {
                showSubjectEditor = false
            }
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
            Circle().fill(Color.mmGreen).frame(width: 7, height: 7)
        case .transcribing:
            ProgressView().scaleEffect(0.55).frame(width: 7, height: 7)
        case .failed:
            Circle().fill(Color.mmRed).frame(width: 7, height: 7)
        case .pending:
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 7, height: 7)
        }
    }
}

// MARK: - Subject editor sheet

struct SubjectEditorSheet: View {
    @Binding var subject: String
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Set Subject").font(.headline)
            TextField("e.g. Biology 101", text: $subject)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit { onSave() }
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 300)
    }
}

// MARK: - Audio level meter

struct AudioLevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(meterColor)
                    .frame(width: max(4, geo.size.width * CGFloat(level)))
                    .animation(.easeOut(duration: 0.06), value: level)
            }
        }
        .frame(height: 6)
    }

    private var meterColor: Color {
        if level > 0.8 { return .red }
        if level > 0.5 { return .yellow }
        return .green
    }
}

// MARK: - Recording in progress view

struct RecordingInProgressView: View {
    @EnvironmentObject var appState: AppState

    private var isPaused: Bool { appState.audioRecorder.isPaused }
    private var accentColor: Color { isPaused ? .orange : .mmRed }

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                Circle().fill(accentColor).frame(width: 7, height: 7)
                Text(isPaused ? "Paused" : "Recording")
                    .font(.callout.bold())
                    .foregroundStyle(accentColor)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            Divider()

            // Main content
            VStack(spacing: 28) {
                Spacer()

                // Large Pebble-style dark timer pill
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 10, height: 10)
                            .opacity(isPaused ? 0.6 : 1)
                        Text(appState.audioRecorder.duration.durationFormatted)
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(Color.mmDark)
                    .clipShape(Capsule())

                    Text(isPaused ? "Recording paused" : "Recording in progress…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                // Waveform meter
                if !isPaused {
                    VStack(spacing: 8) {
                        AudioLevelMeter(level: appState.audioRecorder.peakLevel)
                            .frame(maxWidth: 240, maxHeight: 6)
                        Text("Transcript generated automatically on stop")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Bookmark button
                if !isPaused {
                    Button(action: { appState.addBookmark() }) {
                        HStack(spacing: 5) {
                            Image(systemName: "bookmark.fill")
                            Text("Bookmark")
                        }
                    }
                    .buttonStyle(PebblePillStyle(fill: Color.secondary.opacity(0.12), fg: .primary))
                    .help("Mark current moment (⌘⇧B)")
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Recording detail view

struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState
    @StateObject private var player = AudioPlayer()
    @State private var copyFeedback = false
    @State private var isSeeking = false
    @State private var seekTime: Double = 0
    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var isEditingSubject = false
    @State private var subjectDraft = ""

    private var segments: [Transcript] {
        appState.transcriptSegments.filter { $0.recordingID == recording.id }
    }

    private var fullText: String { segments.map(\.text).joined(separator: " ") }

    private var copyText: String {
        if appState.showTimestamps {
            segments.map { "[\($0.startTime.durationFormatted)] \($0.text.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n")
        } else {
            segments.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        }
    }

    private var activeSegment: Transcript? {
        segments.first { $0.startTime <= player.currentTime && player.currentTime < $0.endTime }
    }

    private var recordingBookmarks: [Bookmark] {
        appState.bookmarks.filter { $0.recordingID == recording.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if isEditingTitle {
                        TextField("Name", text: $titleDraft)
                            .font(.headline).textFieldStyle(.plain)
                            .onSubmit { commitTitleRename() }
                            .onExitCommand { isEditingTitle = false }
                    } else {
                        Text(recording.displayName)
                            .font(.headline)
                            .onTapGesture { titleDraft = recording.displayName; isEditingTitle = true }
                    }
                    HStack(spacing: 4) {
                        Text(recording.durationFormatted).font(.caption).foregroundStyle(.secondary)
                        if isEditingSubject {
                            TextField("Subject", text: $subjectDraft)
                                .textFieldStyle(.plain)
                                .font(.caption.bold())
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 120)
                                .onSubmit { commitSubject() }
                                .onExitCommand { isEditingSubject = false }
                        } else if let subject = recording.subject {
                            Text("·").foregroundStyle(.tertiary).font(.caption)
                            Text(subject)
                                .font(.caption2.bold())
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.mmGreen.opacity(0.15))
                                .foregroundStyle(Color.mmGreen)
                                .clipShape(Capsule())
                                .onTapGesture { subjectDraft = subject; isEditingSubject = true }
                        } else {
                            Button("+ subject") { subjectDraft = ""; isEditingSubject = true }
                                .buttonStyle(.plain)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                Button { appState.showTimestamps.toggle() } label: {
                    Image(systemName: "timer")
                        .font(.caption.bold())
                        .foregroundStyle(appState.showTimestamps ? Color.mmGreen : .secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.showTimestamps ? "Hide timestamps" : "Show timestamps")
                if !fullText.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(copyText, forType: .string)
                        copyFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyFeedback = false }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: copyFeedback ? "checkmark" : "doc.on.clipboard")
                            Text(copyFeedback ? "Copied!" : "Copy")
                        }
                        .font(.caption.bold())
                    }
                    .buttonStyle(PebblePillStyle(
                        fill: copyFeedback ? Color.mmGreen : Color.secondary.opacity(0.12),
                        fg: copyFeedback ? .black : .primary
                    ))
                }
            }
            .padding(16)
            .background(VisualEffectView(material: .headerView, blendingMode: .withinWindow))

            Divider()

            if player.duration > 0 { playbackBar; Divider() }

            if !recordingBookmarks.isEmpty { bookmarksStrip; Divider() }

            contentBody
        }
        .onAppear { player.load(url: URL(fileURLWithPath: recording.filePath)) }
        .onDisappear { player.stop() }
        .background(
            Group {
                Button("") { if player.duration > 0 { player.togglePlayback() } }
                    .keyboardShortcut(.space, modifiers: [])
                Button("") { stepRate(by: 1) }
                    .keyboardShortcut(".", modifiers: .shift)
                Button("") { stepRate(by: -1) }
                    .keyboardShortcut(",", modifiers: .shift)
            }
            .hidden()
        )
    }

    private static let rateSteps: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    private func stepRate(by delta: Int) {
        let steps = Self.rateSteps
        let current = player.playbackRate
        let idx = steps.firstIndex(where: { abs($0 - current) < 0.01 }) ?? 1
        let next = max(0, min(steps.count - 1, idx + delta))
        player.setRate(steps[next])
    }

    private var playbackBar: some View {
        VStack(spacing: 6) {
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
            .tint(Color.mmGreen)
            .padding(.horizontal, 16)

            HStack {
                // Dark pill for current time
                Text(player.currentTime.durationFormatted)
                    .font(.system(.caption, design: .rounded).bold().monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.mmDark)
                    .clipShape(Capsule())

                Spacer()

                // Green play/pause button
                Button(action: player.togglePlayback) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Color.mmGreen)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 8) {
                    Menu {
                        ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button(formatRate(rate)) { player.setRate(rate) }
                        }
                    } label: {
                        Text(formatRate(player.playbackRate))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                    Text(player.duration.durationFormatted)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(VisualEffectView(material: .headerView, blendingMode: .behindWindow))
    }

    private func formatRate(_ rate: Float) -> String {
        switch rate {
        case 0.75: return "0.75×"
        case 1.0:  return "1×"
        case 1.25: return "1.25×"
        case 1.5:  return "1.5×"
        case 2.0:  return "2×"
        default:   return String(format: "%.2g×", rate)
        }
    }

    private var bookmarksStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.caption2).foregroundStyle(Color.mmGreen)
                ForEach(recordingBookmarks) { bookmark in
                    Button(action: {
                        player.seek(to: bookmark.time)
                        if !player.isPlaying { player.togglePlayback() }
                    }) {
                        Text(bookmark.time.durationFormatted)
                            .font(.system(.caption, design: .rounded).bold().monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.mmDark)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete Bookmark", role: .destructive) {
                            appState.deleteBookmark(bookmark)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
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
                let remaining: TimeInterval? = svc.estimatedRemainingSeconds
                    ?? (progress > 0.02 && elapsed > 3 ? (elapsed / progress) * (1 - progress) : nil)
                VStack(spacing: 12) {
                    Text("Transcribing…").foregroundStyle(.secondary)
                    ProgressView(value: progress).progressViewStyle(.linear).frame(maxWidth: 280)
                    HStack(spacing: 16) {
                        Label(elapsed.durationFormatted, systemImage: "timer")
                            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        if let remaining {
                            Label("\(remaining.durationFormatted) left", systemImage: "hourglass")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    if !svc.currentSegmentText.isEmpty {
                        Text(svc.currentSegmentText)
                            .foregroundStyle(.tertiary).font(.callout)
                            .multilineTextAlignment(.center).padding(.horizontal, 40)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .pending:
            ContentUnavailableView("Pending Transcription", systemImage: "clock",
                                   description: Text("Transcription will start automatically."))
        case .failed:
            VStack(spacing: 12) {
                ContentUnavailableView("Transcription Failed", systemImage: "exclamationmark.triangle",
                                       description: Text("Tap Retranscribe to try again."))
                Button("Retranscribe") { appState.retranscribeRecording(recording) }
                    .buttonStyle(PebblePillStyle())
            }
        }
    }

    private func commitTitleRename() {
        let name = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        guard !name.isEmpty, name != recording.displayName else { return }
        appState.renameRecording(recording, name: name)
    }

    private func commitSubject() {
        let s = subjectDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingSubject = false
        appState.setSubject(for: recording, subject: s.isEmpty ? nil : s)
    }
}
