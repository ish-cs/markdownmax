import AppKit
import Foundation

public enum ExportFormat {
    case markdown
    case plainText
    case pdf
}

public struct ExportDocument {
    public let recording: Recording
    public let segments: [Transcript]
    public let format: ExportFormat

    public init(recording: Recording, segments: [Transcript], format: ExportFormat) {
        self.recording = recording
        self.segments = segments
        self.format = format
    }

    public var suggestedFilename: String {
        let base = recording.filename.replacingOccurrences(of: ".wav", with: "")
        switch format {
        case .markdown:  return "\(base).md"
        case .plainText: return "\(base).txt"
        case .pdf:       return "\(base).pdf"
        }
    }
}

public final class ExportService {
    public init() {}

    // MARK: - Markdown

    public func markdownContent(recording: Recording, segments: [Transcript]) -> String {
        var lines: [String] = []
        lines.append("# Transcript")
        lines.append("")
        lines.append("**Date:** \(recording.displayName)  ")
        lines.append("**Duration:** \(recording.durationFormatted)  ")
        if let model = recording.transcribedWithModel {
            lines.append("**Model:** \(model)  ")
        }
        lines.append("")
        lines.append("---")
        lines.append("")

        for seg in segments {
            let timestamp = "[\(seg.timeRangeFormatted)]"
            lines.append("\(timestamp) \(seg.text)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Plain Text

    public func plainTextContent(recording: Recording, segments: [Transcript]) -> String {
        var lines: [String] = []
        lines.append("Transcript")
        lines.append("==========")
        lines.append("Date: \(recording.displayName)")
        lines.append("Duration: \(recording.durationFormatted)")
        if let model = recording.transcribedWithModel {
            lines.append("Model: \(model)")
        }
        lines.append("")

        for seg in segments {
            lines.append("[\(seg.timeRangeFormatted)] \(seg.text)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Full text (no timestamps)

    public func fullText(segments: [Transcript]) -> String {
        segments.map(\.text).joined(separator: " ")
    }

    // MARK: - Save to file

    public func save(document: ExportDocument, to url: URL) throws {
        switch document.format {
        case .markdown:
            let content = markdownContent(recording: document.recording, segments: document.segments)
            try content.write(to: url, atomically: true, encoding: .utf8)

        case .plainText:
            let content = plainTextContent(recording: document.recording, segments: document.segments)
            try content.write(to: url, atomically: true, encoding: .utf8)

        case .pdf:
            try savePDF(document: document, to: url)
        }
    }

    // MARK: - PDF via NSPrintOperation

    private func savePDF(document: ExportDocument, to url: URL) throws {
        let content = markdownContent(recording: document.recording, segments: document.segments)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 595, height: 842))
        textView.string = content
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        let printInfo = NSPrintInfo.shared
        printInfo.jobDisposition = .save
        printInfo.dictionary()[NSPrintInfo.AttributeKey("NSJobSavingURL")] = url

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        op.run()
    }

    // MARK: - Save panel helper

    @MainActor
    public func showSavePanel(suggestedName: String, format: ExportFormat) async -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        switch format {
        case .markdown:
            panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        case .plainText:
            panel.allowedContentTypes = [.plainText]
        case .pdf:
            panel.allowedContentTypes = [.pdf]
        }

        let response = await panel.beginSheetModal(for: NSApp.mainWindow ?? NSWindow())
        return response == .OK ? panel.url : nil
    }
}
