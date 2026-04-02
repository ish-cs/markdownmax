import XCTest
@testable import MarkdownMaxCore

final class WaveformUtilsTests: XCTestCase {

    // MARK: - Waveform encoding/decoding round-trip

    func testEncodeDecodeRoundTrip() {
        let samples: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0, 0.1, 0.9]
        let encoded = WaveformUtils.encode(samples)
        let decoded = WaveformUtils.decode(encoded)
        XCTAssertEqual(decoded.count, samples.count)
        for (original, restored) in zip(samples, decoded) {
            XCTAssertEqual(Double(original), Double(restored), accuracy: 0.004, "Waveform quantization error too large")
        }
    }

    func testEncodingClampsBelowZero() {
        let encoded = WaveformUtils.encode([-0.5])
        let decoded = WaveformUtils.decode(encoded)
        XCTAssertGreaterThanOrEqual(decoded[0], 0.0)
    }

    func testEncodingClampsAboveOne() {
        let encoded = WaveformUtils.encode([1.5])
        let decoded = WaveformUtils.decode(encoded)
        XCTAssertLessThanOrEqual(decoded[0], 1.0 + 0.004)
    }

    func testEncodeEmptyInput() {
        let encoded = WaveformUtils.encode([])
        XCTAssertEqual(encoded.count, 0)
        let decoded = WaveformUtils.decode(encoded)
        XCTAssertEqual(decoded.count, 0)
    }

    func testEncodeZeroIsZero() {
        let encoded = WaveformUtils.encode([0.0])
        XCTAssertEqual(encoded[0], 0)
    }

    func testEncodeOneIsMaxByte() {
        let encoded = WaveformUtils.encode([1.0])
        XCTAssertEqual(encoded[0], 255)
    }
}

// MARK: - Duration formatting tests

final class DurationFormattingTests: XCTestCase {

    func testDurationFormattingSeconds() {
        let duration: TimeInterval = 45
        XCTAssertEqual(duration.durationFormatted, "0:45")
    }

    func testDurationFormattingMinutes() {
        let duration: TimeInterval = 125
        XCTAssertEqual(duration.durationFormatted, "2:05")
    }

    func testDurationFormattingThreeMinutes() {
        let duration: TimeInterval = 185
        XCTAssertEqual(duration.durationFormatted, "3:05")
    }

    func testDurationFormattingZero() {
        let duration: TimeInterval = 0
        XCTAssertEqual(duration.durationFormatted, "0:00")
    }
}
