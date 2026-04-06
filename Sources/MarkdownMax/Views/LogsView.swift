import SwiftUI

struct LogsView: View {
    @ObservedObject private var logger = AppLogger.shared

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(logger.entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { logger.clear() }
                    .buttonStyle(.plain)
                    .font(.callout)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            if logger.entries.isEmpty {
                ContentUnavailableView("No Logs", systemImage: "doc.text",
                                       description: Text("Logs will appear here as you use the app."))
            } else {
                List(logger.entries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(Self.timeFormatter.string(from: entry.timestamp))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 90, alignment: .leading)

                        Text(entry.level.rawValue)
                            .font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(levelColor(entry.level))
                            .frame(width: 36, alignment: .leading)

                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .listRowSeparator(.visible)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
}
