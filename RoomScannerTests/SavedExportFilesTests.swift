import XCTest
@testable import RoomScanner

final class SavedExportFilesTests:XCTestCase {
    func testIdenticalFileIsNotSavedAgainUnderDifferentName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let saved = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
        let first = root.appendingPathComponent("Ground Floor - Reception.pdf"),second = root.appendingPathComponent("Another label.pdf")
        try Data("same plan".utf8).write(to:first); try Data("same plan".utf8).write(to:second)
        let original = try SavedExportFiles.store(first,in:saved)
        XCTAssertEqual(try SavedExportFiles.store(second,in:saved),original)
        XCTAssertEqual(original.lastPathComponent,first.lastPathComponent)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:saved.path).count,1)
    }
    func testChangedContentKeepsPreviousFileAndGetsNumberedVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let saved = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
        let source = root.appendingPathComponent("Reception.pdf")
        try Data("old plan".utf8).write(to:source)
        let original = try SavedExportFiles.store(source,in:saved)
        try Data("new plan".utf8).write(to:source,options:.atomic)
        let revised = try SavedExportFiles.store(source,in:saved)
        XCTAssertEqual(revised.lastPathComponent,"Reception - 2.pdf")
        XCTAssertEqual(try Data(contentsOf:original),Data("old plan".utf8))
        XCTAssertEqual(try Data(contentsOf:revised),Data("new plan".utf8))
        XCTAssertEqual(try SavedExportFiles.store(source,in:saved),revised)
    }
}
