import Foundation

/// Same-volume staging with a recoverable original until the final rename succeeds.
enum PackageReplacement {
    static func staging(for target: URL, fm: FileManager = .default) throws -> URL {
        let parent = target.deletingLastPathComponent()
        try fm.createDirectory(at:parent,withIntermediateDirectories:true)
        return parent.appendingPathComponent(".package-writing-"+UUID().uuidString,isDirectory:true)
    }
    static func backup(for target: URL) -> URL {
        target.deletingLastPathComponent().appendingPathComponent("."+target.lastPathComponent+".package-backup")
    }
    static func recover(_ target: URL, fm: FileManager = .default) throws {
        let old = backup(for:target)
        guard fm.fileExists(atPath:old.path) else { return }
        if fm.fileExists(atPath:target.path) { try fm.removeItem(at:old) }
        else { try fm.moveItem(at:old,to:target) }
    }
    static func commit(_ staging: URL, to target: URL, fm: FileManager = .default,
                       move: ((URL,URL) throws -> Void)? = nil) throws {
        let interval = PerformanceTrace.begin("PackageReplacement")
        defer { interval.end() }
        let rename = move ?? { try fm.moveItem(at:$0,to:$1) }
        try recover(target,fm:fm)
        let old = backup(for:target),existed = fm.fileExists(atPath:target.path)
        if existed { try rename(target,old) }
        do { try rename(staging,target) }
        catch {
            // Keep the backup if rollback itself fails; launch recovery will retry it.
            if existed { try fm.moveItem(at:old,to:target) }
            throw error
        }
        if existed { try? fm.removeItem(at:old) }
    }
    static func recover(in directory: URL) throws {
        let suffix = ".package-backup"
        for file in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
        where file.lastPathComponent.hasPrefix(".") && file.lastPathComponent.hasSuffix(suffix) {
            let name = String(file.lastPathComponent.dropFirst().dropLast(suffix.count))
            guard ["roomscan","housescan"].contains(URL(fileURLWithPath:name).pathExtension) else { continue }
            let target = directory.appendingPathComponent(name)
            try RoomPackage.coordinatedWrite(at:target,options:.forReplacing) { try recover($0) }
        }
    }
}
