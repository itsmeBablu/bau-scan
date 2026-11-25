import XCTest
@testable import RoomScanner

private actor DelayedCloudLocation {
    var continuation: CheckedContinuation<StorageLocation?,Never>?
    func resolve(started: XCTestExpectation) async -> StorageLocation? {
        await withCheckedContinuation { continuation = $0; started.fulfill() }
    }
    func finish(_ location: StorageLocation) { continuation?.resume(returning:location); continuation = nil }
}
final class CloudToggleRaceTests: XCTestCase {
    @MainActor func testDisableIgnoresInFlightEnable() async {
        let defaults = UserDefaults.standard,key = CloudAvailability.preferenceKey,previous = UserDefaults.standard.object(forKey:CloudAvailability.preferenceKey)
        defer { if let previous { defaults.set(previous,forKey:key) } else { defaults.removeObject(forKey:key) } }
        for initiallyEnabled in [true,false] {
        if initiallyEnabled { defaults.set(true,forKey:key) } else { defaults.removeObject(forKey:key) }
        let local = StorageLocation.temporary(),delayed = DelayedCloudLocation(),store = RoomStore(location:StorageLocation.temporary())
        let original = store.location.documentsURL,started = expectation(description:"Resolving")
        let task = Task { await store.activateCloudIfAvailable(resolver:{ await delayed.resolve(started:started) }) }
        await fulfillment(of:[started],timeout:2)
        await store.setCloudEnabled(false)
        await delayed.finish(StorageLocation(kind:.iCloud,documentsURL:local.documentsURL))
        await task.value
        XCTAssertFalse(store.isCloud); XCTAssertEqual(store.location.documentsURL,original)
        XCTAssertFalse(store.isResolvingCloud)
        XCTAssertFalse(defaults.bool(forKey:key))
        }
    }
}
