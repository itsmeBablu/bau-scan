import Foundation

/// Assembles a `House` from a `StructureInput`: each room passes through
/// `FloorPlanBuilder` (shared world coordinates ⇒ `transform = .identity`),
/// stories are inferred from floor elevation, rooms are named and
/// deduplicated. No RoomPlan dependency (v2, D26).
struct HouseBuilder {
    enum BuildError: Error, Equatable { case duplicateRoomID(UUID) }
    /// Shared world coordinates: no per-room alignment (house is aligned globally in v2).
    var planBuilder: FloorPlanBuilder = { var b = FloorPlanBuilder(); b.alignToLongestWall = false; return b }()
    var storyDetector = StoryDetector()
    var naming = RoomNaming()

    func build(from structure: StructureInput, name: String) throws -> House {
        var heights: [UUID:Double] = [:]
        for room in structure.rooms {
            guard heights[room.id] == nil else { throw BuildError.duplicateRoomID(room.id) }
            heights[room.id] = StoryDetector.floorHeight(of:room)
        }
        let storyOf = storyDetector.stories(floorHeights: heights)
        var names: [String] = []
        var plans: [FloorPlan] = []
        for scan in structure.rooms {
            let proposed = naming.proposedName(for: scan.sectionLabels, existingNames: names)
            var plan = planBuilder.build(from: scan, name: proposed)
            plan.story = storyOf[scan.id] ?? scan.story
            plan.transform = .identity
            let regions = RoomRegionBuilder.rooms(from:plan,scan:scan)
            for var region in regions {
                region.name = naming.proposedName(for:regions.count > 1 ? [region.label] : scan.sectionLabels,existingNames:names)
                names.append(region.name); plans.append(region)
            }
        }
        let indices = Set(plans.map(\.story)).sorted()
        let stories = indices.map { i in Story(index: i, rooms: plans.filter { $0.story == i }) }
        return House(id: structure.id, name: name, stories: stories)
    }
}
