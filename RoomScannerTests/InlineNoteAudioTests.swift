import XCTest
@testable import RoomScanner

final class InlineNoteAudioTests: XCTestCase {
    func testSingleClipReadDoesNotLoadOrValidateUnrelatedClipBytes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = UUID(), reference = ProjectReference(kind: .house, itemID: UUID(), library: "local")
        let bytes = Data([0,0,0,16]) + Data("ftypM4A ".utf8)
        func note() -> ARNote {
            var value = ARNote(projectID: project, reference: reference, number: 1, level: nil, roomID: nil, position: nil, planPosition: nil, language: "en")
            value.audioDuration = 1; value.audioFileName = value.stem + ".m4a"; value.audioModifiedAt = Date()
            return value
        }
        let first = try ARNoteStore.upsertAudio(note(), audio: bytes, root: root)
        let second = try ARNoteStore.upsertAudio(note(), audio: bytes, root: root)
        let directory = ARNoteStore.url(root: root, projectID: project)
        let badPath = try XCTUnwrap(second.audioPath)
        try Data("invalid audio".utf8).write(to: directory.appendingPathComponent(badPath), options: .atomic)
        XCTAssertThrowsError(try ARNoteStore.read(root: root, projectID: project))
        XCTAssertEqual(try ARNoteStore.audio(for: first, root: root), bytes)
        XCTAssertThrowsError(try ARNoteStore.audio(for: second, root: root))
    }
    func testStaleAudioRevisionAndForeignReferenceAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = UUID(), reference = ProjectReference(kind: .house, itemID: UUID(), library: "local")
        let bytes = Data([0,0,0,16]) + Data("ftypM4A ".utf8)
        var note = ARNote(projectID: project, reference: reference, number: 1, level: nil, roomID: nil, position: nil, planPosition: nil, language: "en")
        note.audioDuration = 1; note.audioFileName = note.stem + ".m4a"; note.audioModifiedAt = Date(timeIntervalSince1970: 10)
        let original = try ARNoteStore.upsertAudio(note, audio: bytes, root: root)
        var newer = original; newer.audioModifiedAt = Date(timeIntervalSince1970: 20)
        let saved = try ARNoteStore.upsertAudio(newer, audio: bytes, root: root)
        XCTAssertThrowsError(try ARNoteStore.audio(for: original, root: root))
        XCTAssertEqual(try ARNoteStore.audio(for: saved, root: root), bytes)
        var foreign = saved; foreign.reference.library = "icloud"
        XCTAssertThrowsError(try ARNoteStore.audio(for: foreign, root: root))
    }
}
