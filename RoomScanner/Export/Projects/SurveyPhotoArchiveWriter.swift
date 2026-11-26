import Foundation

enum ArchivePath {
    /// Safe on Windows as well as Apple filesystems. Room names remain readable.
    static func component(_ raw: String, fallback: String = "Room") -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn:"/\\:*?\"<>|"))
        var value = String(raw.precomposedStringWithCanonicalMapping.unicodeScalars.map { forbidden.contains($0) ? "-" : Character($0) })
        value = String(value.trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"."))).prefix(60))
        if value.isEmpty { value = fallback }
        let stem = String(value.split(separator:".").first ?? "").uppercased()
        if ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"].contains(stem) { value = "_"+value }
        return value
    }
    static func unique(_ base: String, used: inout Set<String>) -> String {
        var name = base, suffix = 2
        func key(_ value: String) -> String { value.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")) }
        while used.contains(key(name)) { name = base+"-\(suffix)"; suffix += 1 }
        used.insert(key(name)); return name
    }
}

enum SurveyPhotoArchiveWriter {
    static func archive(project: RenovationProject, entries: [ProjectLibraryEntry], locale: Locale, to destination: URL,organization:[String:ScanOrganization] = [:]) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
        let root = staging.appendingPathComponent(ArchivePath.component(project.name,fallback:"Project"),isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:staging) }
        var records: [Entry] = [], used = PhotoArchiveLayout()
        for ref in project.references where !ref.kind.rawValue.hasPrefix("design") {
            guard let entry = entries.first(where:{ $0.reference == ref }) else { throw CocoaError(.fileNoSuchFile) }
            let images: [SurveyPhotoImage]
            var summary:ProjectScanSummary?
            if ref.kind == .technicalRoom { images = SurveyPhotoStore.images(technical:try TechnicalRoomPackage.read(from:entry.url)) }
            else {
                let house: House
                if ref.kind == .house { house = try HousePackage.readHouse(from:entry.url) }
                else { house = House(room:try RoomPackage.readPlan(from:entry.url)) }
                summary = ProjectScanSummary(house:house)
                images = try SurveyPhotoStore.images(from:entry.url,house:house)
            }
            records += try write(images,to:root,used:&used,sourceID:ref.id,organization:organization[ref.id],summary:summary,locale:locale)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(records).write(to:root.appendingPathComponent("photo-index.json"))
        try AppLanguage.text("Photos use Photos/building/level/room/ with room-name.number image and camera files. Numbering restarts in each room. Same-name rooms receive numbered suffixes. Missing organization remains Unassigned. Photo-index.json preserves source IDs and original numbers. Camera coordinates are not GPS. Device validation pending.",locale:locale).write(to:root.appendingPathComponent("README.txt"),atomically:true,encoding:.utf8)
        try ArchiveExporter.zip(directory:root,to:destination)
    }
    struct Entry: Codable, Equatable {
        var sourceID: String?
        var photoID: UUID
        var roomID: UUID?
        var roomName: String
        var number: Int
        var imageFile: String
        var cameraFile: String
    }
    struct Camera: Encodable {
        let schemaVersion = 1
        let coordinateSystem = "rightHandedYUpMetres; scan coordinates, not GPS"
        let deviceValidationPending = true
        var photoID: UUID
        var roomID: UUID?
        var number: Int
        var imageFile: String
        var rawCameraPose: [Double]
        var displayCameraPose: [Double]?
        var captureTimestamp: Double
        var capturedAt: Date?
        var sourceID: String?
    }
    /// `used` spans all source scans in a bundle, protecting same-name rooms and case-only collisions.
    static func write(_ images: [SurveyPhotoImage], to root: URL, used: inout PhotoArchiveLayout, sourceID: String? = nil,organization:ScanOrganization? = nil,summary:ProjectScanSummary? = nil,locale:Locale = AppLanguage.locale) throws -> [Entry] {
        var manifest: [Entry] = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        for image in images {
            try image.photo.validate()
            guard image.jpegData.count <= 4*1_048_576,image.jpegData.starts(with:[0xff,0xd8]) else { throw CocoaError(.fileReadCorruptFile) }
            let paths = try used.paths(photo:image.photo,roomName:image.roomName,sourceID:sourceID ?? "",organization:organization,summary:summary,locale:locale)
            let target = root.appendingPathComponent(paths.image)
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            let jpeg = target.lastPathComponent
            try image.jpegData.write(to:target)
            let camera = Camera(photoID:image.id,roomID:image.photo.roomID,number:image.photo.number,imageFile:jpeg,rawCameraPose:image.photo.pose,displayCameraPose:image.photo.displayPose,captureTimestamp:image.photo.timestamp,capturedAt:image.photo.capturedAt,sourceID:sourceID)
            try encoder.encode(camera).write(to:root.appendingPathComponent(paths.camera))
            manifest.append(.init(sourceID:sourceID,photoID:image.id,roomID:image.photo.roomID,roomName:image.roomName,number:image.photo.number,imageFile:paths.image,cameraFile:paths.camera))
        }
        return manifest
    }
}
