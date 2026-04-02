import Foundation

enum LogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
}

@MainActor
final class AppLogger: ObservableObject {
    static let shared = AppLogger()
    @Published private(set) var entries: [LogEntry] = []

    private init() {}

    func log(_ message: String, _ level: LogLevel = .info) {
        entries.insert(LogEntry(timestamp: Date(), level: level, message: message), at: 0)
        if entries.count > 500 { entries.removeLast() }
    }

    func clear() {
        entries.removeAll()
    }
}

func appLog(_ message: String, _ level: LogLevel = .info) {
    Task { @MainActor in AppLogger.shared.log(message, level) }
}
