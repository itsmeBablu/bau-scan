import XCTest
@testable import RoomScanner

final class PackageReplacementTests: XCTestCase {
    func testExistingTargetDoesNotCauseRecoveryBackupToBeDeleted() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let target = root.appendingPathComponent("survey.roomscan"), backup = PackageReplacement.backup(for:target)
        let staging = try PackageReplacement.staging(for:target)
        try Data("possibly incomplete current".utf8).write(to:target)
        try Data("last good recovery".utf8).write(to:backup)
        try Data("new attempted save".utf8).write(to:staging)
        try PackageReplacement.recover(target)
        XCTAssertEqual(try Data(contentsOf:target),Data("possibly incomplete current".utf8))
        XCTAssertEqual(try Data(contentsOf:backup),Data("last good recovery".utf8))
        XCTAssertThrowsError(try PackageReplacement.commit(staging,to:target)) { error in
            guard case PackageReplacement.RecoveryConflict.existingBackup = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf:backup),Data("last good recovery".utf8))
        XCTAssertEqual(try Data(contentsOf:staging),Data("new attempted save".utf8))
        // Explicit resolution outside the library can remove the current item;
        // the existing recovery path then restores exactly the backup bytes.
        try FileManager.default.removeItem(at:target)
        try PackageReplacement.recover(target)
        XCTAssertEqual(try Data(contentsOf:target),Data("last good recovery".utf8))
    }
    func testPreparedReplacementRejectsExistingRecoveryCopyWithoutTouchingAnything() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("survey.technicalroom")
        let stage = root.appendingPathComponent(".technical-writing-test")
        let backup = root.appendingPathComponent(".technical-backup-test")
        for (url, text) in [(target, "current"), (stage, "pending"), (backup, "recovery")] {
            try Data(text.utf8).write(to: url)
        }
        XCTAssertThrowsError(try PackageReplacement.commitPrepared(stage, to: target, backup: backup))
        XCTAssertEqual(try Data(contentsOf: target), Data("current".utf8))
        XCTAssertEqual(try Data(contentsOf: stage), Data("pending".utf8))
        XCTAssertEqual(try Data(contentsOf: backup), Data("recovery".utf8))
    }

    func testPreparedReplacementPreservesTechnicalBackupConventionOnFailure() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("survey.technicalroom")
        let stage = root.appendingPathComponent(".technical-writing-test")
        let backup = root.appendingPathComponent(".technical-backup-test")
        try Data("original".utf8).write(to: target)
        try Data("pending".utf8).write(to: stage)
        XCTAssertThrowsError(try PackageReplacement.commitPrepared(stage, to: target, backup: backup, move: { from, to in
            if from == stage { throw CocoaError(.fileWriteOutOfSpace) }
            try fm.moveItem(at: from, to: to)
        }))
        XCTAssertEqual(try Data(contentsOf: target), Data("original".utf8))
        XCTAssertEqual(try Data(contentsOf: stage), Data("pending".utf8))
        XCTAssertFalse(fm.fileExists(atPath: backup.path))
    }

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
