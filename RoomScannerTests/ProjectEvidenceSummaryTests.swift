import XCTest
@testable import RoomScanner

final class ProjectEvidenceSummaryTests: XCTestCase {
    func testLocalAndCloudPhotoTwinsKeepTheirIndependentSourceIdentities() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let roomID = UUID(), photo = SurveyPhoto(id:UUID(),roomID:nil,number:1,pose:SyntheticWorkload.pose,timestamp:1)
        var entries:[ProjectLibraryEntry] = []
        for library in ["local","icloud"] {
            let package = root.appendingPathComponent(library+"/\(roomID.uuidString).roomscan")
            let image = package.appendingPathComponent(photo.jpegPath)
            try FileManager.default.createDirectory(at:image.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data([0xff,0xd8]).write(to:image)
            try RoomPackage.encoder.encode([photo]).write(to:package.appendingPathComponent("survey-photos.json"))
            entries.append(.init(reference:.init(kind:.room,itemID:roomID,library:library),title:library,date:Date(),area:nil,roomCount:1,root:root,url:package))
        }
        let summary = try await ProjectEvidenceSummaryCache().summary(projectID:UUID(),entries:entries,notesRoot:root,summaries:[:])
        XCTAssertEqual(summary.photoCount,2)
        XCTAssertEqual(Set(summary.photos.map(\.reference.library)),["local","icloud"])
        XCTAssertEqual(Set(summary.photos.map(\.id)).count,2)
        XCTAssertEqual(Set(summary.photos.map(\.photo.id)).count,1,"Raw photo UUID stays unchanged")
    }
    func testMetadataCacheInvalidatesNotesWithoutReadingAudio() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let project = UUID(),reference = ProjectReference(kind:.house,itemID:UUID(),library:"local")
        let package = root.appendingPathComponent("source.housescan")
        try FileManager.default.createDirectory(at:package,withIntermediateDirectories:true)
        let entry = ProjectLibraryEntry(reference:reference,title:"A",date:Date(),area:nil,roomCount:1,root:root,url:package)
        let bytes = Data([0,0,0,16])+Data("ftypM4A ".utf8)
        var value = ARNote(projectID:project,reference:reference,number:1,level:nil,roomID:nil,position:nil,planPosition:nil,language:"en")
        value.audioFileName = value.stem+".m4a"; value.audioDuration = 1; value.audioModifiedAt = Date()
        let saved = try ARNoteStore.upsertAudio(value,audio:bytes,root:root)
        let cache = ProjectEvidenceSummaryCache()
        let first = try await cache.summary(projectID:project,entries:[entry],notesRoot:root,summaries:[:])
        XCTAssertEqual(first.voiceCount,1); XCTAssertEqual(first.writtenCount,0)
        var edited = saved; edited.text = "Check the expansion vessel"; edited.modifiedAt = Date().addingTimeInterval(1)
        _ = try ARNoteStore.upsertText(edited,root:root,expected:saved)
        let next = try await cache.summary(projectID:project,entries:[entry],notesRoot:root,summaries:[:])
        XCTAssertEqual(next.writtenCount,1); XCTAssertEqual(next.voices.first?.text,edited.text)
        // Metadata preview remains available when clip bytes are corrupt/unavailable.
        let path = try XCTUnwrap(saved.audioPath)
        try Data("broken clip".utf8).write(to:ARNoteStore.url(root:root,projectID:project).appendingPathComponent(path),options:.atomic)
        let preview = try await cache.summary(projectID:project,entries:[entry],notesRoot:root,summaries:[:])
        XCTAssertEqual(preview.voiceCount,1)
        XCTAssertThrowsError(try ARNoteStore.audio(for:saved,root:root))
    }
}
