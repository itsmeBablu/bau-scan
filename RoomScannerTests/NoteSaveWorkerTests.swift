import XCTest
@testable import RoomScanner

final class NoteSaveWorkerTests:XCTestCase {
    func testNewSaveDoesNotAttemptUnrelatedConflictingOutboxRevision() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library = root.appendingPathComponent("library"), outbox = root.appendingPathComponent("outbox")
        var old = note(); old.audioFileName = old.stem+".m4a"; old.audioDuration = 1; old.audioModifiedAt = Date(timeIntervalSince1970:2)
        try VoiceNoteRecovery.stageRevision(old,audio:audio,at:outbox)
        var newer = old; newer.audioModifiedAt = Date(timeIntervalSince1970:3)
        _ = try ARNoteStore.upsertAudio(newer,audio:audio+Data([1]),root:library)
        var added = old; added.id = UUID(); added.audioModifiedAt = Date(timeIntervalSince1970:4)
        let saved = try await NoteSaveWorker.newRecording(added,audio:audio,root:library,outbox:outbox)
        XCTAssertEqual(saved.id,added.id)
        XCTAssertEqual(try ARNoteStore.audio(for:saved,root:library),audio)
        XCTAssertEqual(try ARNoteStore.index(root:outbox,projectID:old.projectID).notes.map(\.id),[old.id])
        XCTAssertEqual(try ARNoteStore.read(root:outbox,projectID:old.projectID).audio[old.id],audio)
    }
    func testNewRecordingFailureRetainsOutboxAndRetryReturnsDurableAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let blocked = root.appendingPathComponent("blocked"),outbox = root.appendingPathComponent("outbox"),library = root.appendingPathComponent("library")
        try Data("not a directory".utf8).write(to:blocked)
        var value = note(); value.audioFileName = value.stem+".m4a"; value.audioDuration = 1
        do { _ = try await NoteSaveWorker.newRecording(value,audio:audio,root:blocked,outbox:outbox); XCTFail("Expected write failure") }
        catch { XCTAssertFalse(error is CancellationError) }
        XCTAssertEqual(try ARNoteStore.read(root:outbox,projectID:value.projectID).audio[value.id],audio)
        let saved = try await NoteSaveWorker.newRecording(value,audio:audio,root:library,outbox:outbox)
        XCTAssertEqual(saved.id,value.id)
        XCTAssertEqual(try ARNoteStore.audio(for:saved,root:library),audio)
        XCTAssertTrue(try ARNoteStore.index(root:outbox,projectID:value.projectID).notes.isEmpty)
    }
    private let audio = Data([0,0,0,16])+Data("ftypM4A ".utf8)
    private func note() -> ARNote {
        var value = ARNote(projectID:UUID(),reference:.init(kind:.house,itemID:UUID(),library:"local"),number:1,
                           level:0,roomID:nil,position:nil,planPosition:nil,language:"en")
        value.createdAt = Date(timeIntervalSince1970:1)
        return value
    }

    func testTextSaveReturnsReloadedDiskValueAndPreservesCombinedAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        var initial = note(); initial.audioFileName = initial.stem+".m4a"; initial.audioDuration = 1
        initial.audioModifiedAt = initial.createdAt
        let saved = try ARNoteStore.upsertAudio(initial,audio:audio,root:root)
        var edited = saved; edited.text = "Verify valve"; edited.modifiedAt = Date(timeIntervalSince1970:2)
        let result = try await NoteSaveWorker.text(edited,expected:saved,root:root)
        XCTAssertEqual(try ARNoteStore.index(root:root,projectID:result.projectID).notes.first,result)
        XCTAssertEqual(result.text,edited.text)
        XCTAssertEqual(try ARNoteStore.audio(for:result,root:root),audio)
        do { _ = try await NoteSaveWorker.text(edited,expected:initial,root:root); XCTFail("Stale draft saved") }
        catch ARNoteStore.TextConflict.stale {} catch { throw error }
    }

    func testAudioSaveReturnsCurrentDiskRecordWithoutOverwritingNewerText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library = root.appendingPathComponent("library"), outbox = root.appendingPathComponent("outbox")
        let initial = note()
        var text = initial; text.text = "Newer engineering note"; text.modifiedAt = Date(timeIntervalSince1970:5)
        _ = try ARNoteStore.upsertText(text,root:library)
        var revision = initial; revision.audioFileName = revision.stem+".m4a"; revision.audioDuration = 1
        revision.audioModifiedAt = Date(timeIntervalSince1970:6)
        let result = try await NoteSaveWorker.audioRevision(revision,audio:audio,root:library,outbox:outbox)
        XCTAssertEqual(result.text,text.text)
        XCTAssertEqual(try ARNoteStore.audio(for:result,root:library),audio)
        XCTAssertTrue(try ARNoteStore.index(root:outbox,projectID:initial.projectID).notes.isEmpty)
    }

    func testSupersededRecordingIsNotReportedAsTheRequestedSave() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let library = root.appendingPathComponent("library"), outbox = root.appendingPathComponent("outbox")
        var newest = note(); newest.audioFileName = newest.stem+".m4a"; newest.audioDuration = 1
        newest.audioModifiedAt = Date(timeIntervalSince1970:10)
        let saved = try ARNoteStore.upsertAudio(newest,audio:audio+Data([1]),root:library)
        var older = newest; older.audioModifiedAt = Date(timeIntervalSince1970:5)
        do { _ = try await NoteSaveWorker.audioRevision(older,audio:audio,root:library,outbox:outbox); XCTFail("Older recording reported saved") }
        catch NoteSaveWorker.Failure.supersededAudio {} catch { throw error }
        XCTAssertEqual(try ARNoteStore.audio(for:saved,root:library),audio+Data([1]))
        XCTAssertEqual(try ARNoteStore.read(root:outbox,projectID:older.projectID).audio[older.id],audio,
                       "The unapplied revision must remain available for explicit recovery")
    }
}
