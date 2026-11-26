import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let technicalRoom = UTType(exportedAs: "io.github.itsmebablu.dwalkscan.technicalroom", conformingTo: .package)
}

struct TechnicalRoomManifest: Codable, Hashable, Identifiable {
    var schemaVersion = 1
    var id: UUID
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var checkpointAcceptedAtSave = false
    var incomplete: Bool? = nil
    /// This release has no device-validated engineering accuracy claim.
    var validationStatus = "deviceValidationPending"
}

/// Independent technical survey container. No RoomPlan/ARKit imports or room/house package changes.
struct TechnicalRoomPackage {
    enum PackageError: LocalizedError {
        case unsupportedVersion(Int), invalidPackage, unsafePath, oversizedFile
        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version): "Unsupported technical package version \(version). The original was not modified."
            case .invalidPackage: "The technical survey is incomplete or inconsistent."
            case .unsafePath: "The technical package contains an unsafe asset path."
            case .oversizedFile: "A technical package file exceeds the supported size limit."
            }
        }
    }
    var manifest: TechnicalRoomManifest
    var document: TechnicalAnnotationDocument
    var alignment: TechnicalAlignmentSurvey
    var journal: TechnicalCaptureJournal
    var worldMapData: Data?
    var thumbnailPNG: Data?
    var evidence = TechnicalCaptureEvidence()
    var recognition = TechnicalMEPReview()

    func validate() throws {
        guard manifest.schemaVersion == 1 else { throw PackageError.unsupportedVersion(manifest.schemaVersion) }
        guard manifest.id == document.room.id, !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.name.count <= 200, manifest.validationStatus == "deviceValidationPending",
              manifest.createdAt.timeIntervalSince1970.isFinite, manifest.modifiedAt.timeIntervalSince1970.isFinite else { throw PackageError.invalidPackage }
        try TechnicalAnnotationHistory.validate(document)
        _ = try TechnicalRoomJSONExporter.data(for: document.room)
        try alignment.validate()
        try journal.validate()
        try evidence.validate()
        try recognition.validate()
        let spatialAnnotations = !document.room.pipeRuns.isEmpty || !document.room.equipment.isEmpty || !document.ducts.isEmpty || !document.measurements.isEmpty
        if spatialAnnotations { guard alignment.referenceFrame != nil, alignment.referenceLocked else { throw PackageError.invalidPackage } }
        if let reference = alignment.referenceFrame {
            guard reference == document.room.shellToRoom.value else { throw PackageError.invalidPackage }
        }
        if manifest.checkpointAcceptedAtSave {
            guard alignment.checkpoints.last?.accepted == true else { throw PackageError.invalidPackage }
        }
        guard (worldMapData?.count ?? 0) <= 64 * 1_048_576, (thumbnailPNG?.count ?? 0) <= 10 * 1_048_576 else { throw PackageError.oversizedFile }
        let assets = Set(document.photoAssets.map(\.id))
        guard assets == Set(document.room.photos.map(\.id)) else { throw PackageError.invalidPackage }
        for photo in document.room.photos {
            guard photo.reference.value == "photos/\(photo.id.uuidString).jpg" else { throw PackageError.unsafePath }
        }
    }

    func write(to target: URL, fileManager fm: FileManager = .default) throws {
        let interval = PerformanceTrace.begin("TechnicalPackageWrite")
        defer { interval.end() }
        try validate()
        guard target.pathExtension == "technicalroom" else { throw PackageError.invalidPackage }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let parent = target.deletingLastPathComponent()
        try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        if fm.fileExists(atPath: target.path), try fm.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType == .typeSymbolicLink {
            throw PackageError.unsafePath
        }
        let staging = parent.appendingPathComponent(".technical-writing-\(UUID().uuidString)", isDirectory: true)
        let backup = parent.appendingPathComponent(".technical-backup-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        var annotations = document
        annotations.photoAssets = []
        func write(_ data: Data, _ name: String, _ limit: Int) throws {
            guard data.count <= limit else { throw PackageError.oversizedFile }
            try data.write(to: staging.appendingPathComponent(name), options: .atomic)
        }
        try write(encoder.encode(manifest), "manifest.json", 262_144)
        try write(encoder.encode(annotations), "annotations.json", 32 * 1_048_576)
        try write(TechnicalRoomJSONExporter.data(for: document.room), "technical-room.json", 32 * 1_048_576)
        try write(encoder.encode(alignment), "survey.json", 8 * 1_048_576)
        try write(encoder.encode(journal), "capture.json", 256 * 1_048_576)
        try write(encoder.encode(evidence.withoutImageBytes()), "evidence.json", 96 * 1_048_576)
        try write(encoder.encode(recognition), "recognition.json", 1_048_576)
        if !evidence.keyframes.isEmpty {
            let images = staging.appendingPathComponent("capture-images", isDirectory: true)
            try fm.createDirectory(at: images, withIntermediateDirectories: true)
            for frame in evidence.keyframes {
                try frame.jpegData.write(to: images.appendingPathComponent("\(frame.id.uuidString).jpg"), options: .atomic)
            }
        }
        if let worldMapData { try worldMapData.write(to: staging.appendingPathComponent("world-map.archive"), options: .atomic) }
        if let thumbnailPNG { try thumbnailPNG.write(to: staging.appendingPathComponent("thumbnail.png"), options: .atomic) }
        let photos = staging.appendingPathComponent("photos", isDirectory: true)
        if !document.photoAssets.isEmpty { try fm.createDirectory(at: photos, withIntermediateDirectories: true) }
        for photo in document.photoAssets { try photo.jpegData.write(to: photos.appendingPathComponent("\(photo.id.uuidString).jpg"), options: .atomic) }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { destination in
            do {
                if fm.fileExists(atPath: destination.path) { try fm.moveItem(at: destination, to: backup) }
                do { try fm.moveItem(at: staging, to: destination) }
                catch {
                    if fm.fileExists(atPath: backup.path) { try fm.moveItem(at: backup, to: destination) }
                    throw error
                }
                try? fm.removeItem(at: backup)
            } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    static func read(from url: URL) throws -> Self {
        var coordinationError: NSError?
        var result: Result<Self, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { root in
            result = Result { try readUncoordinated(from: root) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw PackageError.invalidPackage }
        return try result.get()
    }
    static func readManifest(from url: URL) throws -> TechnicalRoomManifest {
        let manifest = try JSONDecoder().decode(TechnicalRoomManifest.self, from: load("manifest.json", root: url, maximum: 262_144))
        guard manifest.schemaVersion == 1 else { throw PackageError.unsupportedVersion(manifest.schemaVersion) }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, manifest.name.count <= 200,
              manifest.validationStatus == "deviceValidationPending", manifest.createdAt.timeIntervalSince1970.isFinite,
              manifest.modifiedAt.timeIntervalSince1970.isFinite else { throw PackageError.invalidPackage }
        return manifest
    }
    private static func readUncoordinated(from root: URL) throws -> Self {
        let manifest = try readManifest(from: root)
        let decoder = JSONDecoder()
        var annotations = try decoder.decode(TechnicalAnnotationDocument.self, from: load("annotations.json", root: root, maximum: 32 * 1_048_576))
        guard annotations.photoAssets.isEmpty else { throw PackageError.invalidPackage }
        let rawData = try load("technical-room.json", root: root, maximum: 32 * 1_048_576)
        try TechnicalJSONSchema.validate(rawData)
        let raw = try decoder.decode(TechnicalRoom.self, from: rawData)
        guard raw == annotations.room else { throw PackageError.invalidPackage }
        for photo in annotations.room.photos {
            guard photo.reference.value == "photos/\(photo.id.uuidString).jpg" else { throw PackageError.unsafePath }
            annotations.photoAssets.append(.init(id: photo.id, jpegData: try load(photo.reference.value, root: root, maximum: 10 * 1_048_576)))
        }
        let alignment = try decoder.decode(TechnicalAlignmentSurvey.self, from: load("survey.json", root: root, maximum: 8 * 1_048_576))
        let journal = try decoder.decode(TechnicalCaptureJournal.self, from: load("capture.json", root: root, maximum: 256 * 1_048_576))
        func optional(_ path: String, maximum: Int) throws -> Data? {
            guard FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else { return nil }
            return try load(path, root: root, maximum: maximum)
        }
        var evidence = try optional("evidence.json", maximum: 96 * 1_048_576).map { try decoder.decode(TechnicalCaptureEvidence.self, from: $0) } ?? .init()
        guard evidence.keyframes.count <= 32,evidence.bytes <= TechnicalCaptureEvidence.budget,
              evidence.keyframes.allSatisfy({ $0.jpegData.isEmpty }) else { throw PackageError.invalidPackage }
        var evidenceBytes = evidence.bytes
        try evidence.restoreImages {
            let data = try load("capture-images/\($0.uuidString).jpg", root: root, maximum: 4 * 1_048_576)
            evidenceBytes += data.count
            guard evidenceBytes <= TechnicalCaptureEvidence.budget else { throw PackageError.oversizedFile }
            return data
        }
        let recognition = try optional("recognition.json", maximum: 1_048_576).map { try decoder.decode(TechnicalMEPReview.self, from: $0) } ?? .init()
        let package = Self(manifest: manifest, document: annotations, alignment: alignment, journal: journal,
                           worldMapData: try optional("world-map.archive", maximum: 64 * 1_048_576), thumbnailPNG: try optional("thumbnail.png", maximum: 10 * 1_048_576))
        var completed = package
        completed.evidence = evidence; completed.recognition = recognition
        try completed.validate()
        return completed
    }
    private static func load(_ path: String, root: URL, maximum: Int) throws -> Data {
        try SafePackageRead.data(root.appendingPathComponent(path),root:root,maximum:maximum)
    }
}
