import XCTest
@testable import RoomScanner

final class VoiceNoteRecoveryTests: XCTestCase {
    func testConflictingAudioNeverOverwritesDestinationOrDeletesRecoveryCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let outbox = root.appendingPathComponent("outbox"),destination = root.appendingPathComponent("destination"),project = UUID()
        let ref = ProjectReference(kind:.room,itemID:UUID(),library:"local")
        var note = ARNote(projectID:project,reference:ref,number:1,level:nil,roomID:ref.itemID,position:nil,planPosition:nil,language:"en")
        note.audioFileName = "note-01.m4a"; note.audioDuration = 1
        let header = Data([0,0,0,16])+Data("ftypM4A ".utf8),changed = header+Data([1])
        try VoiceNoteRecovery.stage(note,audio:header,at:outbox)
        try ARNoteStore.update(root:destination,projectID:project,audio:[note.id:changed]) { $0.notes.append(note) }
        XCTAssertThrowsError(try VoiceNoteRecovery.recover(projectID:project,from:outbox,to:destination,references:[ref]))
        XCTAssertEqual(try ARNoteStore.read(root:destination,projectID:project).audio[note.id],changed)
        XCTAssertEqual(try ARNoteStore.read(root:outbox,projectID:project).audio[note.id],header)
    }
    func testPinnedNoteCanGainAudioAndRecoverReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let outbox = root.appendingPathComponent("outbox"),destination = root.appendingPathComponent("library"),project = UUID()
        let ref = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        var note = ARNote(projectID:project,reference:ref,number:1,level:0,roomID:nil,position:.init(x:1,y:1,z:1),planPosition:nil,language:"en")
        note.text = "Boiler"; note.modifiedAt = Date()
        _ = try ARNoteStore.upsertText(note,root:destination)
        note.audioFileName = "note-01.m4a"; note.audioDuration = 1
        let audio = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        _ = try VoiceNoteRecovery.publishRevision(note,audio:audio,to:destination,outbox:outbox)
        let replacement = audio+Data([1]); note.modifiedAt = Date()
        try VoiceNoteRecovery.stageRevision(note,audio:replacement,at:outbox)
        try VoiceNoteRecovery.recover(projectID:project,from:outbox,to:destination,references:[ref])
        var edit = note; edit.text = "Boiler valve"; edit.audioFileName = nil; edit.audioDuration = nil; edit.modifiedAt = Date()
        _ = try ARNoteStore.upsertText(edit,root:destination)
        let result = try ARNoteStore.read(root:destination,projectID:project)
        XCTAssertEqual(result.index.notes.count,1)
        XCTAssertEqual(result.index.notes.first?.text,"Boiler valve")
        XCTAssertEqual(result.audio[note.id],replacement)
        XCTAssertTrue(try ARNoteStore.index(root:outbox,projectID:project).notes.isEmpty)
    }
    func testLateAudioPreservesNewerTextAndOlderAudioCannotReplaceIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let ref = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        var note = ARNote(projectID:UUID(),reference:ref,number:1,level:0,roomID:nil,position:nil,planPosition:nil,language:"en")
        note.text = "Initial"; note.modifiedAt = Date(timeIntervalSince1970:100)
        _ = try ARNoteStore.upsertText(note,root:root)
        var later = note; later.text = "Edited while saving"; later.modifiedAt = Date(timeIntervalSince1970:300)
        _ = try ARNoteStore.upsertText(later,root:root)
        note.audioFileName = "note-01.m4a"; note.audioDuration = 1; note.audioModifiedAt = Date(timeIntervalSince1970:200)
        let audio = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        let saved = try ARNoteStore.upsertAudio(note,audio:audio,root:root)
        XCTAssertEqual(saved.text,later.text)
        note.audioModifiedAt = Date(timeIntervalSince1970:150)
        _ = try ARNoteStore.upsertAudio(note,audio:audio+Data([1]),root:root)
        XCTAssertEqual(try ARNoteStore.read(root:root,projectID:note.projectID).audio[note.id],audio)
    }
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
