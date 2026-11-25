import XCTest
@testable import RoomScanner

final class LevelExportTests: XCTestCase {
    func testLevelsUseScanFloorHeightsAndDoNotInventMissingElevations() throws {
        let structure = SyntheticRooms.twoStoryHouse()
        let house = try HouseBuilder().build(from:structure,name:"Building")
        let heights = LevelExportService.elevations(house:house,scans:structure.rooms)
        XCTAssertEqual(heights[0] ?? -999,0.02,accuracy:0.001)
        XCTAssertEqual(heights[1] ?? -999,2.7,accuracy:0.001)
        XCTAssertTrue(LevelExportService.elevations(house:house,scans:[]).isEmpty)
        XCTAssertTrue(LevelExportService.needsArchive(house:house,format:.dxf))
        XCTAssertFalse(LevelExportService.needsArchive(house:house,format:.pdf))
        let subject = ExportSubject(record:HouseRecord(house:house),house:house,packageURL:nil)
        XCTAssertTrue(ExportService.fileName(for:subject,format:.obj).hasSuffix("-obj-levels.zip"))
    }
}
