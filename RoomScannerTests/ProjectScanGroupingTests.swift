import XCTest
@testable import RoomScanner

final class ProjectScanGroupingTests: XCTestCase {
    func testNumericFloorOrderingAndLegacyUnassigned() {
        let levels: [Int?] = [10, -2, 0, 2, nil]
        let entries = levels.map { _ in entry() }
        let metadata = Dictionary(uniqueKeysWithValues: zip(entries, levels).compactMap { entry, level -> (String, ScanOrganization)? in
            guard let level else { return nil }
            return (entry.id, .init(level: level, buildingName: "A", kind: .house))
        })
        let groups = ProjectScanGrouping.buildings(entries: entries, organization: metadata, locale: Locale(identifier: "de"))
        XCTAssertEqual(groups.map(\.id.name), ["A", nil])
        XCTAssertEqual(groups[0].levels.compactMap(\.id.number), [-2, 0, 2, 10])
        XCTAssertEqual(groups[1].levels.count, 1)
        XCTAssertNil(groups[1].levels[0].id.number)
        XCTAssertEqual(groups.flatMap(\.levels).flatMap(\.scans).count, entries.count)
    }
    func testNamedFloorsAndScanNumbersKeepIndependentReferences() {
        let a = entry(), b = entry(), c = entry(), d = entry()
        let metadata: [String: ScanOrganization] = [
            a.id: .init(level: 0, buildingName: "A", number: 10, kind: .house),
            b.id: .init(level: 0, buildingName: "A", number: 2, kind: .house),
            c.id: .init(otherLevelName: "Roof", buildingName: "A", number: 1, kind: .house),
            d.id: .init(buildingName: "A", kind: .house)
        ]
        let first = ProjectScanGrouping.buildings(entries: [a, c, d, b], organization: metadata, locale: Locale(identifier: "en"))
        XCTAssertEqual(first[0].levels[0].scans.map(\.id), [b.id, a.id])
        XCTAssertEqual(first[0].levels[1].id.otherName, "Roof")
        XCTAssertNil(first[0].levels[2].id.otherName)
        let reversed = ProjectScanGrouping.buildings(entries: [b, d, c, a], organization: metadata, locale: Locale(identifier: "en"))
        XCTAssertEqual(first.flatMap(\.levels).flatMap(\.scans).map(\.reference), reversed.flatMap(\.levels).flatMap(\.scans).map(\.reference))
    }
    private func entry() -> ProjectLibraryEntry {
        .init(reference: .init(kind: .house, itemID: UUID(), library: "local"), title: "House", date: Date(timeIntervalSince1970: 1), area: nil, roomCount: 1,
              root: URL(fileURLWithPath: "/tmp"), url: URL(fileURLWithPath: "/tmp/example.housescan"))
    }
}
