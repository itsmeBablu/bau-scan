import Foundation

/// Derived overview only; not a scan/package schema or a claim of building area.
struct ProjectScanSummary: Equatable {
    let floorArea: Double
    let wallAreaGross: Double
    let wallAreaNet: Double
    let rooms: Int
    let stories: Int

    init(house: House) {
        let measures = HouseMeasurements(house: house)
        let quantities = house.allRooms.map(RenovationQuantities.init)
        floorArea = measures.floorArea; rooms = measures.roomCount; stories = measures.storyCount
        wallAreaGross = quantities.reduce(0) { $0 + $1.wallAreaGross }
        wallAreaNet = quantities.reduce(0) { $0 + $1.wallAreaNet }
    }
}
