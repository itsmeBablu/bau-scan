import Foundation

/// Room metadata (`meta.json` inside package): displayed in library list
/// without opening the plan file.
struct RoomRecord: Codable, Equatable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var createdAt: Date
    var label: RoomLabel
    var areaM2: Double
    var storyIndex: Int
    var schemaVersion: Int

    init(id: UUID, name: String, createdAt: Date = Date(), label: RoomLabel, areaM2: Double, storyIndex: Int, schemaVersion: Int = FloorPlan.schemaVersion) {
        self.id = id; self.name = name; self.label = label
        // Milliseconds: exact precision preserved by ISO 8601 with fractional seconds.
        self.createdAt = Date(timeIntervalSince1970: (createdAt.timeIntervalSince1970 * 1000).rounded() / 1000)
        self.areaM2 = areaM2; self.storyIndex = storyIndex; self.schemaVersion = schemaVersion
    }

    init(plan: FloorPlan, createdAt: Date = Date()) {
        self.init(id: plan.id, name: plan.name, createdAt: createdAt, label: plan.label,
                  areaM2: RoomMeasurements(plan: plan).floorArea, storyIndex: plan.story)
    }
}
