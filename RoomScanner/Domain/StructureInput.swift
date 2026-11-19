import Foundation

/// Neutral snapshot of a **house** scanned room-by-room in a shared
/// world space (AR session retained): scans of each room plus optional
/// merged surfaces from Apple `CapturedStructure`,
/// converted by iOS adapter. Domain never depends on RoomPlan.
struct StructureInput: Codable, Equatable, Identifiable {
    var id: UUID
    /// One entry per room, shared world coordinates.
    var rooms: [ScanInput]
    /// Merged walls/floors from Apple (deduplicated); empty if structure unavailable.
    var mergedWalls: [ScanSurface]
    var mergedFloors: [ScanSurface]

    init(id: UUID = UUID(), rooms: [ScanInput], mergedWalls: [ScanSurface] = [], mergedFloors: [ScanSurface] = []) {
        self.id = id; self.rooms = rooms; self.mergedWalls = mergedWalls; self.mergedFloors = mergedFloors
    }
}
