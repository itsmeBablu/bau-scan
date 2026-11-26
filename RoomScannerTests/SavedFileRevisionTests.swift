import XCTest
@testable import RoomScanner

final class SavedFileRevisionTests:XCTestCase {
    func testAtomicReplacementWithSameDateAndLengthHasADifferentRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("metadata.json"), date = Date(timeIntervalSince1970:1_700_000_000)
        try Data("old".utf8).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:file.path)
        let before = try SavedFileRevision(file)
        XCTAssertEqual(before,try SavedFileRevision(file))
        try Data("new".utf8).write(to:file,options:.atomic)
        try FileManager.default.setAttributes([.modificationDate:date],ofItemAtPath:file.path)
        let after = try SavedFileRevision(file)
        XCTAssertEqual(before.modified,after.modified)
        XCTAssertEqual(before.bytes,after.bytes)
        XCTAssertEqual(before.path,after.path)
        XCTAssertNotEqual(before.fileID,after.fileID)
        XCTAssertNotEqual(before,after)
    }

    func testDirectoryAndSymbolicLinkAreNotRegularRevisionSources() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let file = root.appendingPathComponent("file"), link = root.appendingPathComponent("link")
        try Data([1]).write(to:file)
        try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file)
        XCTAssertThrowsError(try SavedFileRevision(root))
        XCTAssertThrowsError(try SavedFileRevision(link))
        XCTAssertEqual(try SavedFileRevision(file).bytes,1)
    }
}
