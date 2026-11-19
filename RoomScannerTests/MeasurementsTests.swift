import XCTest
@testable import RoomScanner

final class MeasurementsTests: XCTestCase {
    let builder = FloorPlanBuilder()

    func testRoomMeasurements() {
        let (scan, _, _) = SyntheticRooms.rectangularRoom()
        let m = RoomMeasurements(plan: builder.build(from: scan, name: "Salon"))
        XCTAssertEqual(m.floorArea, 12, accuracy: 0.001)
        XCTAssertEqual(m.perimeter, 14, accuracy: 0.001)
        XCTAssertEqual(m.ceilingHeight.lowerBound, 2.5, accuracy: 0.001)
        XCTAssertEqual(m.walls.count, 4)
        XCTAssertEqual(m.doors.count, 1)
        XCTAssertEqual(m.windows.count, 1)
        XCTAssertEqual(m.windows[0].sillHeight, 1.0, accuracy: 0.001)
        XCTAssertEqual(m.objects.first?.category, "table")
    }

    func testHouseMeasurementsSumRooms() {
        let a = builder.build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        let b = builder.build(from: SyntheticRooms.lShapedRoom(), name: "Chambre")
        let house = House(name: "Maison", stories: [Story(index: 0, rooms: [a]), Story(index: 1, rooms: [b])])
        let m = HouseMeasurements(house: house)
        XCTAssertEqual(m.floorArea, 36, accuracy: 0.001)
        XCTAssertEqual(m.roomCount, 2)
        XCTAssertEqual(m.storyCount, 2)
    }

    func testFormattingFrench() {
        let fr = Locale(identifier: "fr_FR")
        XCTAssertEqual(MeasurementFormat.centimeters(4.004, locale: fr), "400 cm")
        XCTAssertTrue(MeasurementFormat.millimeters(4.004, locale: fr).contains("4") && MeasurementFormat.millimeters(4.004, locale: fr).contains("mm"))
        XCTAssertEqual(MeasurementFormat.squareMeters(12.04, locale: fr), "12,0 m²")
        XCTAssertEqual(MeasurementFormat.meters(2.5, locale: fr), "2,50 m")
        XCTAssertEqual(MeasurementFormat.length(2.5, unit: .meters, locale: fr), "2,50 m")
    }

    func testFormattingEnglish() {
        let en = Locale(identifier: "en_US")
        XCTAssertEqual(MeasurementFormat.centimeters(1.2, locale: en), "120 cm")
        XCTAssertEqual(MeasurementFormat.millimeters(1.2, locale: en), "1200 mm")
        XCTAssertEqual(MeasurementFormat.meters(1.2, locale: en), "1.20 m")
        XCTAssertEqual(MeasurementFormat.length(1.2, unit: .both, locale: en), "1200 mm (1.20 m)")
        XCTAssertEqual(MeasurementFormat.squareMeters(29.94, locale: en), "29.9 m²")
        XCTAssertEqual(MeasurementFormat.openingWidth(0.9, unit: .meters, locale: en), "0.90 m")
        XCTAssertEqual(MeasurementFormat.openingHeight(2.1, unit: .meters, locale: en), "2.10 m")
        XCTAssertEqual(MeasurementFormat.parapetHeight(0.9, unit: .meters, locale: en), "BRH: 0.90 m")
        XCTAssertEqual(MeasurementFormat.parapetHeight(0.9, unit: .millimeters, locale: en), "BRH: 900 mm")
    }

    func testBoundsIncludeObjectCorners() {
        var plan = FloorPlanBuilder().build(from: SyntheticRooms.rectangularRoom().scan, name: "Salon")
        // Table 1.2 x 0.8 placed across east wall (x = 2): corners extend beyond wall bounds.
        plan.objects[0].center = Point2D(x: 2.0, y: 0); plan.objects[0].angle = 0
        XCTAssertEqual(plan.bounds.maxX, 2.6, accuracy: 1e-4)
        XCTAssertEqual(plan.bounds.minX, -2.0, accuracy: 1e-4)
    }
}
