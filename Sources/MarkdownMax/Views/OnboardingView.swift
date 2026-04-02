import MarkdownMaxCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedModel: WhisperModelSize = .medium
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)
                Text("Welcome to MarkdownMax")
                    .font(.title2.bold())
                Text("Local, private transcription — no cloud required.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.horizontal, 24)

            Divider()
                .padding(.vertical, 20)

            // Model selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Choose a transcription model:")
                    .font(.headline)

                ForEach(WhisperModelSize.allCases, id: \.self) { model in
                    ModelOptionRow(model: model, isSelected: selectedModel == model) {
                        selectedModel = model
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Download button
            VStack(spacing: 8) {
                if let state = appState.modelDownloadManager.downloadStates[selectedModel], state.isDownloading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Downloading…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        TimelineView(.periodic(from: state.startedAt ?? Date(), by: 1)) { _ in
                            Text(state.elapsedFormatted)
                                .font(.callout)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    Button(action: {
                        appState.downloadModel(selectedModel)
                    }) {
                        Label("Download \(selectedModel.displayName)", systemImage: "arrow.down.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal, 24)
                }

                Button("Skip for now") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 28)
        }
        .frame(width: 420, height: 520)
    }
}

struct ModelOptionRow: View {
    let model: WhisperModelSize
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(model.rawValue.capitalized)
                            .font(.callout.bold())
                        if model == .medium {
                            Text("RECOMMENDED")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue)
                                .cornerRadius(4)
                        }
                    }
                    Text("\(model.displayName) · WER \(model.werPercent) · \(model.speedDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue.opacity(0.08) : Color.primary.opacity(0.04))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
