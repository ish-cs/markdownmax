import MarkdownMaxCore
import SwiftUI

/// Full recordings list window — accessible from menu bar or transcript header
struct RecordingListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedID: Int64?

    var body: some View {
        NavigationSplitView {
            List(appState.recordings, selection: $selectedID) { recording in
                RecordingListRow(recording: recording)
                    .tag(recording.id)
                    .contextMenu {
                        if recording.transcriptionStatus == .complete {
                            Button("View Transcript") {
                                appState.loadTranscript(for: recording)
                                openWindow(id: "transcript")
                            }
                            Menu("Export") {
                                Button("Markdown") { appState.exportTranscript(recording: recording, format: .markdown) }
                                Button("Plain Text") { appState.exportTranscript(recording: recording, format: .plainText) }
                                Button("PDF") { appState.exportTranscript(recording: recording, format: .pdf) }
                            }
                            Divider()
                        }
                        Button("Delete", role: .destructive) {
                            appState.deleteRecording(recording)
                        }
                    }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: appState.toggleRecording) {
                        Image(systemName: appState.audioRecorder.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                            .foregroundStyle(appState.audioRecorder.isRecording ? .red : .accentColor)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .searchable(text: $appState.searchQuery, prompt: "Search transcripts…")
            .onChange(of: appState.searchQuery) { _, _ in appState.performSearch() }
        } detail: {
            if let id = selectedID,
               let recording = appState.recordings.first(where: { $0.id == id }) {
                TranscriptDetailView(recording: recording)
                    .environmentObject(appState)
            } else {
                ContentUnavailableView("Select a Recording",
                                       systemImage: "waveform",
                                       description: Text("Choose a recording from the list."))
            }
        }
    }
}

struct RecordingListRow: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: 8) {
            statusIcon
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.displayName)
                    .font(.callout)
                HStack(spacing: 4) {
                    Text(recording.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let model = recording.transcribedWithModel {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(model)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var statusIcon: some View {
        Group {
            switch recording.transcriptionStatus {
            case .complete:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .transcribing:
                ProgressView().scaleEffect(0.6)
            case .failed:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
            case .pending:
                Image(systemName: "clock").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }
}

/// Inline transcript detail for the sidebar layout
struct TranscriptDetailView: View {
    let recording: Recording
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.displayName).font(.headline)
                    Text(recording.durationFormatted).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Menu("Export") {
                    Button("Markdown") { appState.exportTranscript(recording: recording, format: .markdown) }
                    Button("Plain Text") { appState.exportTranscript(recording: recording, format: .plainText) }
                    Button("PDF") { appState.exportTranscript(recording: recording, format: .pdf) }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(appState.transcriptSegments.filter { $0.recordingID == recording.id }) { seg in
                        TranscriptSegmentRow(segment: seg)
                    }
                }
                .padding(20)
            }
        }
        .onAppear { appState.loadTranscript(for: recording) }
    }
}
