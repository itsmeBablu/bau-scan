import Foundation
import UniformTypeIdentifiers

/// Paquet `.housescan` (v2, D25) : `meta.json` (`HouseRecord`), `house.json` (`House`),
/// `structure.json` (`StructureInput` neutre), `structure-apple.json` (`CapturedStructure`,
/// opaque here), `rooms/<uuid>.roomscan` (v1 bundles), `house.usdz`, `thumbnail.png`.
/// Written in a single coordinated operation, like `RoomPackage`.
struct HousePackage {
    var record: HouseRecord
    var house: House
    var structure: StructureInput?
    var capturedStructureData: Data?
    var rooms: [RoomPackage]
    var usdzData: Data?
    var thumbnailPNG: Data?
    /// Optional independent observations; never reconstructed from RoomPlan's furniture categories.
    var radiators: HouseRadiatorSurvey? = nil
    var surveyPhotos: [SurveyPhoto]? = nil
    var surveyPhotoAssets: [UUID:Data] = [:]

    typealias F = FileLayout.HousePackageFile

    /// Raw captures of a room (Apple `room.json`, parametric USDZ, mesh) to bundle.
    struct RoomExtras { var capturedRoomData: Data?; var usdzData: Data?; var usdzMeshData: Data? }

    /// Assembles full package from neutral structure: house is constructed by
    /// `HouseBuilder`, each room receives its `.roomscan` bundle (plan, scan, raw captures, thumbnail).
    static func assemble(structure: StructureInput, name: String, capturedStructureData: Data?, usdzData: Data?,
                         roomExtras: [UUID: RoomExtras] = [:], createdAt: Date = Date()) throws -> HousePackage {
        let house = try HouseBuilder().build(from: structure, name: name)
        let rooms = house.allRooms.map { plan -> RoomPackage in
            let extras = roomExtras[plan.id]
            return RoomPackage(record: RoomRecord(plan: plan, createdAt: createdAt), plan: plan,
                               scan: structure.rooms.first { $0.id == plan.id },
                               capturedRoomData: extras?.capturedRoomData, usdzData: extras?.usdzData, usdzMeshData: extras?.usdzMeshData,
                               thumbnailPNG: PlanRenderer.thumbnailPNG(for: plan))
        }
        return HousePackage(record: HouseRecord(house: house, createdAt: createdAt), house: house, structure: structure,
                            capturedStructureData: capturedStructureData, rooms: rooms, usdzData: usdzData,
                            thumbnailPNG: PlanRenderer.thumbnailPNG(for: house))
    }

    func write(to packageURL: URL, fileManager fm: FileManager = .default) throws {
        let interval = PerformanceTrace.begin("HousePackageWrite")
        defer { interval.end() }
        if let radiators { try radiators.validate(for: house) }
        let staging = try PackageReplacement.staging(for:packageURL,fm:fm)
        try fm.createDirectory(at: staging.appendingPathComponent(F.rooms, isDirectory: true), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        try RoomPackage.encoder.encode(record).write(to: staging.appendingPathComponent(F.meta))
        try RoomPackage.encoder.encode(house).write(to: staging.appendingPathComponent(F.house))
        if let radiators {
            let data = try RoomPackage.encoder.encode(radiators)
            guard data.count <= 64 * 1_048_576 else { throw HouseRadiatorSurvey.Failure.invalid }
            try data.write(to: staging.appendingPathComponent("radiators.json"))
        }
        if let structure { try RoomPackage.encoder.encode(structure).write(to: staging.appendingPathComponent(F.structure)) }
        if let capturedStructureData { try capturedStructureData.write(to: staging.appendingPathComponent(F.capturedStructure)) }
        if let usdzData { try usdzData.write(to: staging.appendingPathComponent(F.usdz)) }
        if let thumbnailPNG { try thumbnailPNG.write(to: staging.appendingPathComponent(F.thumbnail)) }
        try SurveyPhotoStore.write(surveyPhotos,assets:surveyPhotoAssets,to:staging)
        for room in rooms {
            try room.write(to: staging.appendingPathComponent(F.rooms).appendingPathComponent(room.record.id.uuidString).appendingPathExtension(FileLayout.packageExtension))
        }
        try fm.createDirectory(at: packageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RoomPackage.coordinatedWrite(at: packageURL, options: .forReplacing) { url in
            try PackageReplacement.commit(staging,to:url,fm:fm)
        }
    }

    // MARK: Lecture

    static func readRecord(from url: URL) throws -> HouseRecord {
        try RoomPackage.coordinatedRead(at: url) { u in try RoomPackage.decoder.decode(HouseRecord.self, from: SafePackageRead.data(u.appendingPathComponent(F.meta),root:u)) }
    }

    static func readHouse(from url: URL) throws -> House {
        try RoomPackage.coordinatedRead(at: url) { u in try RoomPackage.decoder.decode(House.self, from: SafePackageRead.data(u.appendingPathComponent(F.house),root:u)) }
    }
    static func readRadiators(from url: URL) throws -> HouseRadiatorSurvey? {
        try RoomPackage.coordinatedRead(at: url) { root in
            let file = root.appendingPathComponent("radiators.json")
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            let base = root.resolvingSymlinksInPath().standardizedFileURL
            let resolved = file.resolvingSymlinksInPath().standardizedFileURL
            let attributes = try FileManager.default.attributesOfItem(atPath: resolved.path)
            guard resolved.path.hasPrefix(base.path+"/"),attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber,size.intValue <= 64 * 1_048_576 else { throw HouseRadiatorSurvey.Failure.invalid }
            let result = try RoomPackage.decoder.decode(HouseRadiatorSurvey.self,from: SafePackageRead.data(file,root:root,maximum:64*1_048_576))
            let house = try RoomPackage.decoder.decode(House.self,from: SafePackageRead.data(root.appendingPathComponent(F.house),root:root))
            try result.validate(for: house)
            return result
        }
    }
    static func writeRadiators(_ survey: HouseRadiatorSurvey,house: House,in url: URL) throws {
        try survey.validate(for: house)
        let data = try RoomPackage.encoder.encode(survey)
        guard data.count <= 64 * 1_048_576 else { throw HouseRadiatorSurvey.Failure.invalid }
        try RoomPackage.coordinatedWrite(at: url,options: .forMerging) { root in
            let target = root.appendingPathComponent("radiators.json")
            if FileManager.default.fileExists(atPath: target.path) {
                guard try FileManager.default.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType != .typeSymbolicLink else { throw HouseRadiatorSurvey.Failure.invalid }
            }
            try data.write(to: target,options: .atomic)
        }
    }

    static func readStructure(from url: URL) throws -> StructureInput? {
        try RoomPackage.coordinatedRead(at: url) { u in
            let f = u.appendingPathComponent(F.structure)
            guard FileManager.default.fileExists(atPath: f.path) else { return nil }
            return try RoomPackage.decoder.decode(StructureInput.self, from: SafePackageRead.data(f,root:u))
        }
    }

    /// URLs of nested room packages.
    static func roomPackageURLs(in url: URL) -> [URL] {
        let dir = url.appendingPathComponent(F.rooms, isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == FileLayout.packageExtension }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func usdzURL(in url: URL) -> URL? {
        let f = url.appendingPathComponent(F.usdz); return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }
    static func thumbnailURL(in url: URL) -> URL? {
        let f = url.appendingPathComponent(F.thumbnail); return FileManager.default.fileExists(atPath: f.path) ? f : nil
    }

    /// Rewrites `meta.json` and `house.json` (rename, recalculate) preserving assets.
    static func update(record: HouseRecord, house: House, in url: URL) throws {
        try RoomPackage.coordinatedWrite(at: url, options: .forMerging) { u in
            try RoomPackage.encoder.encode(record).write(to: u.appendingPathComponent(F.meta), options: .atomic)
            try RoomPackage.encoder.encode(house).write(to: u.appendingPathComponent(F.house), options: .atomic)
        }
    }

    static func writeThumbnail(_ png: Data, in url: URL) throws {
        try RoomPackage.coordinatedWrite(at: url, options: .forMerging) { u in try png.write(to: u.appendingPathComponent(F.thumbnail), options: .atomic) }
    }

    static func delete(at url: URL) throws {
        try RoomPackage.coordinatedWrite(at: url, options: .forDeleting) { u in try FileManager.default.removeItem(at: u) }
    }
}

extension UTType {
    /// `io.github.itsmebablu.dwalkscan.house`, declared in Info.plist of both targets.
    static let houseScan = UTType(exportedAs: "io.github.itsmebablu.dwalkscan.house", conformingTo: .package)
    static let legacyHouseScan = UTType("fr.vincentlauriat.roomscanner.house")
}
