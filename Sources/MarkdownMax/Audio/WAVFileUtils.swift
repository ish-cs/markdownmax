import Foundation

// Shared WAV file manipulation utilities used by AlwaysOnRecordingService and AppState.

/// Appends the audio payload of `sessionURL` (16 kHz Int16 mono WAV) to `masterURL`,
/// updating the RIFF and data chunk size fields in the master header.
func appendWAV(from sessionURL: URL, to masterURL: URL) {
    guard let sessionData = try? Data(contentsOf: sessionURL, options: .mappedIfSafe),
          sessionData.count > 44 else { return }
    let audioBytes = Data(sessionData[44...])
    guard !audioBytes.isEmpty,
          let handle = try? FileHandle(forUpdating: masterURL) else { return }
    defer { try? handle.close() }

    // seekToEndOfFile() returns the pre-append file size synchronously — no filesystem stat needed.
    let oldSize = Int(handle.seekToEndOfFile())
    handle.write(audioBytes)
    let newFileSize = oldSize + audioBytes.count

    guard newFileSize > 44 else { return }
    var riff = UInt32(newFileSize - 8).littleEndian
    var data = UInt32(newFileSize - 44).littleEndian
    handle.seek(toFileOffset: 4)
    handle.write(Data(bytes: &riff, count: 4))
    handle.seek(toFileOffset: 40)
    handle.write(Data(bytes: &data, count: 4))
}

/// Returns the exact audio duration of a standard PCM WAV file by reading the data-chunk size.
/// Falls back to nil if the file can't be read or doesn't look like a standard WAV.
func wavAudioDurationSeconds(at url: URL) -> Double? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let header = try? handle.read(upToCount: 44), header.count == 44 else { return nil }
    guard header[0...3].elementsEqual("RIFF".utf8),
          header[8...11].elementsEqual("WAVE".utf8) else { return nil }
    let sampleRate  = header[24...27].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    let bitsPerSample = header[34...35].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    let channels    = header[22...23].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    let dataSize    = header[40...43].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    let bytesPerSample = Int(bitsPerSample / 8) * Int(channels)
    guard bytesPerSample > 0, sampleRate > 0 else { return nil }
    return Double(Int(dataSize) / bytesPerSample) / Double(sampleRate)
}

/// Builds a 16 kHz Int16 mono WAV from raw PCM bytes.
func buildWAV(from audioData: Data.SubSequence) -> Data {
    let audioSize = UInt32(audioData.count)
    var wav = Data(capacity: 44 + audioData.count)
    func u32le(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
    func u16le(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    wav += "RIFF".data(using: .ascii)!
    wav += u32le(audioSize + 36)
    wav += "WAVE".data(using: .ascii)!
    wav += "fmt ".data(using: .ascii)!
    wav += u32le(16)
    wav += u16le(1)       // PCM
    wav += u16le(1)       // mono
    wav += u32le(16000)   // sample rate
    wav += u32le(32000)   // byte rate
    wav += u16le(2)       // block align
    wav += u16le(16)      // bits per sample
    wav += "data".data(using: .ascii)!
    wav += u32le(audioSize)
    wav += Data(audioData)
    return wav
}
