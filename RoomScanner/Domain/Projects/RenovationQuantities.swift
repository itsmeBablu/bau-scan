import Foundation

struct RenovationQuantities: Equatable {
    var roomID: UUID
    var name: String
    var floorArea: Double
    var ceilingProjectedArea: Double
    var wallAreaGross: Double
    var wallAreaNet: Double
    var perimeter: Double
    var heightMin: Double
    var heightMax: Double
    var volumeMin: Double
    var volumeMax: Double
    var doors: Int
    var windows: Int
    var otherOpenings: Int
    var unhostedOpenings: Int

    init(_ room: FloorPlan) {
        roomID = room.id; name = room.name
        floorArea = Polygon2D.area(room.floorPolygon)
        ceilingProjectedArea = floorArea // horizontal projection; not sloping/actual ceiling surface
        perimeter = room.walls.reduce(0) { $0+$1.length }
        heightMin = room.ceilingHeight.lowerBound
        heightMax = room.ceilingHeight.upperBound
        volumeMin = floorArea*room.ceilingHeight.lowerBound
        volumeMax = floorArea*room.ceilingHeight.upperBound
        wallAreaGross = room.walls.reduce(0) { $0+$1.length*$1.height }
        var removed = 0.0
        for wall in room.walls where wall.length > 0 && wall.height > 0 {
            let dx = (wall.end.x-wall.start.x)/wall.length, dy = (wall.end.y-wall.start.y)/wall.length
            let rectangles = room.openings.filter { $0.wallID == wall.id }.compactMap { opening -> OpeningRectangle? in
                let center = (opening.center.x-wall.start.x)*dx+(opening.center.y-wall.start.y)*dy
                let x0 = max(0,center-opening.width/2), x1 = min(wall.length,center+opening.width/2)
                let y0 = max(0,opening.sillHeight), y1 = min(wall.height,opening.sillHeight+opening.height)
                guard x1 > x0,y1 > y0 else { return nil }
                return .init(x0:x0,x1:x1,y0:y0,y1:y1)
            }
            removed += Self.union(rectangles)
        }
        wallAreaNet = max(0,wallAreaGross-removed)
        doors = room.openings.filter { $0.kind == .door }.count
        windows = room.openings.filter { $0.kind == .window }.count
        otherOpenings = room.openings.count-doors-windows
        let ids = Set(room.walls.map(\.id))
        unhostedOpenings = room.openings.filter { opening in opening.wallID.map { !ids.contains($0) } ?? true }.count
    }
    /// Rectangular openings clipped to each wall, unioned so duplicates subtract only once.
    private struct OpeningRectangle { var x0,x1,y0,y1: Double }
    private static func union(_ rects: [OpeningRectangle]) -> Double {
        let xs = Set(rects.flatMap { [$0.x0,$0.x1] }).sorted(); guard xs.count >= 2 else { return 0 }
        var area = 0.0
        for i in 0..<xs.count-1 {
            let mid = (xs[i]+xs[i+1])/2
            let intervals = rects.filter { $0.x0 < mid && $0.x1 > mid }.map { ($0.y0,$0.y1) }.sorted { $0.0 < $1.0 }
            var length = 0.0, end = -Double.infinity
            for (lo,hi) in intervals { length += max(0,hi-max(lo,end)); end = max(end,hi) }
            area += length*(xs[i+1]-xs[i])
        }
        return area
    }
    private func wasteFactor(_ percent: Double) -> Double { 1+(percent.isFinite ? min(100,max(0,percent)) : 0)/100 }
    func flooring(wastePercent: Double) -> Double { floorArea*wasteFactor(wastePercent) }
    func paintArea(wastePercent: Double) -> Double { wallAreaNet*wasteFactor(wastePercent) }
}
