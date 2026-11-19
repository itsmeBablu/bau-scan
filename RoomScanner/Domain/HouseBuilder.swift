import Foundation

/// Assembles a `House` from a `StructureInput`: each room passes through
/// `FloorPlanBuilder` (shared world coordinates ⇒ `transform = .identity`),
/// stories are inferred from floor elevation, rooms are named and
/// deduplicated. No RoomPlan dependency (v2, D26).
struct HouseBuilder {
    /// Shared world coordinates: no per-room alignment (house is aligned globally in v2).
    var planBuilder: FloorPlanBuilder = { var b = FloorPlanBuilder(); b.alignToLongestWall = false; return b }()
    var storyDetector = StoryDetector()
    var naming = RoomNaming()

    func build(from structure: StructureInput, name: String) -> House {
        let heights = Dictionary(uniqueKeysWithValues: structure.rooms.map { ($0.id, StoryDetector.floorHeight(of: $0)) })
        let storyOf = storyDetector.stories(floorHeights: heights)
        var names: [String] = []
        var plans: [FloorPlan] = []
        for scan in structure.rooms {
            let proposed = naming.proposedName(for: scan.sectionLabels, existingNames: names)
            names.append(proposed)
            var plan = planBuilder.build(from: scan, name: proposed)
            plan.story = storyOf[scan.id] ?? scan.story
            plan.transform = .identity
            plans.append(plan)
        }
        let indices = Set(plans.map(\.story)).sorted()
        let stories = indices.map { i in Story(index: i, rooms: plans.filter { $0.story == i }) }
        return House(id: structure.id, name: name, stories: stories)
    }
}
