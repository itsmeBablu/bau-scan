import XCTest
@testable import RoomScanner

final class VoiceNoteRecoveryTests: XCTestCase {
    func testRecoveryIsIdempotentAndKeepsUnrelatedDrafts() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let outbox = root.appendingPathComponent("outbox"),destination = root.appendingPathComponent("library"),project = UUID()
        let ref = ProjectReference(kind:.technicalRoom,itemID:UUID(),library:"local")
        var note = ARNote(projectID:project,reference:ref,number:1,level:nil,roomID:ref.itemID,position:nil,planPosition:nil,language:"de")
        note.audioFileName = "note-01.m4a"; note.audioDuration = 1
        let header = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        try VoiceNoteRecovery.stage(note,audio:header,at:outbox)
        try VoiceNoteRecovery.stage(note,audio:header,at:outbox)
        XCTAssertEqual(try ARNoteStore.index(root:outbox,projectID:project).notes.count,1)
        try VoiceNoteRecovery.recover(projectID:project,from:outbox,to:destination,references:[])
        XCTAssertEqual(try ARNoteStore.index(root:outbox,projectID:project).notes.count,1)
        for _ in 0..<2 { try VoiceNoteRecovery.recover(projectID:project,from:outbox,to:destination,references:[ref]) }
        XCTAssertEqual(try ARNoteStore.read(root:destination,projectID:project).audio[note.id],header)
        XCTAssertTrue(try ARNoteStore.index(root:outbox,projectID:project).notes.isEmpty)
    }
}
