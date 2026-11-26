import XCTest
@testable import RoomScanner

final class WrittenNoteTests:XCTestCase {
    func testDeletingWrittenPartPreservesCombinedAudioAndTranscript() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var note = makeNote(); note.text = "Check valve"; note.title = "Heating"
        note.audioFileName = note.stem+".m4a"; note.audioDuration = 1; note.transcript = "Separate transcript"
        let bytes = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        let saved = try ARNoteStore.upsertAudio(note,audio:bytes,root:root)
        _ = try ARNoteStore.removeWrittenText(saved,root:root)
        let library = try ARNoteStore.read(root:root,projectID:note.projectID)
        XCTAssertEqual(library.index.notes.count,1)
        let retained = try XCTUnwrap(library.index.notes.first)
        XCTAssertEqual(retained.text,""); XCTAssertNil(retained.title)
        XCTAssertEqual(retained.transcript,"Separate transcript")
        XCTAssertEqual(library.audio[note.id],bytes)
        XCTAssertEqual(retained.reference,note.reference); XCTAssertEqual(retained.position,note.position)
    }
    func testTextOnlyDeletionRejectsStaleEditorAndLeavesNoAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var note = makeNote(); note.text = "Original"; note.modifiedAt = Date(timeIntervalSince1970:1)
        let saved = try ARNoteStore.upsertText(note,root:root)
        var next = saved; next.text = "Updated"; next.modifiedAt = Date(timeIntervalSince1970:2)
        let changed = try ARNoteStore.upsertText(next,root:root,expected:saved)
        XCTAssertThrowsError(try ARNoteStore.removeWrittenText(saved,root:root))
        XCTAssertEqual(try ARNoteStore.index(root:root,projectID:note.projectID).notes.first?.text,"Updated")
        _ = try ARNoteStore.removeWrittenText(changed,root:root)
        XCTAssertTrue(try ARNoteStore.index(root:root,projectID:note.projectID).notes.isEmpty)
    }
    func testAudioReplacementFailureKeepsOldClipAndDurableRetry() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let destination = root.appendingPathComponent("library"),outbox = root.appendingPathComponent("outbox")
        var note = makeNote(); note.text = "Keep text"; note.modifiedAt = Date(timeIntervalSince1970:1)
        note.audioModifiedAt = Date(timeIntervalSince1970:1); note.audioFileName = note.stem+".m4a"; note.audioDuration = 1
        let old = Data([0,0,0,16])+Data("ftypM4A ".utf8),new = old+Data([1])
        let saved = try ARNoteStore.upsertAudio(note,audio:old,root:destination)
        var replacement = saved; replacement.audioModifiedAt = Date(timeIntervalSince1970:3)
        try VoiceNoteRecovery.stageRevision(replacement,audio:new,at:outbox)
        XCTAssertEqual(try ARNoteStore.read(root:destination,projectID:note.projectID).audio[note.id],old)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let blocked = root.appendingPathComponent("blocked"); try Data("not a directory".utf8).write(to:blocked)
        XCTAssertThrowsError(try VoiceNoteRecovery.publishRevision(replacement,audio:new,to:blocked,outbox:outbox))
        XCTAssertEqual(try ARNoteStore.read(root:outbox,projectID:note.projectID).audio[note.id],new)
        let latest = try VoiceNoteRecovery.publishRevision(replacement,audio:new,to:destination,outbox:outbox)
        XCTAssertEqual(latest.text,"Keep text")
        XCTAssertEqual(try ARNoteStore.read(root:destination,projectID:note.projectID).audio[note.id],new)
    }
    private func makeNote() -> ARNote {
        .init(projectID:UUID(),reference:.init(kind:.house,itemID:UUID(),library:"local"),number:1,level:-1,roomID:UUID(),position:nil,planPosition:nil,language:"de")
    }
}
