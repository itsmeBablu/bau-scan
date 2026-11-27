import XCTest
@testable import RoomScanner

final class SceneEditCatalogueTests: XCTestCase {
    func testRootPrecedenceDoesNotMergeDifferentSourceKindsWithTheSameUUID() throws {
        let local = StorageLocation.temporary(), cloud = StorageLocation.temporary()
        defer {
            try? FileManager.default.removeItem(at: local.documentsURL)
            try? FileManager.default.removeItem(at: cloud.documentsURL)
        }
        let plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Room")
        let id = plan.id, house = House(room: plan)
        for (root, source, title) in [(local.documentsURL, SceneEditDocument.Source.room, "Local room"),
                                      (local.documentsURL, .house, "Local house"),
                                      (cloud.documentsURL, .house, "Cloud house")] {
            let document = SceneEditDocument.seed(house: house, source: source, id: id)
            var named = document; named.title = title
            _ = try SceneEditStore.write(named, to: SceneEditStore.url(root: root, source: source, id: id))
        }
        let entries = try SceneEditCatalogue.load(roots: [cloud.documentsURL, local.documentsURL])
        XCTAssertEqual(entries.count, 2)
        let room = try XCTUnwrap(entries.first { $0.document.source == .room })
        let wholeHome = try XCTUnwrap(entries.first { $0.document.source == .house })
        XCTAssertNotEqual(room.id, wholeHome.id)
        XCTAssertEqual(room.root, local.documentsURL)
        XCTAssertEqual(wholeHome.root, cloud.documentsURL)
        XCTAssertEqual(wholeHome.document.title, "Cloud house")
        XCTAssertEqual(try SceneEditCatalogue.load(roots: [local.documentsURL, cloud.documentsURL])
            .first { $0.document.source == .house }?.document.title, "Local house")
    }

    func testCancellationDoesNotPublishAnEmptyCatalogueAndCorruptionIsNotHidden() async throws {
        let root = StorageLocation.temporary().documentsURL
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("SceneEdits")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("invalid json".utf8).write(to: directory.appendingPathComponent("room-\(UUID().uuidString).json"))
        XCTAssertThrowsError(try SceneEditCatalogue.load(roots: [root]))
        let job = Task<Void, Never> {
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try SceneEditCatalogue.load(roots: [root]); XCTFail("Cancelled catalogue load returned success") }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        await job.value
    }
}
