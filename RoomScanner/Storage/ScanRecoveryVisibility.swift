import Foundation

extension ScanSessionStore {
    /// Presentation filtering only: insignificant drafts are never deleted here.
    func recoveryCandidates(projectID:UUID) throws -> [ScanSession] {
        try unfinished().filter { ($0.projectID ?? ProjectIndex.unsortedID) == projectID }.filter { session in
            let committed = try entries(session.id)
            if committed.contains(where:{ $0.key.hasPrefix("voice-") || $0.key.hasPrefix("note-") || $0.key.hasPrefix("photo-") }) { return true }
            if session.kind == .technical {
                var active = Set<UUID>()
                for entry in committed where entry.key == "mesh-delta" {
                    let delta = try JSONDecoder().decode(RecoveryMeshPresence.self,from:payload(session.id,entry:entry))
                    active.subtract(delta.removed)
                    for patch in delta.changed {
                        if patch.hasTriangles { active.insert(patch.anchorID) } else { active.remove(patch.anchorID) }
                    }
                }
                return !active.isEmpty
            }
            for value in try latestValues(session.id,prefix:"room-") {
                let room = try JSONDecoder().decode(RecoveryRoomPresence.self,from:value.data)
                let plan = FloorPlanBuilder().build(from:room.scan,name:"")
                let area = Polygon2D.area(plan.floorPolygon)
                if plan.floorOutlineSource != .boundsEstimate,area >= (room.partial ? 30 : 1) { return true }
            }
            return false
        }
    }
}
private struct RecoveryRoomPresence:Decodable {
    let scan:ScanInput
    let partial:Bool
}
private struct RecoveryMeshPresence:Decodable {
    struct Patch:Decodable {
        let anchorID:UUID
        let hasTriangles:Bool
        enum CodingKeys:CodingKey { case anchorID,triangleIndices }
        init(from decoder:Decoder) throws {
            let container = try decoder.container(keyedBy:CodingKeys.self)
            anchorID = try container.decode(UUID.self,forKey:.anchorID)
            let indices = try container.nestedUnkeyedContainer(forKey:.triangleIndices)
            hasTriangles = (indices.count ?? 0) >= 3
        }
    }
    let changed:[Patch]
    let removed:[UUID]
}
