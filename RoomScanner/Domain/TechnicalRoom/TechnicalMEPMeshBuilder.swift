import Foundation

/// Derived mesh of reviewed objects. Never writes generated triangles into capture evidence.
enum TechnicalMEPMeshBuilder {
    static func snapshot(_ review: TechnicalMEPReview) throws -> TechnicalMeshSnapshot {
        try review.validate()
        let patches = review.suggestions.filter { $0.status == .accepted }.map { item -> TechnicalMeshSnapshot.Patch in
            let axis = MEPVector.unit(MEPVector.sub(item.end,item.start)), u = item.crossAxis
            let v = MEPVector.unit(MEPVector.cross(u,axis))
            func point(x: Double,y: Double,z: Double) -> TechnicalPoint3 {
                MEPVector.add(item.start,MEPVector.add(MEPVector.mul(axis,y),MEPVector.add(MEPVector.mul(u,x),MEPVector.mul(v,z))))
            }
            var vertices: [TechnicalPoint3] = [], indices: [UInt32] = []
            if item.kind == .rectangularDuct {
                let w = item.width/2,h = item.height/2,l = item.length
                vertices = [point(x: -w,y: 0,z: -h),point(x: w,y: 0,z: -h),point(x: w,y: l,z: -h),point(x: -w,y: l,z: -h),
                            point(x: -w,y: 0,z: h),point(x: w,y: 0,z: h),point(x: w,y: l,z: h),point(x: -w,y: l,z: h)]
                indices = [0,3,2,0,2,1,4,5,6,4,6,7,0,1,5,0,5,4,3,7,6,3,6,2,0,4,7,0,7,3,1,2,6,1,6,5]
            } else {
                let n: UInt32 = 24
                for y in [0,item.length] {
                    for i in 0..<n {
                        let angle = Double(i)*2 * Double.pi/Double(n)
                        vertices.append(point(x: cos(angle)*item.width/2,y: y,z: sin(angle)*item.width/2))
                    }
                }
                vertices += [item.start,item.end]
                for i in 0..<n {
                    let next = (i+1)%n
                    indices += [i,i+n,next,next,i+n,next+n,i,next,n*2,i+n,n*2+1,next+n]
                }
            }
            return .init(anchorID: item.id,vertices: vertices,triangleIndices: indices,colors: Array(repeating: item.color,count: vertices.count))
        }
        return .init(timestamp: 0,patches: patches,alignmentVerified: false,truncated: false)
    }
}
