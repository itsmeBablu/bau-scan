import Foundation

/// Optional export-only index. Legacy files are neither renamed nor deleted.
enum ProjectArtifactIndex {
    struct Record:Codable,Equatable,Identifiable {
        let id:String
        let request:ProjectExportRequest
        var filename:String
        let created:Date
        let bytes:Int
        let sha256:String
    }
    private struct Index:Codable { var schemaVersion = 1; var records:[Record] = [] }
    private static let filename = ".artifact-index-v1.json"
    private static func read(_ folder:URL) throws -> Index {
        let file = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath:file.path) else { return .init() }
        let value = try JSONDecoder().decode(Index.self,from:SafePackageRead.data(file,root:folder,maximum:8*1_048_576,preflight:false))
        guard value.schemaVersion == 1,value.records.count <= 10_000,Set(value.records.map(\.id)).count == value.records.count else { throw CocoaError(.fileReadCorruptFile) }
        for record in value.records {
            try record.request.validate()
            guard record.id == (try record.request.key()),record.filename.count <= 240,!record.filename.hasPrefix("."),
                  !record.filename.contains("/"),!record.filename.contains("\\"),!record.filename.contains(":"),
                  !record.filename.unicodeScalars.contains(where:{ CharacterSet.controlCharacters.contains($0) }),
                  URL(fileURLWithPath:record.filename).pathExtension == record.request.kind.suffix,
                  (0...1_073_741_824).contains(record.bytes),record.created.timeIntervalSince1970.isFinite,
                  record.sha256.count == 64,record.sha256.allSatisfy(\.isHexDigit) else { throw CocoaError(.fileReadCorruptFile) }
        }
        return value
    }
    private static func write(_ value:Index,folder:URL) throws {
        let data = try ProjectExportRequest.encode(value)
        guard data.count <= 8*1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to:folder.appendingPathComponent(filename),options:.atomic)
    }
    static func lookup(_ request:ProjectExportRequest,root:URL) throws -> URL? {
        try request.validate()
        let folder = ProjectArtifacts.directory(root:root,projectID:request.projectID)
        guard FileManager.default.fileExists(atPath:folder.path) else { return nil }
        try ProjectArtifacts.checkFolders(root:root,projectID:request.projectID)
        return try RoomPackage.coordinatedRead(at:folder) { directory in try reusable(request,index:read(directory),folder:directory) }
    }
    static func records(root:URL,projectID:UUID) throws -> [Record] {
        let folder = ProjectArtifacts.directory(root:root,projectID:projectID)
        guard FileManager.default.fileExists(atPath:folder.path) else { return [] }
        try ProjectArtifacts.checkFolders(root:root,projectID:projectID)
        return try RoomPackage.coordinatedRead(at:folder) { try read($0).records }
    }
    private static func reusable(_ request:ProjectExportRequest,index:Index,folder:URL) throws -> URL? {
        let key = try request.key()
        guard let record = index.records.first(where:{ $0.id == key }) else { return nil }
        let file = folder.appendingPathComponent(record.filename)
        guard FileManager.default.fileExists(atPath:file.path) else { return nil }
        let info = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard info.isRegularFile == true,info.isSymbolicLink != true,info.fileSize == record.bytes else { return nil }
        return try ExportChecksum.sha256(file) == record.sha256 ? file : nil
    }
    struct Publication { let url:URL; let reused:Bool }
    enum PublicationStage:CaseIterable { case beforeCopy, afterCopy, afterPublication, beforeIndexWrite }
    static func publish(_ source:URL,request:ProjectExportRequest,projectName:String,sourceNames:[String] = [],root:URL) throws -> URL {
        try publishResult(source,request:request,projectName:projectName,sourceNames:sourceNames,root:root).url
    }
    static func publishResult(_ source:URL,request:ProjectExportRequest,projectName:String,sourceNames:[String],root:URL,
                              fault:(PublicationStage) throws -> Void = { _ in }) throws -> Publication {
        try request.validate(); try Task.checkCancellation()
        let folder = try ProjectArtifacts.prepareDirectory(root:root,projectID:request.projectID)
        try ProjectArtifacts.checkFolders(root:root,projectID:request.projectID)
        var result:Publication?
        try RoomPackage.coordinatedWrite(at:folder,options:.forMerging) { directory in
            try Task.checkCancellation()
            var index = try read(directory)
            if let existing = try reusable(request,index:index,folder:directory) { result = .init(url:existing,reused:true); return }
            let info = try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard info.isRegularFile == true,info.isSymbolicLink != true,let bytes = info.fileSize,
                  (0...1_073_741_824).contains(bytes),source.pathExtension == request.kind.suffix else { throw CocoaError(.fileReadCorruptFile) }
            let key = try request.key(),checksum = try ExportChecksum.sha256(source)
            let candidates = try ProjectArtifacts.files(root:root,projectID:request.projectID).filter { $0.pathExtension == request.kind.suffix }
            guard candidates.count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
            for candidate in candidates {
                try Task.checkCancellation()
                let size = try candidate.resourceValues(forKeys:[.fileSizeKey]).fileSize
                if size == bytes,try ExportChecksum.sha256(candidate) == checksum {
                    index.records.removeAll { $0.id == key }
                    index.records.append(.init(id:key,request:request,filename:candidate.lastPathComponent,created:Date(),bytes:bytes,sha256:checksum))
                    try Task.checkCancellation(); try fault(.beforeIndexWrite)
                    try write(index,folder:directory); result = .init(url:candidate,reused:true); return
                }
            }
            let actualNames = sourceNames.filter { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty }.reduce(into:[String]()) { names,name in
                if !names.contains(name) && name != projectName { names.append(name) }
            }
            let detail = ([projectName]+actualNames).map { ArchivePath.component($0) }.joined(separator:" - ")
            var readable = String(detail.prefix(170))
            while readable.utf8.count > 180 { readable.removeLast() }
            let base = readable+" - "+request.kind.fileStem
            var name = base+"."+request.kind.suffix,number = 2
            while FileManager.default.fileExists(atPath:directory.appendingPathComponent(name).path) {
                name = base+" - \(number)."+request.kind.suffix; number += 1
                guard number <= 10_000 else { throw CocoaError(.fileWriteFileExists) }
            }
            let target = directory.appendingPathComponent(name),staging = try PackageReplacement.staging(for:target)
            defer { try? FileManager.default.removeItem(at:staging) }
            try fault(.beforeCopy)
            try FileManager.default.copyItem(at:source,to:staging)
            try fault(.afterCopy)
            guard try ExportChecksum.sha256(staging) == checksum else { throw CocoaError(.fileReadCorruptFile) }
            try Task.checkCancellation()
            try PackageReplacement.commit(staging,to:target)
            do {
                try fault(.afterPublication)
                try Task.checkCancellation()
                index.records.removeAll { $0.id == key }
                index.records.append(.init(id:key,request:request,filename:name,created:Date(),bytes:bytes,sha256:checksum))
                try fault(.beforeIndexWrite)
                try write(index,folder:directory)
            }
            catch { try? FileManager.default.removeItem(at:target); throw error }
            result = .init(url:target,reused:false)
        }
        guard let result else { throw CocoaError(.fileWriteUnknown) }; return result
    }
    static func renamed(_ old:String,to new:String,folder:URL) throws {
        var index = try read(folder)
        guard index.records.contains(where:{ $0.filename == old }) else { return }
        for i in index.records.indices where index.records[i].filename == old { index.records[i].filename = new }
        try write(index,folder:folder)
    }
    static func removed(_ name:String,folder:URL) throws {
        var index = try read(folder)
        guard index.records.contains(where:{ $0.filename == name }) else { return }
        index.records.removeAll { $0.filename == name }; try write(index,folder:folder)
    }
}
