import Foundation
import CryptoKit

enum ExportChecksum {
    static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom:url)
        defer { try? file.close() }
        var hash = SHA256()
        while true {
            try Task.checkCancellation()
            let chunk = try file.read(upToCount:1_048_576) ?? Data()
            if chunk.isEmpty { break }; hash.update(data:chunk)
        }
        return hash.finalize().map { String(format:"%02x",$0) }.joined()
    }
}
