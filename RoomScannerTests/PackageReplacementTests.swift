import XCTest
@testable import RoomScanner

final class PackageReplacementTests: XCTestCase {
    func testOutOfSpaceDuringPublicationPreservesOriginalAndRetry() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("survey.housescan")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: target.appendingPathComponent("house.json"))
        let stage = try PackageReplacement.staging(for: target)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        try Data("replacement".utf8).write(to: stage.appendingPathComponent("house.json"))
        XCTAssertThrowsError(try PackageReplacement.commit(stage, to: target, move: { from, to in
            if from == stage { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.moveItem(at: from, to: to)
        }))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("house.json")), Data("original".utf8))
        XCTAssertTrue(fm.fileExists(atPath: stage.path))
        try PackageReplacement.commit(stage, to: target)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("house.json")), Data("replacement".utf8))
    }

    func testFailedRollbackKeepsBackupForReopen() throws {
        let fm = RollbackFailureFileManager(), root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("survey.roomscan")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: target.appendingPathComponent("plan.json"))
        let stage = try PackageReplacement.staging(for: target)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        fm.stage = stage
        XCTAssertThrowsError(try PackageReplacement.commit(stage, to: target, fm: fm))
        XCTAssertFalse(fm.fileExists(atPath: target.path))
        XCTAssertEqual(try Data(contentsOf: PackageReplacement.backup(for: target).appendingPathComponent("plan.json")), Data("original".utf8))
        // A reopened normal writer can recover the retained original.
        try PackageReplacement.recover(target)
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("plan.json")), Data("original".utf8))
    }

    func testFailureBeforeOriginalMoveLeavesBothInputsUntouched() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let target = root.appendingPathComponent("survey.roomscan")
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: target.appendingPathComponent("plan.json"))
        let stage = try PackageReplacement.staging(for: target)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        XCTAssertThrowsError(try PackageReplacement.commit(stage, to: target, move: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }))
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("plan.json")), Data("original".utf8))
        XCTAssertTrue(fm.fileExists(atPath: stage.path))
        XCTAssertFalse(fm.fileExists(atPath: PackageReplacement.backup(for: target).path))
    }

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

private final class RollbackFailureFileManager: FileManager, @unchecked Sendable {
    var stage: URL?
    override func moveItem(at source: URL, to destination: URL) throws {
        if source == stage || source.lastPathComponent.hasSuffix(".package-backup") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: source, to: destination)
    }
}
