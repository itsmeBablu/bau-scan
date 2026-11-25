import XCTest
@testable import RoomScanner

final class OrganisedExportPresetTests: XCTestCase {
    func testEveryPresetMatchesAndKeepsExplicitSurveyIDsAndLocale() {
        let survey = UUID()
        for preset in OrganisedExportPreset.allCases where preset != .custom {
            var options = OrganisedExportService.Options()
            options.technicalRoomID = survey; options.locale = Locale(identifier:"de_DE")
            preset.apply(to:&options)
            XCTAssertEqual(OrganisedExportPreset.matching(options),preset)
            XCTAssertEqual(options.technicalRoomID,survey)
            XCTAssertEqual(options.locale.identifier,"de_DE")
        }
    }
    func testPhotosExcludeTechnicalSurveysAndNativeCopies() {
        var options = OrganisedExportService.Options(); options.technicalRoomID = UUID()
        OrganisedExportPreset.photos.apply(to:&options)
        XCTAssertTrue(options.photosOnly)
        XCTAssertFalse(options.includeNativePackages)
        XCTAssertTrue(OrganisedExportService.selectedTechnicalRoomIDs(options:options).isEmpty)
    }
    func testTechnicalPresetDoesNotInventHouseRegistration() {
        var options = OrganisedExportService.Options()
        OrganisedExportPreset.technical.apply(to:&options)
        XCTAssertTrue(options.includeIFC)
        XCTAssertFalse(options.includeArchitectureIFC)
        XCTAssertNil(options.technicalRoomID)
    }
    func testNativeSnapshotKeepsSourceBytesAndCanBeReadWithoutMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Bad")
        let package = RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:nil)
        let source = root.appendingPathComponent("source.roomscan"),copy = root.appendingPathComponent("copy.roomscan")
        try package.write(to:source)
        try NativeExportSnapshot.copy(from:source,to:copy)
        let paths = try NativeExportSnapshot.files(in:source)
        XCTAssertEqual(try NativeExportSnapshot.files(in:copy),paths)
        for path in paths { XCTAssertEqual(try ExportChecksum.sha256(source.appendingPathComponent(path)),try ExportChecksum.sha256(copy.appendingPathComponent(path))) }
        XCTAssertEqual(try RoomPackage.read(from:copy).plan,plan)
        XCTAssertEqual(try RoomPackage.readRecord(from:copy).id,package.record.id)
    }
}
