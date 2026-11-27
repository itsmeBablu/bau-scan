import XCTest
@testable import RoomScanner

final class ProjectStorageUsageTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("storage-usage-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSumsProjectSizesAndRealProjectMetrics() throws {
        let roomScan = SyntheticRooms.rectangularRoom().scan
        let roomPlan = FloorPlanBuilder().build(from: roomScan, name: "Small Room")
        let roomFolder = root.appendingPathComponent("Rooms/\(roomPlan.id.uuidString).roomscan", isDirectory: true)
        try RoomPackage(record: RoomRecord(plan: roomPlan), plan: roomPlan, scan: roomScan).write(to: roomFolder)

        let houseID = UUID()
        let secondRoom = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom(origin: .init(x: 5, y: 0, z: 0)).scan, name: "Office")
        var storyRoom = secondRoom
        storyRoom.story = 1
        let house = House(id: houseID, name: "Main House", stories: [
            Story(index: 0, rooms: [roomPlan]),
            Story(index: 1, rooms: [storyRoom])
        ])
        let houseFolder = root.appendingPathComponent("Houses/\(houseID.uuidString).housescan", isDirectory: true)
        try FileManager.default.createDirectory(at: houseFolder, withIntermediateDirectories: true)
        let houseBytes = try RoomPackage.encoder.encode(house)
        try houseBytes.write(to: houseFolder.appendingPathComponent("house.json"))
        let metaBytes = try RoomPackage.encoder.encode(HouseRecord(house: house))
        try metaBytes.write(to: houseFolder.appendingPathComponent("meta.json"))

        let designFile = SceneEditStore.url(root: root, source: .house, id: houseID)
        try FileManager.default.createDirectory(at: designFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 512).write(to: designFile)

        let techID = UUID()
        let techFolder = root.appendingPathComponent("TechnicalRooms/\(techID.uuidString).technicalroom", isDirectory: true)
        try FileManager.default.createDirectory(at: techFolder, withIntermediateDirectories: true)
        let acceptedItem = TechnicalMEPSuggestion(
            kind: .pipe, center: .init(x: 0, y: 0, z: 0), axis: .init(x: 0, y: 1, z: 0),
            length: 1, width: 0.1, height: 0.1, supportCount: 10, residualMetres: 0.002, status: .accepted
        )
        let proposedItem = TechnicalMEPSuggestion(
            kind: .roundDuct, center: .init(x: 1, y: 0, z: 0), axis: .init(x: 0, y: 1, z: 0),
            length: 1, width: 0.2, height: 0.2, supportCount: 8, residualMetres: 0.004, status: .proposed
        )
        let reviewData = try JSONEncoder().encode(TechnicalMEPReview(suggestions: [acceptedItem, proposedItem]))
        try reviewData.write(to: techFolder.appendingPathComponent("recognition.json"))

        let small = RenovationProject(name: "Small Room", references: [
            .init(kind: .room, itemID: roomPlan.id, library: "local")
        ])
        let big = RenovationProject(name: "Main House", references: [
            .init(kind: .house, itemID: houseID, library: "local"),
            .init(kind: .designHouse, itemID: houseID, library: "local"),
            .init(kind: .technicalRoom, itemID: techID, library: "local")
        ])
        let check = ProjectDistanceCheck(
            projectID: big.id, reference: .init(kind: .house, itemID: houseID, library: "local"),
            elementID: UUID(), label: "Wall", referenceMeters: 4, observedMeters: 4, method: "laser"
        )
        let exportFolder = root.appendingPathComponent("Projects/\(big.id.uuidString)/Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        try Data(repeating: 4, count: 256).write(to: exportFolder.appendingPathComponent("report.pdf"))

        let index = ProjectIndex(projects: [small, big], distanceChecks: [check])
        try ProjectIndexStore.write(index, root: root)

        let loaded = try ProjectStorageUsage.load(roots: ["local": root], catalogueRoot: root, locale: Locale(identifier: "en"))
        XCTAssertEqual(loaded.count, 2)
        let mainEntry = try XCTUnwrap(loaded.first { $0.id == big.id })
        XCTAssertEqual(mainEntry.layouts, 3)
        XCTAssertEqual(mainEntry.floors, 2)
        XCTAssertEqual(mainEntry.totalAreaM2, HouseMeasurements(house: house).floorArea, accuracy: 0.001)
        XCTAssertEqual(mainEntry.approvedCount, 1)
        XCTAssertEqual(mainEntry.acceptedCount, 1)
        XCTAssertEqual(mainEntry.bytes, Int64(houseBytes.count + metaBytes.count + 512 + reviewData.count + 256))
    }
}
