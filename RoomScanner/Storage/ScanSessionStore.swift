import Foundation

struct ScanSession: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case house, room, technical }
    enum State: String, Codable { case scanning, paused, finalizing, completed, failed }
    var schemaVersion = 1
    let id: UUID
    let kind: Kind
    let projectID: UUID?
    var state = State.scanning
    let created: Date
    var updated: Date
}

/// Serialized disk transactions. Index entries are immutable commit records;
/// payloads become visible only after their index record is committed.
actor ScanSessionStore {
    struct Entry: Codable, Equatable, Identifiable {
        let id: UUID
        let sequence: Int
        let key: String
        let path: String
        let bytes: Int
        let metadata: [String:String]
        let created: Date
    }
    enum CrashPoint: CaseIterable { case afterPayload, afterIndex, afterManifest }
    typealias Fault = @Sendable (CrashPoint) throws -> Void
    @MainActor private static var localStore: ScanSessionStore?
    @MainActor static func local() throws -> ScanSessionStore {
        if let localStore { return localStore }
        let value = ScanSessionStore(root:try applicationSupportRoot()); localStore = value; return value
    }
    let root: URL
    private let fault: Fault
    init(root:URL, fault:@escaping Fault = { _ in }) { self.root = root; self.fault = fault }
    static func applicationSupportRoot() throws -> URL {
        try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "dWalkScan").appendingPathComponent("ScanSessions")
    }
    private func directory(_ id:UUID) -> URL { root.appendingPathComponent(id.uuidString,isDirectory:true) }
    private func check(_ url:URL) throws {
        guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path+"/") else { throw CocoaError(.fileReadNoPermission) }
        var current = url
        while current.path != root.deletingLastPathComponent().path {
            if FileManager.default.fileExists(atPath:current.path),try current.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink == true { throw CocoaError(.fileReadNoPermission) }
            if current.path == root.path { break }; current.deleteLastPathComponent()
        }
    }
    private func atomic(_ data:Data,to target:URL) throws {
        try check(target)
        let staging = try PackageReplacement.staging(for:target)
        defer { try? FileManager.default.removeItem(at:staging) }
        try data.write(to:staging,options:.atomic)
        try PackageReplacement.commit(staging,to:target)
    }
    private func manifest(_ session:ScanSession) throws {
        try atomic(JSONEncoder().encode(session),to:directory(session.id).appendingPathComponent("session.json"))
    }
    func create(kind:ScanSession.Kind,projectID:UUID?,id:UUID = UUID()) throws -> ScanSession {
        let folder = directory(id); try check(folder)
        if FileManager.default.fileExists(atPath:folder.path) {
            let existing = try read(id)
            guard existing.kind == kind,existing.projectID == projectID else { throw CocoaError(.fileWriteFileExists) }
            return existing
        }
        let staging = try PackageReplacement.staging(for:folder)
        defer { try? FileManager.default.removeItem(at:staging) }
        for name in ["segments","media","index"] { try FileManager.default.createDirectory(at:staging.appendingPathComponent(name),withIntermediateDirectories:true) }
        let now = Date(),session = ScanSession(id:id,kind:kind,projectID:projectID,created:now,updated:now)
        try JSONEncoder().encode(session).write(to:staging.appendingPathComponent("session.json"),options:.atomic)
        try PackageReplacement.commit(staging,to:folder)
        return session
    }
    func read(_ id:UUID) throws -> ScanSession {
        let target = directory(id).appendingPathComponent("session.json")
        try check(target); try PackageReplacement.recover(target)
        guard (try target.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 16_384 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf:target)
        guard data.count <= 16_384 else { throw CocoaError(.fileReadTooLarge) }
        let session = try JSONDecoder().decode(ScanSession.self,from:data)
        guard session.schemaVersion == 1,session.id == id,session.updated >= session.created else { throw CocoaError(.fileReadCorruptFile) }
        return session
    }
    func setState(_ id:UUID,_ state:ScanSession.State) throws {
        var value = try read(id)
        guard value.state != .completed || state == .completed else { throw CocoaError(.fileWriteNoPermission) }
        if state == .completed { guard value.state == .finalizing || value.state == .completed else { throw CocoaError(.fileWriteNoPermission) } }
        value.state = state; value.updated = Date(); try manifest(value)
    }
    @discardableResult func write(_ id:UUID,key:String,data:Data,media:Bool = false,metadata:[String:String] = [:]) throws -> Entry {
        var session = try read(id)
        guard session.state != .completed,!key.isEmpty,key.count <= 200,data.count <= 64*1_048_576,
              metadata.count <= 32,metadata.allSatisfy({ $0.key.count <= 100 && $0.value.count <= 2000 }) else { throw CocoaError(.fileWriteNoPermission) }
        let entries = try entries(id)
        let sequence = (entries.last?.sequence ?? 0)+1,token = UUID()
        let path = (media ? "media/" : "segments/")+token.uuidString+".data"
        let entry = Entry(id:token,sequence:sequence,key:key,path:path,bytes:data.count,metadata:metadata,created:Date())
        try atomic(data,to:directory(id).appendingPathComponent(path)); try fault(.afterPayload)
        try atomic(JSONEncoder().encode(entry),to:directory(id).appendingPathComponent(String(format:"index/%08d.json",sequence)))
        try fault(.afterIndex)
        session.updated = Date(); try manifest(session); try fault(.afterManifest)
        return entry
    }
    func entries(_ id:UUID) throws -> [Entry] {
        _ = try read(id)
        let folder = directory(id).appendingPathComponent("index"); try check(folder)
        let urls = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil,options:.skipsHiddenFiles).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard urls.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
        return try urls.enumerated().map { offset,url in
            try check(url)
            guard (try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max) <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
            let data = try Data(contentsOf:url)
            guard data.count <= 100_000 else { throw CocoaError(.fileReadTooLarge) }
            let entry = try JSONDecoder().decode(Entry.self,from:data)
            guard entry.sequence == offset+1,entry.path == "segments/"+entry.id.uuidString+".data" || entry.path == "media/"+entry.id.uuidString+".data" else { throw CocoaError(.fileReadCorruptFile) }
            let payload = directory(id).appendingPathComponent(entry.path); try check(payload)
            let bytes = try payload.resourceValues(forKeys:[.fileSizeKey]).fileSize
            guard bytes == entry.bytes,entry.bytes <= 64*1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
            return entry
        }
    }
    func latest(_ id:UUID,key:String) throws -> Data? {
        guard let entry = try entries(id).last(where:{ $0.key == key }) else { return nil }
        return try Data(contentsOf:directory(id).appendingPathComponent(entry.path))
    }
    struct LatestValue: Codable { let key:String; let data:Data; let metadata:[String:String] }
    func writeLatest(_ id:UUID,key:String,data:Data,metadata:[String:String] = [:]) throws {
        var session = try read(id)
        guard session.state != .completed,key.count <= 100,!key.isEmpty,
              key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              data.count <= 64*1_048_576 else { throw CocoaError(.fileWriteNoPermission) }
        let folder = directory(id).appendingPathComponent("latest")
        try check(folder); try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try atomic(JSONEncoder().encode(LatestValue(key:key,data:data,metadata:metadata)),to:folder.appendingPathComponent(key+".json"))
        session.updated = Date(); try manifest(session)
    }
    func latestValues(_ id:UUID,prefix:String) throws -> [LatestValue] {
        _ = try read(id)
        let folder = directory(id).appendingPathComponent("latest")
        guard FileManager.default.fileExists(atPath:folder.path) else { return [] }
        try check(folder)
        var names = Set(try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).compactMap { url -> String? in
            let name = url.lastPathComponent
            if name.hasPrefix("."),name.hasSuffix(".package-backup") { return String(name.dropFirst().dropLast(".package-backup".count)) }
            return url.pathExtension == "json" ? name : nil
        })
        names = Set(names.filter { $0.hasPrefix(prefix) })
        var totalBytes = 0
        return try names.sorted().map { name in
            let url = folder.appendingPathComponent(name); try check(url); try PackageReplacement.recover(url)
            let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? Int.max
            guard size >= 0,size <= 90*1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            totalBytes += size
            guard totalBytes <= 128*1_048_576 else { throw CocoaError(.fileReadTooLarge) }
            let bytes = try SafePackageRead.data(url,root:folder,maximum:90*1_048_576)
            let value = try JSONDecoder().decode(LatestValue.self,from:bytes)
            guard name == value.key+".json" else { throw CocoaError(.fileReadCorruptFile) }
            return value
        }
    }
    func payload(_ id:UUID,entry:Entry) throws -> Data {
        _ = try read(id)
        guard (1...100_000).contains(entry.sequence),entry.bytes >= 0,entry.bytes <= 64*1_048_576,
              entry.path == "segments/"+entry.id.uuidString+".data" || entry.path == "media/"+entry.id.uuidString+".data" else { throw CocoaError(.fileReadNoPermission) }
        let folder = directory(id),index = folder.appendingPathComponent(String(format:"index/%08d.json",entry.sequence))
        try check(index)
        let committed = try JSONDecoder().decode(Entry.self,from:SafePackageRead.data(index,root:folder,maximum:100_000))
        guard committed == entry else { throw CocoaError(.fileReadNoPermission) }
        let target = folder.appendingPathComponent(entry.path); try check(target)
        let data = try SafePackageRead.data(target,root:folder,maximum:64*1_048_576)
        guard data.count == entry.bytes else { throw CocoaError(.fileReadCorruptFile) }
        return data
    }
    func unfinished() throws -> [ScanSession] {
        guard FileManager.default.fileExists(atPath:root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil,options:.skipsHiddenFiles).compactMap { url in
            guard let id = UUID(uuidString:url.lastPathComponent) else { return nil }
            let value = try read(id)
            return value.state == .completed ? nil : value
        }.sorted { $0.updated > $1.updated }
    }
    /// Unindexed payloads and temporary files cannot belong to a committed note
    /// or segment. Retain committed versions, including previous audio clips.
    func removeOrphans(_ id:UUID) throws {
        let retained = Set(try entries(id).map(\.path))
        let latest = directory(id).appendingPathComponent("latest")
        if FileManager.default.fileExists(atPath:latest.path) {
            for url in try FileManager.default.contentsOfDirectory(at:latest,includingPropertiesForKeys:nil) {
                let name = url.lastPathComponent,suffix = ".package-backup"
                if name.hasPrefix("."),name.hasSuffix(suffix) {
                    let target = latest.appendingPathComponent(String(name.dropFirst().dropLast(suffix.count)))
                    try check(target); try PackageReplacement.recover(target)
                }
            }
            for url in try FileManager.default.contentsOfDirectory(at:latest,includingPropertiesForKeys:nil) where url.lastPathComponent.hasPrefix(".package-writing-") {
                try check(url); try FileManager.default.removeItem(at:url)
            }
        }
        for name in ["segments","media","index"] {
            let folder = directory(id).appendingPathComponent(name)
            for url in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) {
                let relative = name+"/"+url.lastPathComponent
                if url.lastPathComponent.hasPrefix(".") || (name != "index" && !retained.contains(relative)) { try check(url); try FileManager.default.removeItem(at:url) }
            }
        }
    }
    func discard(_ id:UUID) throws {
        _ = try read(id)
        try FileManager.default.removeItem(at:directory(id))
    }
}
