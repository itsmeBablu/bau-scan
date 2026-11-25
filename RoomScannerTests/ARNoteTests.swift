import XCTest
@testable import RoomScanner

final class ARNoteTests: XCTestCase {
    func testDirectScanNotesKeepExistingProjectAndLibraryIdentity() throws {
        let id = UUID(),local = ProjectReference(kind: .house,itemID: id,library: "local")
        let cloud = ProjectReference(kind: .house,itemID: id,library: "icloud")
        let existing = RenovationProject(name: "Flat",references: [local])
        var index = ProjectIndex(projects: [existing])
        XCTAssertEqual(try index.voiceNotesProject(for: local),existing.id)
        XCTAssertEqual(index.projects.count,1)
        XCTAssertEqual(try index.voiceNotesProject(for: cloud),ProjectIndex.unsortedID)
        XCTAssertEqual(index.projects.first?.references,[local])
        XCTAssertEqual(try index.voiceNotesProject(for: cloud),ProjectIndex.unsortedID)
        XCTAssertEqual(index.projects.count,2)
        XCTAssertThrowsError(try index.voiceNotesProject(for: .init(kind: .designHouse,itemID: id,library: "local")))
    }
    func testLiveCaptureNotesUseSelectedProjectWithoutMovingExistingScans() throws {
        let a = RenovationProject(name:"A"),b = RenovationProject(name:"B")
        var index = ProjectIndex(projects:[a,b])
        let reference = ProjectReference(kind:.technicalRoom,itemID:UUID(),library:"local")
        XCTAssertEqual(try index.voiceNotesProject(for:reference,preferredProjectID:a.id),a.id)
        XCTAssertEqual(try index.voiceNotesProject(for:reference,preferredProjectID:b.id),a.id)
        XCTAssertTrue(index.projects[1].references.isEmpty)
    }
    private func note(projectID: UUID,roomID: UUID? = nil) -> ARNote {
        .init(projectID:projectID,reference:.init(kind:.room,itemID:UUID(),library:"local"),number:1,
              level:0,roomID:roomID,position:.init(x:1,y:2,z:3),planPosition:nil,language:"de-DE")
    }
    func testRoundTripPinAndSource() throws {
        let original = note(projectID:UUID())
        try original.validate()
        XCTAssertEqual(try JSONDecoder().decode(ARNote.self,from:JSONEncoder().encode(original)),original)
        let pin = try XCTUnwrap(original.pin()); try pin.validate()
        XCTAssertEqual(pin.position,Point2D(x:1,y:-3))
        XCTAssertNil(pin.photoID); XCTAssertNil(original.accuracyMm)
        XCTAssertEqual(original.positionSource,"scan-derived")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(original)) as? [String:Any])
        XCTAssertEqual(json["positionSource"] as? String,"scan-derived")
        XCTAssertTrue(json["accuracyMm"] is NSNull)
        XCTAssertEqual(json["deviceValidationPending"] as? Bool,true)
        var unplaced = original; unplaced.position = nil
        XCTAssertNil(unplaced.pin())
    }
    func testLengthNamingPartialAndNumberingLimits() throws {
        let id = UUID(),room = UUID()
        for duration in [0.49,60.01,Double.nan,Double.infinity] {
            var item = note(projectID:id); item.audioFileName = "note-01.m4a"; item.audioDuration = duration
            XCTAssertThrowsError(try item.validate())
        }
        var item = note(projectID:id,roomID:room)
        item.audioFileName = "note-01.m4a"; item.audioDuration = 0.5; item.partial = true; item.transcriptState = .pending
        try item.validate()
        let index = ARNoteIndex(projectID:id,notes:[item]); try index.validate()
        XCTAssertEqual(try index.nextNumber(roomID:room),2)
        XCTAssertEqual(try index.nextNumber(roomID:UUID()),1)
        item.audioFileName = "../escape.m4a"; XCTAssertThrowsError(try item.validate())
    }
    func testTechnicalNotesDoNotExpandTheArchitecturalPinFormat() throws {
        var item = note(projectID:UUID()); item.reference.kind = .technicalRoom
        try item.validate(); XCTAssertNil(item.pin())
    }
    func testTitleRoundTripAndLengthLimit() throws {
        var item = note(projectID:UUID()); item.title = "Heizung Rücklauf"
        XCTAssertEqual(try JSONDecoder().decode(ARNote.self,from:JSONEncoder().encode(item)).title,item.title)
        item.title = String(repeating:"x",count:201)
        XCTAssertThrowsError(try item.validate())
    }
    func testMissingAudioFailsInsteadOfDroppingTheNote() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),id = UUID()
        defer { try? FileManager.default.removeItem(at:root) }
        var item = note(projectID:id); item.audioFileName = item.stem+".m4a"; item.audioDuration = 1
        let header = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        try ARNoteStore.update(root:root,projectID:id,audio:[item.id:header]) { $0.notes.append(item) }
        try FileManager.default.removeItem(at:ARNoteStore.url(root:root,projectID:id).appendingPathComponent(try XCTUnwrap(item.audioPath)))
        XCTAssertThrowsError(try ARNoteStore.read(root:root,projectID:id))
        XCTAssertEqual(try ARNoteStore.index(root:root,projectID:id).notes.count,1)
    }
    func testCorruptExistingIndexIsNeverTreatedAsAnEmptyLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),id = UUID()
        defer { try? FileManager.default.removeItem(at:root) }
        let directory = ARNoteStore.url(root:root,projectID:id)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        try Data("corrupt".utf8).write(to:directory.appendingPathComponent("index-v1.json"))
        XCTAssertThrowsError(try ARNoteStore.read(root:root,projectID:id))
        XCTAssertThrowsError(try ARNoteStore.update(root:root,projectID:id) { _ in })
        XCTAssertEqual(try String(contentsOf:directory.appendingPathComponent("index-v1.json"),encoding:.utf8),"corrupt")
    }
    func testLegacyMissingIndexAndAtomicSaveDoNotRewriteSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),id = UUID()
        defer { try? FileManager.default.removeItem(at:root) }
        XCTAssertTrue(try ARNoteStore.read(root:root,projectID:id).index.notes.isEmpty)
        var item = note(projectID:id); item.text = "Valve label"
        try ARNoteStore.update(root:root,projectID:id) { $0.notes.append(item) }
        XCTAssertEqual(try ARNoteStore.read(root:root,projectID:id).index.notes,[item])
        XCTAssertThrowsError(try ARNoteStore.update(root:root,projectID:id) { $0.notes[0].number = 0 })
        XCTAssertEqual(try ARNoteStore.read(root:root,projectID:id).index.notes,[item])
    }
    func testAudioRoundTripCapAndRemovingAudioMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),id = UUID()
        defer { try? FileManager.default.removeItem(at:root) }
        var item = note(projectID:id); item.audioFileName = "note-01.m4a"; item.audioDuration = 12; item.partial = true
        let containerHeader = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        try ARNoteStore.update(root:root,projectID:id,audio:[item.id:containerHeader]) { $0.notes.append(item) }
        XCTAssertEqual(try ARNoteStore.read(root:root,projectID:id).audio[item.id],containerHeader)
        XCTAssertThrowsError(try ARNoteStore.update(root:root,projectID:id,audio:[item.id:Data(repeating:0,count:ARNoteIndex.maximumClipBytes+1)]) { _ in })
        try ARNoteStore.update(root:root,projectID:id) { index in
            index.notes[0].audioFileName = nil; index.notes[0].audioDuration = nil; index.notes[0].partial = nil
        }
        XCTAssertTrue(try ARNoteStore.read(root:root,projectID:id).audio.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath:ARNoteStore.url(root:root,projectID:id).appendingPathComponent(item.audioPath!).path))
    }
    func testInterruptedReplacementReadsBackupAndRestoresBeforeEditing() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),id = UUID()
        defer { try? FileManager.default.removeItem(at:root) }
        let original = note(projectID:id)
        try ARNoteStore.update(root:root,projectID:id) { $0.notes.append(original) }
        let target = ARNoteStore.url(root:root,projectID:id)
        try FileManager.default.moveItem(at:target,to:target.deletingLastPathComponent().appendingPathComponent(".ARNotes-backup"))
        XCTAssertEqual(try ARNoteStore.read(root:root,projectID:id).index.notes,[original])
        try ARNoteStore.update(root:root,projectID:id) { $0.notes[0].text = "Recovered" }
        XCTAssertEqual(try ARNoteStore.read(root:root,projectID:id).index.notes[0].text,"Recovered")
    }
    func testProjectAudioCapRejectsBeforeWritingAndPreservesEmptyLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),id = UUID()
        defer { try? FileManager.default.removeItem(at:root) }
        let header = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        let clip = header+Data(repeating:0,count:ARNoteIndex.maximumClipBytes-header.count)
        var notes: [ARNote] = [],audio: [UUID:Data] = [:]
        for number in 1...65 {
            var item = note(projectID:id); item.number = number
            item.audioFileName = item.stem+".m4a"; item.audioDuration = 60
            notes.append(item); audio[item.id] = clip
        }
        XCTAssertThrowsError(try ARNoteStore.update(root:root,projectID:id,audio:audio) { $0.notes = notes })
        XCTAssertTrue(try ARNoteStore.read(root:root,projectID:id).index.notes.isEmpty)
    }
}
