import XCTest
@testable import RoomScanner

final class SavedExportFilesTests:XCTestCase {
    func testCancelledRequestCannotReturnAnExistingExport() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let saved = root.appendingPathComponent("saved"),source = root.appendingPathComponent("Room.pdf")
        try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
        let bytes = Data("saved plan".utf8)
        try bytes.write(to:source)
        let existing = try SavedExportFiles.store(source,in:saved)
        let request = Task<Void,Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try SavedExportFiles.store(source,in:saved)) { XCTAssertTrue($0 is CancellationError) }
        }
        await request.value
        XCTAssertEqual(try Data(contentsOf:existing),bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:saved.path).count,1)
    }

    func testSourceReplacementCannotReuseAnEarlierExport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let saved = root.appendingPathComponent("saved"),source = root.appendingPathComponent("Room.pdf")
        try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
        let old = Data("old plan".utf8),new = Data("new plan".utf8)
        try old.write(to:source)
        let existing = try SavedExportFiles.store(source,in:saved)
        XCTAssertThrowsError(try SavedExportFiles.store(source,in:saved,fault:{ stage in
            if stage == .afterSourceHash { try new.write(to:source,options:.atomic) }
        }))
        XCTAssertEqual(try Data(contentsOf:existing),old)
        XCTAssertEqual(try Data(contentsOf:source),new)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:saved.path).count,1)
        XCTAssertEqual(try SavedExportFiles.store(source,in:saved).lastPathComponent,"Room - 2.pdf")
    }

    func testCopyFailureOrCancellationRetainsPriorExportAndAllowsRetry() throws {
        for cancelled in [false,true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let saved = root.appendingPathComponent("saved"),source = root.appendingPathComponent("Room.pdf")
            try FileManager.default.createDirectory(at:saved,withIntermediateDirectories:true)
            try Data("old plan".utf8).write(to:source)
            let existing = try SavedExportFiles.store(source,in:saved)
            let new = Data("new plan".utf8)
            try new.write(to:source,options:.atomic)
            XCTAssertThrowsError(try SavedExportFiles.store(source,in:saved,fault:{ stage in
                if stage == .afterCopy {
                    if cancelled { throw CancellationError() }
                    throw CocoaError(.fileWriteOutOfSpace)
                }
            }))
            XCTAssertEqual(try Data(contentsOf:existing),Data("old plan".utf8))
            XCTAssertEqual(try Data(contentsOf:source),new)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:saved.path).count,1)
            XCTAssertEqual(try Data(contentsOf:SavedExportFiles.store(source,in:saved)),new)
        }
    }

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
