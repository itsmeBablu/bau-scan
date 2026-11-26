import Foundation

enum ProjectExportKind:String,Codable,CaseIterable,Identifiable {
    case report = "Project report · PDF", quantities = "Quantities · CSV", complete = "Everything · organised ZIP", photos = "Photos · ZIP"
    var id:String { rawValue }
    var suffix:String { switch self { case .report: "pdf"; case .quantities: "csv"; default: "zip" } }
    var fileStem:String { switch self { case .report: "Report"; case .quantities: "Quantities"; case .complete: "Complete"; case .photos: "Photos" } }
}

struct ProjectExportRequest:Codable,Equatable {
    var schemaVersion = 1
    var generatorRevision = 2
    let projectID:UUID
    let kind:ProjectExportKind
    let metadataDigest:String
    let sourceRevision:String
    let locale:String
    let unit:MeasurementUnit
    let includeDetails:Bool
    let wastePercent:Double
    func key() throws -> String { ExportChecksum.digest(try Self.encode(self)) }
    static func encode<T:Encodable>(_ value:T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    func validate() throws {
        guard schemaVersion == 1,(1...2).contains(generatorRevision),locale.count <= 100,!locale.isEmpty,
              wastePercent.isFinite,(0...100).contains(wastePercent),
              [metadataDigest,sourceRevision].allSatisfy({ $0.count == 64 && $0.allSatisfy(\.isHexDigit) }) else { throw CocoaError(.fileReadCorruptFile) }
    }
    static func make(project:RenovationProject,index:ProjectIndex,entries:[ProjectLibraryEntry],kind:ProjectExportKind,locale:Locale,unit:MeasurementUnit,includeDetails:Bool,wastePercent:Double,includePhotos:Bool = true) async throws -> Self {
        let metadata = try metadata(project:project,index:index)
        var sources:[String:String] = [:]
        // Render options participate in reuse identity without changing stored
        // request keys or native package schemas. Legacy revision 1 still decodes.
        if kind == .report || kind == .complete { sources["$render/pdfPhotos"] = includePhotos ? "included" : "excluded" }
        for reference in project.references.sorted(by:{ $0.id < $1.id }) {
            try Task.checkCancellation()
            guard let entry = entries.first(where:{ $0.reference == reference }),FileManager.default.fileExists(atPath:entry.url.path) else { sources[reference.id] = "unavailable"; continue }
            for (path,hash) in try await ProjectExportSourceHashes.shared.files(entry.url) { sources[reference.id+"/"+path] = hash }
        }
        let result = Self(projectID:project.id,kind:kind,metadataDigest:metadata,sourceRevision:ExportChecksum.digest(try encode(sources)),locale:locale.identifier,unit:unit,includeDetails:includeDetails,wastePercent:wastePercent)
        try result.validate(); return result
    }
    static func metadata(project:RenovationProject,index:ProjectIndex) throws -> String {
        let ids = Set(project.references.map(\.id))
        var subset = index; subset.projects = [project]
        subset.displayNames = subset.displayNames?.filter { ids.contains($0.key) }
        subset.scanOrganization = subset.scanOrganization?.filter { ids.contains($0.key) }
        subset.pins = subset.pins?.filter { $0.projectID == project.id }
        subset.distanceChecks = subset.distanceChecks?.filter { $0.projectID == project.id }
        try subset.validate()
        return ExportChecksum.digest(try encode(subset))
    }
}

/// Cache hashes, never source bytes. Atomic package replacements change file IDs.
/// Enumerate revisions for every request; only changed files are hashed again.
private actor ProjectExportSourceHashes {
    static let shared = ProjectExportSourceHashes()
    private struct Cached { let revision:SavedFileRevision; let hash:String }
    private var values:[String:Cached] = [:]
    private var order:[String] = []
    func files(_ source:URL) throws -> [String:String] {
        let info = try source.resourceValues(forKeys:[.isDirectoryKey,.isRegularFileKey,.isSymbolicLinkKey])
        guard info.isSymbolicLink != true else { throw CocoaError(.fileReadNoPermission) }
        let urls:[URL]
        if info.isRegularFile == true { urls = [source] }
        else {
            try SafePackageRead.validate(source,entries:100_000,total:2_147_483_648)
            var failure:Error?
            guard let enumerator = FileManager.default.enumerator(at:source,includingPropertiesForKeys:[.isRegularFileKey],options:.skipsHiddenFiles,errorHandler:{ _,error in failure = error; return false }) else { throw CocoaError(.fileReadUnknown) }
            urls = try enumerator.compactMap { item -> URL? in
                guard let file = item as? URL else { return nil }
                return try file.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true ? file : nil
            }.sorted { $0.path < $1.path }
            if let failure { throw failure }
        }
        var result:[String:String] = [:]
        for file in urls {
            try Task.checkCancellation()
            let before = try SavedFileRevision(file),hash:String
            guard before.bytes >= 0,before.bytes <= 2_147_483_648 else { throw CocoaError(.fileReadTooLarge) }
            if let cached = values[file.path],cached.revision == before { hash = cached.hash }
            else {
                hash = try ExportChecksum.sha256(file)
                guard try SavedFileRevision(file) == before else { throw CocoaError(.fileReadUnknown) }
                values[file.path] = Cached(revision:before,hash:hash)
                order.removeAll { $0 == file.path }; order.append(file.path)
                if order.count > 2048 { values.removeValue(forKey:order.removeFirst()) }
            }
            result[file == source ? source.lastPathComponent : String(file.path.dropFirst(source.path.count+1))] = hash
        }
        return result
    }
}
