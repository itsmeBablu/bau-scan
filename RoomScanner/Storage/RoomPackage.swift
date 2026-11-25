import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// `.roomscan` — a complete scan bundle treated as a document package.
    static let roomScan = UTType(exportedAs: "io.github.itsmebablu.dwalkscan.room", conformingTo: .package)
    static let legacyRoomScan = UTType("fr.vincentlauriat.roomscanner.room")
}

/// Contents of a `.roomscan` package with coordinated read/write.
///
/// Writing: the package is assembled in a temporary directory and then
/// moved in a single coordinated operation for atomic iCloud sync.
struct RoomPackage {
    var record: RoomRecord
    var plan: FloorPlan
    var scan: ScanInput?
    /// Apple-encoded `CapturedRoom` data — opaque on macOS (readable on iOS only).
    var capturedRoomData: Data?
    var usdzData: Data?
    /// Raw scan mesh (`CapturedRoom.export(.mesh)`), optional.
    var usdzMeshData: Data?
    var thumbnailPNG: Data?
    /// Optional Technik Room annotations; existing room/house packages do not require this file.
    var technicalRoomData: Data? = nil
    var surveyPhotos: [SurveyPhoto]? = nil
    var surveyPhotoAssets: [UUID:Data] = [:]

    /// ISO 8601 dates with fractional seconds: readable in `meta.json`
    /// and stable on roundtrip (standard `.iso8601` strategy truncates subseconds).
    private static let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer(); try c.encode(dateFormatter.string(from: date))
        }
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            guard let date = dateFormatter.date(from: s) ?? ISO8601DateFormatter().date(from: s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "date invalide: \(s)"))
            }
            return date
        }
        return d
    }()

    // MARK: Writing

    func write(to packageURL: URL, fileManager: FileManager = .default) throws {
        let staging = try PackageReplacement.staging(for:packageURL,fm:fileManager)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        try Self.encoder.encode(record).write(to: staging.appendingPathComponent(FileLayout.PackageFile.meta))
        try Self.encoder.encode(plan).write(to: staging.appendingPathComponent(FileLayout.PackageFile.plan))
        if let scan { try Self.encoder.encode(scan).write(to: staging.appendingPathComponent(FileLayout.PackageFile.scan)) }
        if let capturedRoomData { try capturedRoomData.write(to: staging.appendingPathComponent(FileLayout.PackageFile.capturedRoom)) }
        if let usdzData { try usdzData.write(to: staging.appendingPathComponent(FileLayout.PackageFile.usdz)) }
        if let usdzMeshData { try usdzMeshData.write(to: staging.appendingPathComponent(FileLayout.PackageFile.usdzMesh)) }
        if let thumbnailPNG { try thumbnailPNG.write(to: staging.appendingPathComponent(FileLayout.PackageFile.thumbnail)) }
        if let technicalRoomData { try technicalRoomData.write(to: staging.appendingPathComponent("technical-room.json")) }
        try SurveyPhotoStore.write(surveyPhotos,assets:surveyPhotoAssets,to:staging)

        try fileManager.createDirectory(at: packageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.coordinatedWrite(at: packageURL, options: .forReplacing) { url in
            try PackageReplacement.commit(staging,to:url,fm:fileManager)
        }
    }

    // MARK: Lecture

    static func readRecord(from packageURL: URL) throws -> RoomRecord {
        try coordinatedRead(at: packageURL) { url in
            try decoder.decode(RoomRecord.self, from: SafePackageRead.data(url.appendingPathComponent(FileLayout.PackageFile.meta),root:url))
        }
    }

    static func readPlan(from packageURL: URL) throws -> FloorPlan {
        try coordinatedRead(at: packageURL) { url in
            try decoder.decode(FloorPlan.self, from: SafePackageRead.data(url.appendingPathComponent(FileLayout.PackageFile.plan),root:url))
        }
    }

    static func readScan(from packageURL: URL) throws -> ScanInput? {
        try coordinatedRead(at: packageURL) { url in
            let f = url.appendingPathComponent(FileLayout.PackageFile.scan)
            guard FileManager.default.fileExists(atPath: f.path) else { return nil }
            return try decoder.decode(ScanInput.self, from: SafePackageRead.data(f,root:url))
        }
    }

    /// Reads entire package. Missing optional files remain `nil`.
    static func read(from packageURL: URL) throws -> RoomPackage {
        try coordinatedRead(at: packageURL) { url in
            typealias F = FileLayout.PackageFile
            func optional(_ name: String) throws -> Data? {
                let f = url.appendingPathComponent(name)
                return FileManager.default.fileExists(atPath: f.path) ? try SafePackageRead.data(f,root:url) : nil
            }
            let record = try decoder.decode(RoomRecord.self, from: SafePackageRead.data(url.appendingPathComponent(F.meta),root:url))
            let plan = try decoder.decode(FloorPlan.self, from: SafePackageRead.data(url.appendingPathComponent(F.plan),root:url))
            let scan = try optional(F.scan).map { try decoder.decode(ScanInput.self, from: $0) }
            let photos = try SurveyPhotoStore.read(from:url)
            return try RoomPackage(record: record, plan: plan, scan: scan, capturedRoomData: optional(F.capturedRoom),
                                   usdzData: optional(F.usdz), usdzMeshData: optional(F.usdzMesh), thumbnailPNG: optional(F.thumbnail),
                                   technicalRoomData: optional("technical-room.json"),surveyPhotos:photos.photos,surveyPhotoAssets:photos.assets)
        }
    }

    static func usdzURL(in packageURL: URL) -> URL? {
        let f = packageURL.appendingPathComponent(FileLayout.PackageFile.usdz)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    static func usdzMeshURL(in packageURL: URL) -> URL? {
        let f = packageURL.appendingPathComponent(FileLayout.PackageFile.usdzMesh)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    static func thumbnailURL(in packageURL: URL) -> URL? {
        let f = packageURL.appendingPathComponent(FileLayout.PackageFile.thumbnail)
        return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// Rewrites `meta.json` and `plan.json` (rename, recalculate) without altering assets.
    static func update(record: RoomRecord, plan: FloorPlan, in packageURL: URL) throws {
        try coordinatedWrite(at: packageURL, options: .forMerging) { url in
            try encoder.encode(record).write(to: url.appendingPathComponent(FileLayout.PackageFile.meta), options: .atomic)
            try encoder.encode(plan).write(to: url.appendingPathComponent(FileLayout.PackageFile.plan), options: .atomic)
        }
    }

    static func writeThumbnail(_ png: Data, in packageURL: URL) throws {
        try coordinatedWrite(at: packageURL, options: .forMerging) { url in
            try png.write(to: url.appendingPathComponent(FileLayout.PackageFile.thumbnail), options: .atomic)
        }
    }

    static func delete(at packageURL: URL) throws {
        try coordinatedWrite(at: packageURL, options: .forDeleting) { url in
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: Coordination

    static func coordinatedRead<T>(at url: URL, _ body: (URL) throws -> T) throws -> T {
        var coordError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = Result { try body(u) }
        }
        if let coordError { throw coordError }
        guard let result else { throw AppError.storageFailed("NSFileCoordinator n'a pas exécuté la lecture de \(url.lastPathComponent)") }
        return try result.get()
    }

    static func coordinatedWrite(at url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) throws -> Void) throws {
        var coordError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordError) { u in
            do { try body(u) } catch { bodyError = error }
        }
        if let coordError { throw coordError }
        if let bodyError { throw bodyError }
    }
}
