import Foundation

public enum WaveformUtils {
    /// Encode float samples [0,1] to compact UInt8 Data
    public static func encode(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count)
        for s in samples {
            let clamped = max(0.0, min(1.0, s))
            data.append(UInt8(Int(clamped * 255)))
        }
        return data
    }

    /// Decode UInt8 Data back to float samples [0,1]
    public static func decode(_ data: Data) -> [Float] {
        data.map { Float($0) / 255.0 }
    }
}
