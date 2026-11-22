import Foundation

/// A bounded radiator body in the close-up scan's coordinate frame.
struct RadiatorScanGeometry {
    let origin: RadiatorPoint
    let right: RadiatorPoint
    let up = RadiatorPoint(x: 0,y: 1,z: 0)
    let frontNormal: RadiatorPoint
    let width: Double
    let height: Double
    let wallToFront: Double
    let frontCorners: [RadiatorPoint]
    let wall: RadiatorSurfaceSample

    init(frontCorners: [RadiatorPoint],wall: RadiatorSurfaceSample) throws {
        guard frontCorners.count == 3,frontCorners.allSatisfy(\.valid),wall.point.valid,wall.normal.valid else { throw HouseRadiatorSurvey.Failure.incomplete }
        let a = frontCorners[0],b = frontCorners[1],c = frontCorners[2]
        let horizontal = RadiatorPoint(x: b.x-a.x,y: 0,z: b.z-a.z)
        let right = horizontal.unit
        var normal = right.cross(.init(x: 0,y: 1,z: 0)).unit
        if (a-wall.point).dot(normal) < 0 { normal = normal * -1 }
        let w = horizontal.length,h = c.y-a.y,distance = (a-wall.point).dot(normal)
        guard w >= 0.1,w <= 5,h >= 0.1,h <= 4,abs(b.y-a.y) <= 0.08,
              abs((c-a).dot(right)) < 0.1,abs((c-a).dot(normal)) < 0.08 else { throw HouseRadiatorSurvey.Failure.incomplete }
        guard distance >= 0.015,distance <= 1,abs(wall.normal.unit.dot(normal)) > 0.94 else { throw HouseRadiatorSurvey.Failure.wrongWall }
        origin = a; self.right = right; frontNormal = normal
        width = w; height = h; wallToFront = distance
        self.frontCorners = frontCorners; self.wall = wall
    }
    func local(_ point: RadiatorPoint) -> RadiatorPoint {
        let d = point-origin
        return .init(x: d.dot(right),y: d.y,z: d.dot(frontNormal))
    }
    func contains(_ point: RadiatorPoint) -> Bool {
        let p = local(point)
        // Exclude the wall itself; it must never become an invented radiator back.
        return p.x >= -0.015 && p.x <= width+0.015 && p.y >= -0.015 && p.y <= height+0.015 &&
            p.z <= 0.015 && p.z > -wallToFront+0.015
    }
    func result(roomID: UUID,wallID: UUID?,samples: [RadiatorSurfaceSample],viewpoints: Int,
                preset: RadiatorMountingPreset,photo: Data?,automatic: Bool = false) throws -> HouseRadiator {
        var bins: [Int:[RadiatorSurfaceSample]] = [:]
        for sample in samples where contains(sample.point) && sample.normal.dot(frontNormal) < -0.94 {
            let distance = -local(sample.point).z
            guard distance >= 0.015 else { continue }
            bins[Int((distance/0.01).rounded()),default: []].append(sample)
        }
        // A rear plane needs support from at least two distinct viewpoints, not a lone depth outlier.
        let rear = bins.filter { $0.value.count >= 20 && Set($0.value.map(\.viewpoint)).count >= 2 }.max { $0.key < $1.key }
        var depth: RadiatorDimension?,gap: RadiatorDimension?
        if let rear {
            let distances = rear.value.map { -local($0.point).z }.sorted()
            let thickness = distances[distances.count/2]
            if thickness < wallToFront-0.01 {
                depth = .init(metres: thickness,source: .scanEstimate,method: "multiViewVisibleRearPlaneEstimate")
                gap = .init(metres: wallToFront-thickness,source: .scanEstimate,method: "wallToFrontMinusObservedBodyDepth")
            }
        }
        if depth == nil,let assumed = preset.gap,wallToFront > assumed.metres+0.005 {
            gap = assumed
            depth = .init(metres: wallToFront-assumed.metres,source: .mountingAssumption,
                          method: "wallToFrontMinusAssumedMountingGap",reference: assumed.reference)
        }
        let result = HouseRadiator(roomID: roomID,wallID: wallID,name: "Radiator",
            width: .init(metres: width,source: .scanEstimate,method: automatic ? "automaticVisibleFrontEnvelopeWidth" : "userBoundedSceneDepthFrontWidth"),
            height: .init(metres: height,source: .scanEstimate,method: automatic ? "automaticVisibleFrontEnvelopeHeight" : "userBoundedSceneDepthFrontHeight"),
            depth: depth,wallGap: gap,wallToFront: .init(metres: wallToFront,source: .scanEstimate,method: "parallelWallAndRadiatorFrontPlaneDistance"),
            frontCorners: frontCorners,wallSample: wall,samples: Array(samples.prefix(8000)),viewpointCount: viewpoints,photoJPEG: photo)
        try result.validate()
        return result
    }
}

/// Offline geometry proposal, not a semantic radiator classifier. A cabinet or TV
/// can satisfy these tests, so proposals require user confirmation before measuring.
enum RadiatorAutomaticDetector {
    struct Candidate {
        let geometry: RadiatorScanGeometry
        let center: RadiatorPoint
    }
    static func detect(grid: [RadiatorSurfaceSample?],width: Int,height: Int,camera: RadiatorPoint,excluded: [RadiatorPoint] = [],target: RadiatorPoint? = nil) -> Candidate? {
        guard width > 2,height > 2,width <= 256,height <= 256,grid.count == width*height,camera.valid else { return nil }
        var visited = Set<Int>()
        var components: [[Int]] = []
        for start in grid.indices where !visited.contains(start) {
            guard let seed = grid[start],seed.point.valid,seed.normal.valid,abs(seed.normal.y) < 0.25 else { continue }
            let normal = RadiatorPoint(x: seed.normal.x,y: 0,z: seed.normal.z).unit
            guard normal.length > 0.9 else { continue }
            var queue = [start],head = 0; visited.insert(start)
            while head < queue.count {
                let index = queue[head]; head += 1
                let x = index%width,y = index/width
                for next in [x > 0 ? index-1 : -1,x+1 < width ? index+1 : -1,y > 0 ? index-width : -1,y+1 < height ? index+width : -1] where next >= 0 && !visited.contains(next) {
                    guard let sample = grid[next],sample.point.valid,sample.normal.valid,
                          sample.normal.dot(normal) > 0.9,abs((sample.point-seed.point).dot(normal)) < 0.018,
                          let previous = grid[index],(sample.point-previous.point).length < 0.09 else { continue }
                    visited.insert(next); queue.append(next)
                }
            }
            if queue.count >= 60 { components.append(queue) }
        }
        for component in components.sorted(by: { $0.count > $1.count }).prefix(12) {
            // A clipped front cannot establish complete body dimensions.
            guard !component.contains(where: { $0%width <= 1 || $0%width >= width-2 || $0/width <= 1 || $0/width >= height-2 }),
                  let seed = grid[component[0]] else { continue }
            let normal = RadiatorPoint(x: seed.normal.x,y: 0,z: seed.normal.z).unit
            let right = RadiatorPoint(x: 0,y: 1,z: 0).cross(normal).unit
            let points = component.compactMap { grid[$0]?.point }
            let xs = points.map { $0.dot(right) }.sorted(),ys = points.map(\.y).sorted(),zs = points.map { $0.dot(normal) }.sorted()
            guard let left = xs.first,let rightEdge = xs.last,let bottom = ys.first,let top = ys.last else { continue }
            let w = rightEdge-left,h = top-bottom,z = zs[zs.count/2]
            guard w >= 0.25,w <= 3,h >= 0.25,h <= 2.2,w/h >= 0.35,w/h <= 8 else { continue }
            let center = right*((left+rightEdge)/2)+RadiatorPoint(x: 0,y: (bottom+top)/2,z: 0)+normal*z
            guard target.map({ ($0-center).length < 0.12 }) ?? true else { continue }
            guard (camera-center).length >= 0.4,(camera-center).length <= 2.5,
                  !excluded.contains(where: { ($0-center).length < 0.3 }) else { continue }
            var wallBins: [Int:[RadiatorSurfaceSample]] = [:]
            for sample in grid.compactMap({ $0 }) where sample.normal.dot(normal) > 0.94 {
                let x = sample.point.dot(right),y = sample.point.y,d = z-sample.point.dot(normal)
                guard d >= 0.025,d <= 0.35,x >= left-0.5,x <= rightEdge+0.5,y >= bottom-0.3,y <= top+0.4,
                      x < left-0.02 || x > rightEdge+0.02 || y > top+0.02 || y < bottom-0.02 else { continue }
                wallBins[Int((d/0.01).rounded()),default: []].append(sample)
            }
            guard let wallSamples = wallBins.values.filter({ $0.count >= 25 }).max(by: { $0.count < $1.count }) else { continue }
            let depths = wallSamples.map { $0.point.dot(normal) }.sorted()
            let wallZ = depths[depths.count/2]
            let origin = right*left+RadiatorPoint(x: 0,y: bottom,z: 0)+normal*z
            let wall = RadiatorSurfaceSample(point: right*left+RadiatorPoint(x: 0,y: bottom,z: 0)+normal*wallZ,normal: normal,viewpoint: 0)
            if let geometry = try? RadiatorScanGeometry(frontCorners: [origin,origin+right*w,origin+RadiatorPoint(x: 0,y: h,z: 0)],wall: wall) {
                return Candidate(geometry: geometry,center: center)
            }
        }
        return nil
    }
}
