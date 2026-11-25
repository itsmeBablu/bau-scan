import XCTest
@testable import RoomScanner

final class PackageReplacementTests: XCTestCase {
    func testFailedRenamePreservesOriginalAndLaunchRecoveryRestoresBackup() throws {
        let fm = FileManager.default,root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at:root) }
        let target = root.appendingPathComponent("test.roomscan")
        try fm.createDirectory(at:target,withIntermediateDirectories:true)
        try Data("original".utf8).write(to:target.appendingPathComponent("meta.json"))
        let stage = try PackageReplacement.staging(for:target)
        XCTAssertEqual(stage.deletingLastPathComponent(),target.deletingLastPathComponent())
        try fm.createDirectory(at:stage,withIntermediateDirectories:true)
        XCTAssertThrowsError(try PackageReplacement.commit(stage,to:target,move:{ from,to in
            if from == stage { throw CocoaError(.fileWriteUnknown) }
            try fm.moveItem(at:from,to:to)
        }))
        XCTAssertEqual(try Data(contentsOf:target.appendingPathComponent("meta.json")),Data("original".utf8))
        try fm.moveItem(at:target,to:PackageReplacement.backup(for:target))
        try PackageReplacement.recover(in:root)
        XCTAssertEqual(try Data(contentsOf:target.appendingPathComponent("meta.json")),Data("original".utf8))
        try PackageReplacement.commit(stage,to:target)
        XCTAssertFalse(fm.fileExists(atPath:PackageReplacement.backup(for:target).path))
    }
}
