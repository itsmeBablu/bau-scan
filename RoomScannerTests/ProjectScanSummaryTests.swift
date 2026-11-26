import XCTest
@testable import RoomScanner

final class ProjectScanSummaryTests: XCTestCase {
    func testSummaryUsesHouseUnionAndNetRoomFaceQuantities() throws {
        let house = try HouseBuilder().build(from: SyntheticRooms.twoRoomApartment(), name: "A")
        let summary = ProjectScanSummary(house: house)
        XCTAssertEqual(summary.floorArea, HouseMeasurements(house: house).floorArea, accuracy: 0.000001)
        XCTAssertEqual(summary.rooms, house.allRooms.count)
        XCTAssertEqual(summary.stories, house.stories.count)
        XCTAssertEqual(summary.wallAreaGross, house.allRooms.map(RenovationQuantities.init).reduce(0) { $0 + $1.wallAreaGross }, accuracy: 0.000001)
        XCTAssertLessThanOrEqual(summary.wallAreaNet, summary.wallAreaGross)
    }

    func testCacheInvalidatesChangedPlanAndNeverReturnsStaleUnavailableSummary() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"A")
        let package = RoomPackage(record: RoomRecord(plan: plan), plan: plan, scan: nil, capturedRoomData: nil,
                                  usdzData: nil, usdzMeshData: nil, thumbnailPNG: nil)
        let url = root.appendingPathComponent(plan.id.uuidString + ".roomscan")
        try package.write(to: url)
        let reference = ProjectReference(kind: .room, itemID: plan.id, library: "local")
        let entry = ProjectLibraryEntry(reference: reference, title: "A", date: Date(), area: nil, roomCount: 1, root: root, url: url)
        let cache = ProjectScanSummaryCache()
        let first = try await cache.summaries(for: [entry])
        XCTAssertEqual(first[entry.id], ProjectScanSummary(house: House(room: plan)))
        let repeated = try await cache.summaries(for: [entry])
        XCTAssertEqual(first, repeated)
        // Geometry changes with unchanged scan UUID must invalidate the derived overview.
        var changed = package
        changed.plan.floorPolygon = [.init(x: 0, y: 0), .init(x: 8, y: 0), .init(x: 8, y: 5), .init(x: 0, y: 5)]
        try changed.write(to: url)
        let next = try await cache.summaries(for: [entry])
        XCTAssertEqual(next[entry.id]?.floorArea, 40)
        let planURL = url.appendingPathComponent("plan.json")
        try Data("corrupt".utf8).write(to: planURL, options: .atomic)
        let unavailable = try await cache.summaries(for: [entry])
        XCTAssertNil(unavailable[entry.id])
        let design = ProjectLibraryEntry(reference: .init(kind: .designRoom, itemID: plan.id, library: "local"), title: "Copy", date: Date(), area: 40, roomCount: 1, root: root, url: url)
        let designs = try await cache.summaries(for: [design])
        XCTAssertTrue(designs.isEmpty, "Studio copies must not contribute to scan totals")
    }
}
