import Foundation

/// A user-bounded radiator body in the close-up scan's coordinate frame.
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
                preset: RadiatorMountingPreset,photo: Data?) throws -> HouseRadiator {
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
            width: .init(metres: width,source: .scanEstimate,method: "userBoundedSceneDepthFrontWidth"),
            height: .init(metres: height,source: .scanEstimate,method: "userBoundedSceneDepthFrontHeight"),
            depth: depth,wallGap: gap,wallToFront: .init(metres: wallToFront,source: .scanEstimate,method: "parallelWallAndRadiatorFrontPlaneDistance"),
            frontCorners: frontCorners,wallSample: wall,samples: Array(samples.prefix(8000)),viewpointCount: viewpoints,photoJPEG: photo)
        try result.validate()
        return result
    }
}
