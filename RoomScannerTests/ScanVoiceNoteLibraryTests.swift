import XCTest
@testable import RoomScanner

final class ScanVoiceNoteLibraryTests:XCTestCase {
    func testCloudScanLoadsLocalCatalogueNotesWithoutMixingLocalTwin() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:base) }
        let catalogue = base.appendingPathComponent("local"),cloud = base.appendingPathComponent("cloud")
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from:scan,name:"Test room"),owner = UUID()
        let package = RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:scan)
        let url = StorageLocation(kind:.iCloud,documentsURL:cloud).packageURL(for:package.record.id)
        try package.write(to:url)
        let remote = ProjectReference(kind:.room,itemID:package.record.id,library:"icloud")
        let local = ProjectReference(kind:.room,itemID:package.record.id,library:"local")
        _ = try ProjectIndexStore.update(root:catalogue) { index in
            index.projects.append(.init(id:owner,name:"Test"))
            try index.assign(remote,to:owner); try index.assign(local,to:owner)
        }
        var note = ARNote(projectID:owner,reference:remote,number:1,level:0,roomID:scan.id,position:.init(x:0,y:1,z:0),planPosition:nil,language:"en")
        note.text = "Cloud scan note"; _ = try ARNoteStore.upsertText(note,root:catalogue)
        var twin = note; twin.id = UUID(); twin.reference = local; twin.text = "Local twin note"
        _ = try ARNoteStore.upsertText(twin,root:catalogue)
        let loaded = try ScanVoiceNoteLibrary.registeredNotes(packageURL:url,house:House(room:plan),catalogueRoot:catalogue)
        XCTAssertEqual(loaded.map(\.id),[note.id])
        XCTAssertEqual(loaded.first?.text,note.text)
        XCTAssertNotNil(loaded.first?.viewingPosition)
        XCTAssertFalse(FileManager.default.fileExists(atPath:cloud.appendingPathComponent("Projects").path))
    }
    func testLegacyDirectCaptureNotesRemainVisibleWithoutCatalogue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let reference = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let note = ARNote(projectID:ProjectIndex.unsortedID,reference:reference,number:1,level:0,roomID:nil,position:.init(x:1,y:1,z:1),planPosition:nil,language:"en")
        _ = try ARNoteStore.upsertText(note,root:root)
        XCTAssertEqual(try ScanVoiceNoteLibrary.notes(for:reference,root:root).map(\.id),[note.id])
    }
    func testCanonicalLocalStorageKeepsLocalReference() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertEqual(ScanVoiceNoteLibrary.reference(itemID:UUID(),kind:.house,storageRoot:root.resolvingSymlinksInPath(),catalogueRoot:root).library,"local")
    }
}
