import XCTest
@testable import RoomScanner

final class PackageCatalogueTests: XCTestCase {
    func testMetadataEnumerationDoesNotDecodeGeometryAndRejectsWrongIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        let record = RoomRecord(plan: plan)
        let package = root.appendingPathComponent(record.id.uuidString + ".roomscan")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try RoomPackage.encoder.encode(record).write(to: package.appendingPathComponent("meta.json"))
        try Data("not decoded by catalogue".utf8).write(to: package.appendingPathComponent("plan.json"))
        let first = try PackageCatalogue.rooms(in: root)
        XCTAssertEqual(first.records, [record]); XCTAssertTrue(first.problems.isEmpty)
        XCTAssertEqual(first.urls[record.id]?.resolvingSymlinksInPath().path, package.resolvingSymlinksInPath().path)
        let mismatched = root.appendingPathComponent(UUID().uuidString + ".roomscan")
        try FileManager.default.moveItem(at: package, to: mismatched)
        let invalid = try PackageCatalogue.rooms(in: root)
        XCTAssertTrue(invalid.records.isEmpty)
        XCTAssertEqual(invalid.problems.map { $0.url.resolvingSymlinksInPath().path }, [mismatched.resolvingSymlinksInPath().path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: mismatched.path))
    }

    func testFutureAndUnreadableMetadataRemainDiagnosticsRatherThanDisappearing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Future")
        var record = RoomRecord(plan: plan); record.schemaVersion = FloorPlan.schemaVersion + 1
        let future = root.appendingPathComponent(record.id.uuidString + ".roomscan")
        let corrupt = root.appendingPathComponent(UUID().uuidString + ".roomscan")
        for url in [future, corrupt] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        try RoomPackage.encoder.encode(record).write(to: future.appendingPathComponent("meta.json"))
        try Data("broken".utf8).write(to: corrupt.appendingPathComponent("meta.json"))
        let result = try PackageCatalogue.rooms(in: root)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(Set(result.problems.map(\.reason)), [.unsupportedSchema, .corrupt])
        XCTAssertTrue(FileManager.default.fileExists(atPath: future.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
    }

    func testIdenticalIDsInSeparateLibrariesDoNotSharePathsOrState() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let local = root.appendingPathComponent("local"), cloud = root.appendingPathComponent("cloud")
        for (directory, name) in [(local, "Local"), (cloud, "Cloud")] {
            let package = directory.appendingPathComponent(id.uuidString + ".technicalroom")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try JSONEncoder().encode(TechnicalRoomManifest(id: id, name: name)).write(to: package.appendingPathComponent("manifest.json"))
        }
        let a = try PackageCatalogue.technicalRooms(in: local)
        let b = try PackageCatalogue.technicalRooms(in: cloud)
        XCTAssertEqual(a.records.first?.name, "Local"); XCTAssertEqual(b.records.first?.name, "Cloud")
        XCTAssertNotEqual(a.urls[id], b.urls[id])
        let missing = try PackageCatalogue.technicalRooms(in: root.appendingPathComponent("missing"))
        XCTAssertTrue(missing.records.isEmpty); XCTAssertTrue(missing.problems.isEmpty)
    }
}
