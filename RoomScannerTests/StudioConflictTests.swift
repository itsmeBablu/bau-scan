import XCTest
@testable import RoomScanner

final class StudioConflictTests: XCTestCase {
    func testDuplicatingSavedDesignStartsANewRevisionWithoutChangingOriginal() throws {
        for source in [SceneEditDocument.Source.room,.house,.technical] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at:root) }
            let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
            let document = SceneEditDocument(source:source,sourceID:room.id,title:"Original design",shell:House(room:room),objects:[])
            let original = SceneEditStore.url(root:root,source:source,id:room.id)
            let saved = try SceneEditStore.write(document,to:original)
            let bytes = try Data(contentsOf:original),newID = UUID()
            let duplicate = try SceneEditStore.duplicate(saved,sourceID:newID,root:root)
            let copyURL = SceneEditStore.url(root:root,source:source,id:newID)
            XCTAssertEqual(duplicate.sourceID,newID)
            XCTAssertEqual(duplicate.source,source)
            XCTAssertEqual(duplicate.revision,1)
            XCTAssertEqual(duplicate.shell,saved.shell)
            XCTAssertEqual(duplicate.objects,saved.objects)
            XCTAssertEqual(try SceneEditStore.read(copyURL,source:source,id:newID),duplicate)
            XCTAssertEqual(try Data(contentsOf:original),bytes)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:original.deletingLastPathComponent().path).count,2)
            XCTAssertThrowsError(try SceneEditStore.duplicate(saved,sourceID:saved.sourceID,root:root))
            var edited = duplicate; edited.title = "Independent copy"
            XCTAssertEqual(try SceneEditStore.write(edited,to:copyURL).revision,2)
            XCTAssertEqual(try Data(contentsOf:original),bytes)
        }
    }

    func testWrongDesignIdentityCannotOverwriteOrCreateAConflictCopy() throws {
        for matchingRevision in [true,false] {
            for differentSource in [true,false] {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                defer { try? FileManager.default.removeItem(at:root) }
                let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
                let document = SceneEditDocument(source:.room,sourceID:room.id,title:"Saved design",shell:House(room:room),objects:[])
                let file = SceneEditStore.url(root:root,source:.room,id:room.id)
                let saved = try SceneEditStore.write(document,to:file)
                let bytes = try Data(contentsOf:file)
                var wrong = saved; wrong.title = "Wrong destination"
                if differentSource { wrong.source = .house } else { wrong.sourceID = UUID() }
                if !matchingRevision { wrong.revision = 0; wrong.modifiedAt = nil }
                XCTAssertThrowsError(try SceneEditStore.write(wrong,to:file)) { error in
                    guard let failure = error as? SceneEditDocument.Failure,case .wrongSource = failure else {
                        XCTFail("Expected identity rejection, got \(error)"); return
                    }
                }
                XCTAssertEqual(try Data(contentsOf:file),bytes)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath:file.deletingLastPathComponent().path),[file.lastPathComponent])
                var retry = saved; retry.title = "Valid update"
                let updated = try SceneEditStore.write(retry,to:file)
                XCTAssertEqual(updated.revision,2)
                XCTAssertEqual(try SceneEditStore.read(file,source:.room,id:room.id)?.title,"Valid update")
            }
        }
    }

    func testLegacyReadsAndStaleWriterPreservesBothVersions() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let legacy = SceneEditDocument(source:.room,sourceID:room.id,title:"Legacy",shell:House(room:room),objects:[])
        let file = SceneEditStore.url(root:root,source:.room,id:room.id)
        let first = try SceneEditStore.write(legacy,to:file)
        XCTAssertEqual(first.revision,1)
        var mine = first,other = first; mine.title = "Mine"; other.title = "Other"
        _ = try SceneEditStore.write(other,to:file)
        do { try SceneEditStore.write(mine,to:file); XCTFail("Stale writer overwrote newer data") }
        catch let conflict as SceneEditStore.Conflict {
            let copy = try JSONDecoder().decode(SceneEditDocument.self,from:Data(contentsOf:conflict.copy))
            XCTAssertTrue(copy.title.hasPrefix("Mine")); XCTAssertNotEqual(copy.sourceID,mine.sourceID)
        }
        XCTAssertEqual(try SceneEditStore.read(file,source:.room,id:room.id)?.title,"Other")
        XCTAssertNil(try JSONDecoder().decode(SceneEditDocument.self,from:JSONEncoder().encode(legacy)).revision)
    }
}
