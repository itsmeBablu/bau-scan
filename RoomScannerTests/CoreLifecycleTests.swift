import XCTest
@testable import RoomScanner

final class CoreLifecycleTests: XCTestCase {
    @MainActor func testLibraryStoresReleaseAfterMetadataReload() throws {
        let location = StorageLocation.temporary()
        defer { try? FileManager.default.removeItem(at: location.documentsURL) }
        try location.prepare()
        weak var roomReference: RoomStore?
        weak var technicalReference: TechnicalRoomLibraryStore?
        autoreleasepool {
            let store = RoomStore(location: location, allowsCloud: false)
            roomReference = store
            store.reload()
            XCTAssertNil(store.lastError)
        }
        try autoreleasepool {
            let store = TechnicalRoomLibraryStore(root: location.documentsURL.appendingPathComponent("TechnicalRooms"))
            technicalReference = store
            try store.reload()
        }
        XCTAssertNil(roomReference)
        XCTAssertNil(technicalReference)
    }

    @MainActor func testCapturePersistenceReleasesAfterCheckpointWorkCompletes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var persistence: CapturePersistence? = CapturePersistence(kind: .technical, projectID: nil, root: root)
        weak var reference = persistence
        try await persistence?.write(["fixture": "checkpoint"], key: "state")
        XCTAssertNotNil(persistence?.savedAt)
        persistence = nil
        XCTAssertNil(reference, "Completed checkpoint work must not retain its UI owner")
    }

    func testSessionActorReleasesAfterDurableWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var store: ScanSessionStore? = ScanSessionStore(root: root)
        weak var reference = store
        let session = try await XCTUnwrap(store).create(kind: .technical, projectID: nil)
        _ = try await store?.write(session.id, key: "fixture", data: Data("checkpoint".utf8))
        store = nil
        XCTAssertNil(reference)
        let reopened = ScanSessionStore(root: root)
        let saved = try await reopened.latest(session.id, key: "fixture")
        XCTAssertEqual(saved, Data("checkpoint".utf8))
    }
}
