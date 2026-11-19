import Foundation

struct HouseWallSettings {
    var exteriorThickness = 0.365
    var interiorThickness = 0.115
    var maximumAngle = 3.0 * Double.pi / 180
    var maximumGap = 0.5
    var minimumOverlap = 0.3
}

struct ResolvedWall {
    enum WallType { case exterior, interior }
    enum ThicknessSource { case measured, defaultValue }
    let id: Int
    var segment: Segment2D
    var footprints: [[Point2D]] = []
    let thickness: Double
    let wallType: WallType
    let thicknessSource: ThicknessSource
    let roomIdsOnSideA: Set<UUID>
    let roomIdsOnSideB: Set<UUID>
    let sourceWallIds: Set<UUID>
}

/// Derived geometry only. Original room polygons and packages remain untouched.
struct HouseWallGraph {
    struct OpeningHost {
        let roomID: UUID
        let openingID: UUID
        let wallIDs: [Int]
    }
    let walls: [ResolvedWall]
    let openingHosts: [OpeningHost]

    private struct Source {
        let roomID: UUID
        let wallID: UUID
        let segment: Segment2D
        let inward: Point2D
    }

    init(house: House, settings: HouseWallSettings = HouseWallSettings()) {
        var sources: [Source] = []
        for room in house.allRooms {
            let polygon = room.floorPolygon.map(room.transform.apply)
            for wall in room.walls where wall.length > 0.000001 {
                let segment = Segment2D(start: room.transform.apply(wall.start), end: room.transform.apply(wall.end))
                let normal = segment.leftNormal
                let probe = segment.midpoint + normal * 0.02
                let inward = Polygon2D.contains(polygon, probe) ? normal : normal * -1
                sources.append(Source(roomID: room.id, wallID: wall.id, segment: segment, inward: inward))
            }
        }
        var cuts = sources.map { [0.0, $0.segment.length] }
        var matches: [(Int, Int)] = []
        for i in sources.indices {
            for j in sources.indices where j > i {
                let a = sources[i], b = sources[j]
                guard a.roomID != b.roomID else { continue }
                let direction = a.segment.direction
                let cosine = min(1, abs(Self.dot(direction, b.segment.direction)))
                guard acos(cosine) < settings.maximumAngle else { continue }
                // Only opposing room faces can bound a party wall.
                guard Self.dot(a.inward, b.inward) < 0 else { continue }
                let gap = abs(Self.dot(b.segment.midpoint - a.segment.midpoint, a.segment.leftNormal))
                guard gap <= settings.maximumGap else { continue }
                let b0 = Self.dot(b.segment.start - a.segment.start, direction)
                let b1 = Self.dot(b.segment.end - a.segment.start, direction)
                let low = max(0, min(b0, b1)), high = min(a.segment.length, max(b0, b1))
                guard high - low >= settings.minimumOverlap else { continue }
                cuts[i] += [low, high]
                let first = a.segment.start + direction * low
                let last = a.segment.start + direction * high
                cuts[j] += [Self.dot(first - b.segment.start, b.segment.direction),
                            Self.dot(last - b.segment.start, b.segment.direction)]
                matches.append((i, j))
            }
        }
        var resolved: [ResolvedWall] = []
        for i in sources.indices {
            let source = sources[i]
            let stops = Array(Set(cuts[i].map { min(source.segment.length, max(0, $0)) })).sorted()
            for (low, high) in zip(stops, stops.dropFirst()) where high - low > 0.000001 {
                let midpoint = source.segment.start + source.segment.direction * ((low + high) / 2)
                let peers = matches.compactMap { pair -> Int? in
                    let peer: Int
                    if pair.0 == i { peer = pair.1 }
                    else if pair.1 == i { peer = pair.0 }
                    else { return nil }
                    let other = sources[peer].segment
                    let along = Self.dot(midpoint - other.start, other.direction)
                    return along >= -0.000001 && along <= other.length + 0.000001 ? peer : nil
                }
                if peers.contains(where: { $0 < i }) { continue }
                let peer = peers.first.map { sources[$0] }
                let gap = peer.map { abs(Self.dot($0.segment.midpoint - midpoint, source.segment.leftNormal)) }
                let measured = gap.map { $0 >= 0.05 && $0 <= 0.50 } ?? false
                let thickness = measured ? gap! : (peer == nil ? settings.exteriorThickness : settings.interiorThickness)
                let offset: Point2D
                if let peer {
                    offset = source.segment.leftNormal * (Self.dot(peer.segment.midpoint - midpoint, source.segment.leftNormal) / 2)
                } else {
                    offset = source.inward * (-thickness / 2)
                }
                let segment = Segment2D(start: source.segment.start + source.segment.direction * low + offset,
                                        end: source.segment.start + source.segment.direction * high + offset)
                let positive = Self.dot(source.inward, segment.leftNormal) > 0
                let own: Set<UUID> = [source.roomID]
                let other = Set(peers.map { sources[$0].roomID })
                resolved.append(ResolvedWall(id: resolved.count, segment: segment, thickness: thickness,
                    wallType: peer == nil ? .exterior : .interior,
                    thicknessSource: measured ? .measured : .defaultValue,
                    roomIdsOnSideA: positive ? own : other, roomIdsOnSideB: positive ? other : own,
                    sourceWallIds: Set([source.wallID] + peers.map { sources[$0].wallID })))
            }
        }
        WallJunctions.resolve(&resolved)
        walls = resolved
        openingHosts = house.allRooms.flatMap { room in
            room.openings.map { opening in
                let center = room.transform.apply(opening.center)
                let candidates = resolved.filter {
                    $0.sourceWallIds.contains(opening.wallID ?? opening.id) &&
                    ($0.roomIdsOnSideA.contains(room.id) || $0.roomIdsOnSideB.contains(room.id))
                }
                let hosts = candidates.filter {
                    let along = Self.dot(center - $0.segment.start, $0.segment.direction)
                    return along + opening.width / 2 > 0 && along - opening.width / 2 < $0.segment.length
                }
                return OpeningHost(roomID: room.id, openingID: opening.id, wallIDs: hosts.map(\.id))
            }
        }
    }

    private static func dot(_ a: Point2D, _ b: Point2D) -> Double { a.x * b.x + a.y * b.y }
}
