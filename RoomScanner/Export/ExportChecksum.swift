import Foundation
import CryptoKit

enum ExportChecksum {
    static func digest(_ data:Data) -> String { SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() }
    static func sha256(_ url: URL) throws -> String {
        try Task.checkCancellation()
        let file = try FileHandle(forReadingFrom:url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount:1_048_576) ?? Data()
            if chunk.isEmpty { break }; hash.update(data:chunk)
        }
        try Task.checkCancellation()
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
}
