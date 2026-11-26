import XCTest
@testable import RoomScanner

final class NoteTransactionRaceTests:XCTestCase {
    private let audio = Data([0,0,0,16])+Data("ftypM4A ".utf8)
    private func note() -> ARNote {
        var value = ARNote(projectID:UUID(),reference:.init(kind:.house,itemID:UUID(),library:"local"),number:1,
                           level:0,roomID:nil,position:nil,planPosition:nil,language:"en")
        value.createdAt = Date(timeIntervalSince1970:1)
        value.modifiedAt = value.createdAt
        return value
    }

    func testConcurrentTextAndAudioKeepBothLatestFieldsAndReloadedClip() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let original = note()
        let saved = try ARNoteStore.upsertText(original,root:root)
        var edited = saved; edited.text = "Insulation needs repair"; edited.modifiedAt = Date(timeIntervalSince1970:20)
        var recorded = saved; recorded.audioModifiedAt = Date(timeIntervalSince1970:10)
        recorded.audioFileName = recorded.stem+".m4a"; recorded.audioDuration = 1
        let text = edited, recording = recorded, bytes = audio
        try await withThrowingTaskGroup(of:Void.self) { group in
            group.addTask { _ = try ARNoteStore.upsertText(text,root:root,expected:saved) }
            group.addTask { _ = try ARNoteStore.upsertAudio(recording,audio:bytes,root:root) }
            try await group.waitForAll()
        }
        let current = try XCTUnwrap(ARNoteStore.index(root:root,projectID:original.projectID).notes.first)
        XCTAssertEqual(current.text,text.text)
        XCTAssertEqual(current.modifiedAt,text.modifiedAt)
        XCTAssertEqual(current.audioModifiedAt,recording.audioModifiedAt)
        XCTAssertEqual(try ARNoteStore.audio(for:current,root:root),audio)
    }

    func testTwoEditorsWithSameBaselineCannotSilentlyReplaceEachOther() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let original = note(), saved = try ARNoteStore.upsertText(original,root:root)
        let outcomes = try await withThrowingTaskGroup(of:Bool.self) { group in
            for text in ["Inspect pump","Inspect boiler"] {
                group.addTask {
                    var edited = saved; edited.text = text; edited.modifiedAt = Date(timeIntervalSince1970:10)
                    do { _ = try ARNoteStore.upsertText(edited,root:root,expected:saved); return true }
                    catch ARNoteStore.TextConflict.stale { return false }
                }
            }
            var results:[Bool] = []
            for try await result in group { results.append(result) }
            return results
        }
        XCTAssertEqual(outcomes.filter { $0 }.count,1)
        XCTAssertEqual(outcomes.filter { !$0 }.count,1)
        let current = try XCTUnwrap(ARNoteStore.index(root:root,projectID:original.projectID).notes.first)
        XCTAssertTrue(["Inspect pump","Inspect boiler"].contains(current.text))
        XCTAssertEqual(current.id,original.id)
    }
}
