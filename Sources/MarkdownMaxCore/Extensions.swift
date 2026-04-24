import Foundation

public extension TimeInterval {
    var durationFormatted: String {
        let m = Int(self) / 60
        let s = Int(self) % 60
        return String(format: "%d:%02d", m, s)
    }
}

public extension String {
    /// Strips Whisper special tokens like `<|startoftranscript|>`, `<|en|>`, etc.
    var strippingWhisperTokens: String {
        replacing(#/<\|[^|>]*\|>/#, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
