import Foundation

/// Derived overview only; not a scan/package schema or a claim of building area.
struct ProjectScanSummary: Equatable {
    struct Room: Equatable, Identifiable {
        let id: UUID
        let name: String
        let area: Double
        let story: Int
        var elements:[String:Int] = [:]
        var doors = 0
        var windows = 0
        var captureID:UUID? = nil
        var polygon:[Point2D] = []
        var label:RoomLabel = .unidentified
        func displayName(locale:Locale) -> String { RoomNaming.displayName(name,label:label,locale:locale) }
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
        roomDetails = house.allRooms.map { Room(id:$0.id,name:$0.name,area:RoomMeasurements(plan:$0).floorArea,story:$0.story,elements:Dictionary(grouping:$0.objects,by: \.category).mapValues(\.count),doors:$0.openings.filter { $0.kind == .door }.count,windows:$0.openings.filter { $0.kind == .window }.count,captureID:$0.sourceCaptureID,polygon:$0.floorPolygon.map($0.transform.apply),label:$0.label) }
    }
}
