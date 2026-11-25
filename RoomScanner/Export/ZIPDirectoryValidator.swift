import Foundation

/// Bounded structural validation. Does not claim to decompress or validate CRCs.
enum ZIPDirectoryValidator {
    static func validate(_ url: URL) throws {
        let file = try FileHandle(forReadingFrom:url); defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 22,size <= 1_073_741_824 else { throw CocoaError(.fileReadCorruptFile) }
        func read(_ offset: UInt64,_ count: Int) throws -> [UInt8] {
            guard offset <= size,UInt64(count) <= size-offset else { throw CocoaError(.fileReadCorruptFile) }
            try file.seek(toOffset:offset)
            let bytes = Array(try file.read(upToCount:count) ?? Data())
            guard bytes.count == count else { throw CocoaError(.fileReadCorruptFile) }; return bytes
        }
        func n(_ b: [UInt8],_ i: Int,_ count: Int) -> UInt64 {
            (0..<count).reduce(0) { $0 | UInt64(b[i+$1]) << ($1*8) }
        }
        let tail = try read(size-min(size,65_557),Int(min(size,65_557)))
        guard let end = stride(from:tail.count-22,through:0,by:-1).first(where:{ n(tail,$0,4) == 0x06054b50 && $0+22+Int(n(tail,$0+20,2)) == tail.count }) else { throw CocoaError(.fileReadCorruptFile) }
        let count = Int(n(tail,end+10,2)),length = n(tail,end+12,4),start = n(tail,end+16,4)
        guard n(tail,end+4,2) == 0,n(tail,end+6,2) == 0,n(tail,end+8,2) == UInt64(count),count <= 10_000,
              start+length == size-UInt64(tail.count-end) else { throw CocoaError(.fileReadCorruptFile) }
        var cursor = start,total: UInt64 = 0,paths = Set<String>(),files = Set<String>(),ranges: [(UInt64,UInt64)] = []
        for _ in 0..<count {
            try Task.checkCancellation()
            let h = try read(cursor,46)
            let nameLength = Int(n(h,28,2)),extra = Int(n(h,30,2)),comment = Int(n(h,32,2))
            guard n(h,0,4) == 0x02014b50,n(h,8,2)&1 == 0,[0,8].contains(n(h,10,2)),n(h,34,2) == 0 else { throw CocoaError(.fileReadCorruptFile) }
            let nameBytes = try read(cursor+46,nameLength)
            guard let name = String(bytes:nameBytes,encoding:.utf8),!name.isEmpty,!name.hasPrefix("/"),!name.contains("//"),!name.contains("\\"),!name.contains(":"),!name.unicodeScalars.contains(where:{ CharacterSet.controlCharacters.contains($0) }),
                  !name.split(separator:"/").contains(where:{ $0 == "." || $0 == ".." }),(n(h,38,4)>>16 & 0xF000) != 0xA000 else { throw CocoaError(.fileReadCorruptFile) }
            let key = name.trimmingCharacters(in:CharacterSet(charactersIn:"/")).precomposedStringWithCanonicalMapping.lowercased()
            guard paths.insert(key).inserted else { throw CocoaError(.fileReadCorruptFile) }
            if !name.hasSuffix("/") { files.insert(key) }
            let offset = n(h,42,4),local = try read(offset,30)
            guard offset < start,n(local,0,4) == 0x04034b50,n(local,6,2) == n(h,8,2),n(local,8,2) == n(h,10,2),
                  n(local,26,2) == UInt64(nameLength),try read(offset+30,nameLength) == nameBytes,
                  offset+30+UInt64(nameLength)+n(local,28,2)+n(h,20,4) <= start else { throw CocoaError(.fileReadCorruptFile) }
            ranges.append((offset,offset+30+UInt64(nameLength)+n(local,28,2)+n(h,20,4)))
            total += n(h,24,4); guard total <= 1_073_741_824 else { throw CocoaError(.fileReadTooLarge) }
            cursor += 46+UInt64(nameLength+extra+comment)
            guard cursor <= start+length else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard cursor == start+length else { throw CocoaError(.fileReadCorruptFile) }
        for path in paths {
            var parts = path.split(separator:"/")
            while parts.count > 1 { parts.removeLast(); let ancestor = parts.joined(separator:"/");
                guard !files.contains(ancestor) else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        let ordered = ranges.sorted { $0.0 < $1.0 }
        for i in ordered.indices.dropFirst() { guard ordered[i-1].1 <= ordered[i].0 else { throw CocoaError(.fileReadCorruptFile) } }
    }
}
