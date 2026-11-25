import XCTest
@testable import RoomScanner

final class RenovationQuantitiesTests: XCTestCase {
    func testDuplicateOpeningsSubtractOnceAndDoNotChangeNetRoomDimensions() {
        var room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"Room")
        let original = RoomMeasurements(plan:room), wall = room.walls[0]
        let opening = Opening(id:UUID(),kind:.window,wallID:wall.id,center:wall.segment.midpoint,width:1,height:1,sillHeight:1,angle:0,confidence:.high)
        var duplicate = opening; duplicate.id = UUID(); room.openings = [opening,duplicate]
        let q = RenovationQuantities(room)
        XCTAssertEqual(q.wallAreaGross-q.wallAreaNet,1,accuracy:0.000001)
        XCTAssertEqual(q.floorArea,original.floorArea)
        XCTAssertEqual(q.perimeter,original.perimeter)
        XCTAssertEqual(q.flooring(wastePercent:10),q.floorArea*1.1,accuracy:0.000001)
        XCTAssertEqual(q.volumeMin,q.floorArea*room.ceilingHeight.lowerBound,accuracy:0.000001)
    }
    func testCSVProtectsFormulaLikeNamesAndUsesGermanDecimalComma() {
        let room = FloorPlanBuilder().build(from:SyntheticRooms.rectangularRoom().scan,name:"=SUM(A1)")
        let report = ProjectReport(name:"Test",generatedAt:Date(),notes:"",scans:[.init(title:"Scan",house:House(room:room),detailLines:[])],photos:[],unresolved:[])
        let text = String(decoding:ProjectQuantitiesCSV.data(report,locale:Locale(identifier:"de_DE")),as:UTF8.self)
        XCTAssertTrue(text.contains("'=SUM(A1)")); XCTAssertTrue(text.contains(",000"))
    }
}
