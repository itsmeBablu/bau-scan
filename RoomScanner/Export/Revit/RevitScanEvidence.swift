import Foundation

/// Reads neutral structure JSON without introducing a simd or capture dependency.
enum RevitScanEvidence {
    private struct Structure: Decodable { var id: UUID; var rooms: [Room] }
    private struct Room: Decodable { var id: UUID; var surfaces: [Surface] }
    private struct Surface: Decodable { var category: String; var transform: [Double]; var dimensions: [Double] }
    static func options(house: House, structureData: Data, base: RevitExportOptions = .init()) throws -> RevitExportOptions {
        let source = try JSONDecoder().decode(Structure.self,from:structureData)
        guard source.id == house.id else { throw RevitIFCExporter.Failure.invalid("House and structure identities differ") }
        var result = base
        var floors: [Int:[Double]] = [:]
        let identity = TechnicalTransform(translation:.init(x:0,y:0,z:0),xAxis:.init(x:1,y:0,z:0),
                                          yAxis:.init(x:0,y:1,z:0),zAxis:.init(x:0,y:0,z:1))
        for room in house.allRooms {
            guard let scan = source.rooms.first(where: { $0.id == room.id }) else { continue }
            let floorYs = scan.surfaces.filter { $0.category == "floor" }.compactMap { surface -> Double? in
                guard surface.transform.count == 16,surface.transform.allSatisfy(\.isFinite) else { return nil }
                return surface.transform[13]
            }.sorted()
            if let y = floorYs.first { floors[room.story,default:[]].append(y) }
            // HouseBuilder preserves scan XZ coordinates. Reject rotated or translated plans.
            if room.transform == .identity {
                let walls = scan.surfaces.filter { $0.category == "wall" }
                let verified = walls.contains { surface in
                    guard surface.transform.count == 16,surface.dimensions.count >= 2 else { return false }
                    let m = surface.transform
                    return room.walls.contains { wall in
                        abs(wall.segment.midpoint.x-m[12]) < 0.01 &&
                        abs(wall.segment.midpoint.y+m[14]) < 0.01
                    }
                }
                if verified { result.shellPlacements[room.id] = identity }
            }
        }
        for (story,ys) in floors { result.storeyElevations[story] = ys.sorted()[ys.count/2] }
        return result
    }
}
