import XCTest
import SceneKit
@testable import RoomScanner

final class CoreLifecycleTests: XCTestCase {
    @MainActor func testInactivePlaybackDoesNotCreateAGlobalStrongOwner() {
        weak var reference: NotePlayback?
        autoreleasepool {
            let playback = NotePlayback()
            reference = playback
            playback.stop()
        }
        XCTAssertNil(reference)
    }

    @MainActor func testStudioControllerDoesNotRetainItsDetachedView() {
        weak var controllerReference: StudioSceneController?
        weak var viewReference: SCNView?
        autoreleasepool {
            let controller = StudioSceneController()
            var view: SCNView? = SCNView()
            controllerReference = controller; viewReference = view
            controller.view = view
            view = nil
            XCTAssertNil(viewReference,"Controller's view link must remain weak")
        }
        XCTAssertNil(controllerReference)
    }
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

    #if os(iOS)
    @MainActor func testCompletionIsIdempotentAndUnresolvedRecoveryCannotBecomeSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let complete = CapturePersistence(kind:.house,projectID:nil,root:root)
        try await complete.prepare()
        await complete.complete(); await complete.complete()
        XCTAssertNil(complete.failure)
        let store = try XCTUnwrap(complete.store)
        let done = try await store.read(complete.id)
        XCTAssertEqual(done.state,.completed)
        let pending = CapturePersistence(kind:.technical,projectID:nil,root:root)
        try await pending.prepare()
        let manifest = root.appendingPathComponent(pending.id.uuidString+"/session.json")
        let backup = PackageReplacement.backup(for:manifest)
        try FileManager.default.copyItem(at:manifest,to:backup)
        let original = try Data(contentsOf:backup)
        await pending.complete()
        XCTAssertNotNil(pending.failure)
        XCTAssertEqual(try Data(contentsOf:backup),original)
        let pendingStore = try XCTUnwrap(pending.store)
        let unchanged = try await pendingStore.read(pending.id)
        XCTAssertEqual(unchanged.state,.scanning,"A failed finalizing write must not advance the checkpoint")
    }

    @MainActor func testInactiveRecorderNotificationObserversDoNotRetainRecorder() {
        weak var reference: NoteAudioRecorder?
        autoreleasepool {
            let recorder = NoteAudioRecorder()
            reference = recorder
            // Do not call start: this test must not request microphone permission
            // or change an audio session in simulator/CI.
            XCTAssertFalse(recorder.recording)
            XCTAssertFalse(recorder.preparing)
        }
        XCTAssertNil(reference,"Notification subscriptions must not retain the recorder")
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
    #endif

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
