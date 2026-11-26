import XCTest
@testable import RoomScanner

final class SavedScanEvidenceTests: XCTestCase {
    func testBadNoteCatalogueDoesNotHideLazyPhotoMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from:scan,name:"Room")
        let photo = SurveyPhoto(id:UUID(),roomID:plan.id,number:1,pose:SyntheticWorkload.pose,timestamp:1)
        let url = root.appendingPathComponent("Rooms/\(plan.id.uuidString).roomscan")
        try RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:scan,
                        surveyPhotos:[photo],surveyPhotoAssets:[photo.id:Data([0xff,0xd8])]).write(to:url)
        let catalogue = root.appendingPathComponent("Projects/index-v1.json")
        try FileManager.default.createDirectory(at:catalogue.deletingLastPathComponent(),withIntermediateDirectories:true)
        try Data("corrupt".utf8).write(to:catalogue)
        let loaded = try SavedScanEvidence.load(packageURL:url,house:House(room:plan),notesRoot:root)
        XCTAssertNotNil(loaded.noteFailure)
        XCTAssertNil(loaded.photoFailure)
        XCTAssertEqual(loaded.photos.map(\.photo.id),[photo.id])
        XCTAssertEqual(loaded.photos.first?.reference.library,"local")
        XCTAssertEqual(try loaded.photos[0].image().jpegData,Data([0xff,0xd8]))
    }

    func testBadPhotoIndexDoesNotHideRegisteredNotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let scan = SyntheticRooms.rectangularRoom().scan
        let plan = FloorPlanBuilder().build(from:scan,name:"Room"), projectID = UUID()
        let url = root.appendingPathComponent("Rooms/\(plan.id.uuidString).roomscan")
        try RoomPackage(record:RoomRecord(plan:plan),plan:plan,scan:scan).write(to:url)
        let reference = ProjectReference(kind:.room,itemID:plan.id,library:"local")
        _ = try ProjectIndexStore.update(root:root) { index in
            index.projects.append(.init(id:projectID,name:"Project",references:[reference]))
        }
        var note = ARNote(projectID:projectID,reference:reference,number:1,level:0,roomID:scan.id,
                          position:.init(x:0,y:1,z:0),planPosition:nil,language:"en")
        note.text = "Check valve"; _ = try ARNoteStore.upsertText(note,root:root)
        try Data("corrupt".utf8).write(to:url.appendingPathComponent("survey-photos.json"))
        let loaded = try SavedScanEvidence.load(packageURL:url,house:House(room:plan),notesRoot:root)
        XCTAssertNil(loaded.noteFailure)
        XCTAssertNotNil(loaded.photoFailure)
        XCTAssertEqual(loaded.notes.map(\.id),[note.id])
        XCTAssertNotNil(loaded.notes.first?.viewingPosition)
        XCTAssertTrue(loaded.photos.isEmpty)
    }
}
