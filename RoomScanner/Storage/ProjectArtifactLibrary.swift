import Foundation

enum ProjectArtifactCategory:String,CaseIterable,Identifiable {
    case all = "All",reports = "Reports",plans = "Plans",cad = "CAD/BIM",models = "3D",photos = "Photos",audio = "Audio",archives = "Archives"
    var id:String { rawValue }
    static func category(_ file:URL) -> Self {
        switch file.pathExtension.lowercased() {
        case "pdf","csv": return .reports
        case "png","svg": return .plans
        case "dxf","ifc","json": return .cad
        case "usdz","obj","mtl","stl","ply","glb","gltf": return .models
        case "jpg","jpeg","heic": return .photos
        case "m4a","aac","wav","mp3": return .audio
        default: return file.lastPathComponent.lowercased().contains("photos") ? .photos : .archives
        }
    }
}

struct ProjectArtifactFile:Identifiable {
    let url:URL
    let bytes:Int64
    let modified:Date
    var id:URL { url }
    var category:ProjectArtifactCategory { .category(url) }
    var legacy:Bool { UUID(uuidString:url.deletingPathExtension().lastPathComponent) != nil }
}

extension ProjectArtifacts {
    static let supportedExtensions:Set<String> = ["pdf","csv","zip","png","svg","dxf","ifc","json","usdz","obj","mtl","stl","ply","glb","gltf","jpg","jpeg","heic","m4a","aac","wav","mp3"]
    static func inspect(root:URL,projectID:UUID) throws -> [ProjectArtifactFile] {
        let dir = directory(root:root,projectID:projectID)
        guard FileManager.default.fileExists(atPath:dir.path) else { return [] }
        try checkFolders(root:root,projectID:projectID)
        let urls = try files(root:root,projectID:projectID)
        guard urls.count <= 10_000 else { throw CocoaError(.fileReadTooLarge) }
        return try urls.map { file in
            let info = try file.resourceValues(forKeys:[.fileSizeKey,.contentModificationDateKey])
            return ProjectArtifactFile(url:file,bytes:Int64(info.fileSize ?? 0),modified:info.contentModificationDate ?? .distantPast)
        }.sorted { $0.modified == $1.modified ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.modified > $1.modified }
    }
    static func rename(_ file:URL,to name:String,root:URL,projectID:UUID) throws -> URL {
        let dir = directory(root:root,projectID:projectID)
        var result = file
        try RoomPackage.coordinatedWrite(at:dir,options:.forMerging) { folder in
            try checkFile(file,root:root,projectID:projectID)
            guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw CocoaError(.fileWriteInvalidFileName) }
            let target = folder.appendingPathComponent(ArchivePath.component(name,fallback:"Export")).appendingPathExtension(file.pathExtension)
            if target.standardizedFileURL == file.standardizedFileURL { return }
            let used = try FileManager.default.contentsOfDirectory(atPath:folder.path)
            guard !used.contains(where:{ $0.compare(target.lastPathComponent,options:[.caseInsensitive,.diacriticInsensitive]) == .orderedSame }) else { throw CocoaError(.fileWriteFileExists) }
            try FileManager.default.moveItem(at:file,to:target); result = target
        }
        return result
    }
    static func remove(_ file:URL,root:URL,projectID:UUID) throws {
        try RoomPackage.coordinatedWrite(at:directory(root:root,projectID:projectID),options:.forMerging) { _ in
            try checkFile(file,root:root,projectID:projectID)
            try FileManager.default.removeItem(at:file)
        }
    }
    private static func checkFile(_ file:URL,root:URL,projectID:UUID) throws {
        try checkFolders(root:root,projectID:projectID)
        let dir = directory(root:root,projectID:projectID).standardizedFileURL
        guard file.isFileURL,file.deletingLastPathComponent().standardizedFileURL == dir,
              !file.lastPathComponent.hasPrefix("."),supportedExtensions.contains(file.pathExtension.lowercased()) else { throw CocoaError(.fileWriteNoPermission) }
        let info = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
        guard info.isRegularFile == true,info.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
    }
    private static func checkFolders(root:URL,projectID:UUID) throws {
        var folder = root
        for component in ["Projects",projectID.uuidString,"Exports"] {
            folder.appendPathComponent(component)
            let info = try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
            guard info.isDirectory == true,info.isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
        }
    }
}
