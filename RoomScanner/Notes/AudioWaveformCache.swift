import Foundation
import AVFoundation
import CryptoKit

/// Bounded, disposable visualization cache. Audio samples never leave the device.
actor AudioWaveformCache {
    static let shared = AudioWaveformCache()
    private var values: [String:[Double]] = [:]
    private var order: [String] = []
    func peaks(for data:Data) throws -> [Double] {
        let key = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        if let cached = values[key] { return cached }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        defer { try? FileManager.default.removeItem(at:url) }
        try data.write(to:url,options:.atomic)
        let file = try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        guard file.length > 0,file.length <= 12_000_000,file.processingFormat.channelCount <= 8,
              let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:4096) else { throw CocoaError(.fileReadTooLarge) }
        var result = Array(repeating:0.0,count:64),offset:Int64 = 0
        while offset < file.length {
            try Task.checkCancellation()
            try file.read(into:buffer)
            guard buffer.frameLength > 0,let channels = buffer.floatChannelData else { break }
            for i in 0..<Int(buffer.frameLength) {
                let bucket = min(63,Int((offset+Int64(i))*64/file.length))
                for channel in 0..<Int(buffer.format.channelCount) {
                    let sample = Double(abs(channels[channel][i]))
                    if sample.isFinite { result[bucket] = max(result[bucket],min(1,sample)) }
                }
            }
            offset += Int64(buffer.frameLength)
        }
        let maximum = result.max() ?? 0
        if maximum > 0 { result = result.map { $0/maximum } }
        values[key] = result; order.append(key)
        if order.count > 32 { values.removeValue(forKey:order.removeFirst()) }
        return result
    }
}
