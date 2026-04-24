import SwiftUI
import AppKit
import MarkdownMaxCore

// MARK: - NSTextView-backed transcript view (full cross-segment selection + clickable timestamps)

struct TranscriptTextView: NSViewRepresentable {
    let segments: [Transcript]
    let activeSegmentID: Int64?
    let showTimestamps: Bool
    let onSeek: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let sv = NSTextView.scrollableTextView()
        sv.drawsBackground = false
        sv.borderType = .noBorder
        guard let tv = sv.documentView as? NSTextView else { return sv }
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 16, height: 16)
        tv.delegate = context.coordinator
        tv.linkTextAttributes = [
            .foregroundColor: NSColor.tertiaryLabelColor,
            .underlineStyle: 0,
            .cursor: NSCursor.pointingHand
        ]
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) {
        guard let tv = sv.documentView as? NSTextView else { return }
        context.coordinator.onSeek = onSeek

        let segIDs = segments.map(\.id)
        let speakerLabels = segments.map(\.speaker)
        if context.coordinator.lastSegmentIDs != segIDs
            || context.coordinator.lastShowTimestamps != showTimestamps
            || context.coordinator.lastSpeakerLabels != speakerLabels {
            context.coordinator.lastSegmentIDs = segIDs
            context.coordinator.lastShowTimestamps = showTimestamps
            context.coordinator.lastSpeakerLabels = speakerLabels
            let (attrStr, ranges) = buildContent()
            tv.textStorage?.setAttributedString(attrStr)
            context.coordinator.segmentRanges = ranges
        }

        applyHighlight(tv: tv, ranges: context.coordinator.segmentRanges)
    }

    private func speakerColor(for label: String) -> NSColor {
        switch label {
        case "SPEAKER_00": return .systemGreen
        case "SPEAKER_01": return .systemBlue
        case "SPEAKER_02": return .systemOrange
        case "SPEAKER_03": return .systemPurple
        default: return .systemGray
        }
    }

    private func speakerChip(for label: String) -> NSAttributedString {
        let color = speakerColor(for: label)
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        return NSAttributedString(string: label.uppercased() + "\n", attributes: attrs)
    }

    private func buildContent() -> (NSAttributedString, [NSRange]) {
        let result = NSMutableAttributedString()
        var ranges: [NSRange] = []
        let bodyFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let tsFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.paragraphSpacing = 6

        let hasSpeakers = segments.contains(where: { $0.speaker != nil })

        for (i, seg) in segments.enumerated() {
            let prevSpeaker = i > 0 ? segments[i - 1].speaker : nil
            if hasSpeakers, let speaker = seg.speaker, speaker != prevSpeaker {
                if i > 0 {
                    result.append(NSAttributedString(string: "\n",
                        attributes: [.font: bodyFont, .paragraphStyle: para]))
                }
                result.append(speakerChip(for: speaker))
            }

            if showTimestamps {
                let ts = seg.startTime.durationFormatted
                let chip = NSMutableAttributedString(string: ts + "  ")
                let tsLen = (ts as NSString).length
                chip.addAttributes([
                    .font: tsFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .link: URL(string: "seek://\(Int(seg.startTime * 1000))")!,
                    .paragraphStyle: para
                ], range: NSRange(location: 0, length: tsLen))
                chip.addAttributes([.font: tsFont, .paragraphStyle: para],
                                    range: NSRange(location: tsLen, length: 2))
                result.append(chip)
            }

            let textStart = result.length
            let body = NSMutableAttributedString(string: seg.text)
            body.addAttributes([
                .font: bodyFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para
            ], range: NSRange(location: 0, length: (seg.text as NSString).length))
            result.append(body)
            ranges.append(NSRange(location: textStart, length: (seg.text as NSString).length))

            if i < segments.count - 1 {
                result.append(NSAttributedString(string: "\n",
                    attributes: [.font: bodyFont, .paragraphStyle: para]))
            }
        }
        return (result, ranges)
    }

    private func applyHighlight(tv: NSTextView, ranges: [NSRange]) {
        guard let lm = tv.layoutManager, let ts = tv.textStorage else { return }
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: ts.length))
        guard let activeID = activeSegmentID,
              let idx = segments.firstIndex(where: { $0.id == activeID }),
              idx < ranges.count else { return }
        lm.addTemporaryAttribute(.backgroundColor,
                                  value: NSColor.controlAccentColor.withAlphaComponent(0.2),
                                  forCharacterRange: ranges[idx])
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSeek: ((TimeInterval) -> Void)?
        var lastSegmentIDs: [Int64] = []
        var lastShowTimestamps: Bool = true
        var lastSpeakerLabels: [String?] = []
        var segmentRanges: [NSRange] = []

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            guard let url = link as? URL, url.scheme == "seek",
                  let ms = Int(url.host ?? "") else { return false }
            onSeek?(Double(ms) / 1000.0)
            return true
        }
    }
}

// MARK: - Visual effect blur background

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
    }
}
