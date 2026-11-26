import Foundation

/// Derived overview only; not a scan/package schema or a claim of building area.
struct ProjectScanSummary: Equatable {
    struct Room: Equatable, Identifiable {
        let id: UUID
        let name: String
        let area: Double
        let story: Int
    }
    let floorArea: Double
    let wallAreaGross: Double
    let wallAreaNet: Double
    let rooms: Int
    let stories: Int
    let roomDetails: [Room]

    init(house: House) {
        let measures = HouseMeasurements(house: house)
        let quantities = house.allRooms.map(RenovationQuantities.init)
        floorArea = measures.floorArea; rooms = measures.roomCount; stories = measures.storyCount
        wallAreaGross = quantities.reduce(0) { $0 + $1.wallAreaGross }
        wallAreaNet = quantities.reduce(0) { $0 + $1.wallAreaNet }
        roomDetails = house.allRooms.map { Room(id:$0.id,name:$0.name,area:RoomMeasurements(plan:$0).floorArea,story:$0.story) }
    }
}
