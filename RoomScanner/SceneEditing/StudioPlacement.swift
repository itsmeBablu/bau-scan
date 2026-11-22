import Foundation
import simd

/// Conservative oriented envelopes: touching is allowed; penetration beyond 2 mm is rejected.
/// This is a design aid, not an engineering clash report for the raw scan mesh.
enum StudioPlacement {
    enum Failure: LocalizedError {
        case overlap(String), floor
        var errorDescription: String? {
            switch self {
            case .overlap(let name): "Placement overlaps \(name). Move it clear or explicitly enable Allow overlaps for an intentional connection."
            case .floor: "The object would extend below the design floor."
            }
        }
    }
    static func corners(_ item: SceneEditObject) -> [SIMD3<Double>] {
        var result: [SIMD3<Double>] = []
        let center = SIMD3(item.position.x,item.position.y,item.position.z)
        for x in [-0.5,0.5] { for y in [-0.5,0.5] { for z in [-0.5,0.5] {
            result.append(center+item.orientation.act(SIMD3(x*item.size.x,y*item.size.y,z*item.size.z)))
        } } }
        return result
    }
    static func intersects(_ a: SceneEditObject,_ b: SceneEditObject) -> Bool {
        let delta = SIMD3(a.position.x-b.position.x,a.position.y-b.position.y,a.position.z-b.position.z)
        let radius = (simd_length(SIMD3(a.size.x,a.size.y,a.size.z))+simd_length(SIMD3(b.size.x,b.size.y,b.size.z)))/2
        if simd_length_squared(delta) > radius*radius { return false }
        let unit = [SIMD3<Double>(1,0,0),SIMD3(0,1,0),SIMD3(0,0,1)]
        let aa = unit.map { a.orientation.act($0) },bb = unit.map { b.orientation.act($0) }
        var axes = aa+bb
        for x in aa { for y in bb { let cross = simd_cross(x,y); if simd_length(cross) > 1e-8 { axes.append(simd_normalize(cross)) } } }
        let ac = corners(a),bc = corners(b)
        for axis in axes {
            let av = ac.map { simd_dot($0,axis) },bv = bc.map { simd_dot($0,axis) }
            if av.max()! <= bv.min()!+0.002 || bv.max()! <= av.min()!+0.002 { return false }
        }
        return true
    }
    static func conflicts(in document: SceneEditDocument,story: Int) -> [String] {
        let items = document.presentationObjects.filter { $0.story == story }
        var found: [String] = []
        for item in items {
            if let other = items.first(where: { $0.id != item.id && intersects(item,$0) }) {
                found.append(item.name+" ↔ "+other.name)
            } else if (try? check(item,in: document)) == nil { found.append(item.name+" ↔ shell / floor") }
            if found.count == 20 { break }
        }
        return found
    }
    static func check(_ item: SceneEditObject,in document: SceneEditDocument) throws {
        try item.validate()
        guard corners(item).allSatisfy({ $0.y >= -0.002 }) else { throw Failure.floor }
        for other in document.presentationObjects where other.id != item.id && other.story == item.story {
            if intersects(item,other) { throw Failure.overlap(other.name) }
        }
        for wall in walls(document,story: item.story) {
            if intersects(item,wall) { throw Failure.overlap("a scanned wall") }
        }
    }
    private static func walls(_ document: SceneEditDocument,story: Int) -> [SceneEditObject] {
        document.shell.stories.filter { $0.index == story }.flatMap(\.rooms).flatMap { room in
            room.walls.filter { document.includesElement($0.id) }.flatMap { wall in WallGeometry().wallBoxes(wall,openings: room.openings.filter { $0.wallID == wall.id }).map { box in
                let center = room.transform.apply(box.segment.midpoint)
                return SceneEditObject(origin: "Shell",name: "Wall",family: .box,position: .init(x: center.x,y: (box.top+box.bottom)/2,z: -center.y),size: .init(x: box.segment.length,y: box.height,z: box.thickness),yaw: box.segment.angle+room.transform.rotation,story: story)
            } }
        }
    }
    static func snapped(_ item: SceneEditObject,in document: SceneEditDocument) -> SceneEditObject {
        var result = item
        result.position.x = (result.position.x/0.05).rounded()*0.05
        result.position.z = (result.position.z/0.05).rounded()*0.05
        var closest = 0.12
        for wall in walls(document,story: item.story) {
            let normal = wall.orientation.act(SIMD3<Double>(0,0,1)),along = wall.orientation.act(SIMD3<Double>(1,0,0))
            let center = SIMD3(result.position.x,result.position.y,result.position.z)
            let origin = SIMD3(wall.position.x,wall.position.y,wall.position.z)
            let distance = simd_dot(center-origin,normal)
            let extent = corners(result).map { abs(simd_dot($0-center,normal)) }.max() ?? 0
            guard abs(simd_dot(center-origin,along)) <= wall.size.x/2 else { continue }
            let offset = (distance >= 0 ? 1.0 : -1.0)*(extent+wall.size.z/2)-distance
            if abs(offset) < closest {
                let adjusted = center+normal*offset
                result.position.x = adjusted.x; result.position.z = adjusted.z
                closest = abs(offset)
            }
        }
        return result
    }
    static func available(_ item: SceneEditObject,in document: SceneEditDocument,allowOverlap: Bool) throws -> SceneEditObject {
        if allowOverlap { return item }
        if (try? check(item,in: document)) != nil { return item }
        let step = max(item.size.x,item.size.z,0.5)+0.1
        for radius in 1...8 { for x in -radius...radius { for z in -radius...radius where abs(x) == radius || abs(z) == radius {
            var candidate = item
            candidate.position.x += Double(x)*step; candidate.position.z += Double(z)*step
            // Keep automatic placement inside the captured room's bounds.
            let b = document.shell.bounds
            guard b.isEmpty || (candidate.position.x >= b.minX && candidate.position.x <= b.maxX && -candidate.position.z >= b.minY && -candidate.position.z <= b.maxY) else { continue }
            if (try? check(candidate,in: document)) != nil { return candidate }
        } } }
        throw Failure.overlap("existing geometry; no free position was found")
    }
}
