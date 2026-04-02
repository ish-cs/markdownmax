import MarkdownMaxCore
import SwiftUI

struct TranscriptView: View {
    @EnvironmentObject var appState: AppState
    @State private var copyFeedback = false

    var body: some View {
        VStack(spacing: 0) {
            if let recording = appState.selectedRecording {
                // Toolbar
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.displayName)
                            .font(.headline)
                        Text(recording.durationFormatted)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Spacer()

                    // Copy all
                    Button {
                        let fullText = appState.transcriptSegments.map(\.text).joined(separator: " ")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullText, forType: .string)
                        copyFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copyFeedback = false }
                    } label: {
                        Label(copyFeedback ? "Copied!" : "Copy All", systemImage: copyFeedback ? "checkmark" : "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    // Export menu
                    Menu("Export") {
                        Button("Export as Markdown (⌘⇧M)") {
                            appState.exportTranscript(recording: recording, format: .markdown)
                        }
                        Button("Export as Plain Text") {
                            appState.exportTranscript(recording: recording, format: .plainText)
                        }
                        Button("Export as PDF") {
                            appState.exportTranscript(recording: recording, format: .pdf)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)

                Divider()

                // Segments
                if appState.transcriptSegments.isEmpty {
                    emptyTranscript(status: recording.transcriptionStatus)
                } else {
                    transcriptBody
                }
            } else {
                ContentUnavailableView("No Recording Selected",
                                       systemImage: "waveform",
                                       description: Text("Select a recording to view its transcript."))
            }
        }
    }

    private var transcriptBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(appState.transcriptSegments) { segment in
                    TranscriptSegmentRow(segment: segment)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func emptyTranscript(status: Recording.TranscriptionStatus) -> some View {
        Group {
            switch status {
            case .transcribing:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Transcribing…")
                        .foregroundStyle(.secondary)
                    if !appState.transcriptionService.currentSegmentText.isEmpty {
                        Text(appState.transcriptionService.currentSegmentText)
                            .foregroundStyle(.tertiary)
                            .font(.callout)
                            .lineLimit(2)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed:
                ContentUnavailableView("Transcription Failed",
                                       systemImage: "exclamationmark.triangle",
                                       description: Text("Transcription could not be completed."))

            case .pending:
                ContentUnavailableView("Pending",
                                       systemImage: "clock",
                                       description: Text("Transcription will start shortly."))

            case .complete:
                ContentUnavailableView("No Transcript",
                                       systemImage: "doc.text",
                                       description: Text("No transcript segments found."))
            }
        }
    }
}

struct TranscriptSegmentRow: View {
    let segment: Transcript
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(segment.timeRangeFormatted)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 100, alignment: .trailing)
                .padding(.top, 3)

            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(isHovered ? Color.primary.opacity(0.04) : Color.clear)
        .cornerRadius(4)
        .onHover { isHovered = $0 }
    }
}
