import Foundation

/// Bounded geometric fitting. Results are candidates, never inferred DN, contents or connections.
enum TechnicalMEPFitter {
    struct Sample { var point: TechnicalPoint3; var normal: TechnicalPoint3; var color: TechnicalPoint3? }
    static func samples(mesh: TechnicalSavedMeshGeometry) -> [Sample] {
        var normals = Array(repeating: MEPVector.zero, count: mesh.vertices.count)
        for i in stride(from: 0, to: mesh.triangleIndices.count, by: 3) {
            let a = Int(mesh.triangleIndices[i]), b = Int(mesh.triangleIndices[i+1]), c = Int(mesh.triangleIndices[i+2])
            let n = MEPVector.cross(MEPVector.sub(mesh.vertices[b], mesh.vertices[a]), MEPVector.sub(mesh.vertices[c], mesh.vertices[a]))
            for j in [a,b,c] { normals[j] = MEPVector.add(normals[j], n) }
        }
        let step = max(1, (mesh.vertices.count + 5999) / 6000)
        return stride(from: 0, to: mesh.vertices.count, by: step).compactMap { i in
            let n = MEPVector.unit(normals[i])
            return MEPVector.dot(n,n) > 0.5 ? Sample(point: mesh.vertices[i], normal: n, color: mesh.colors[i]) : nil
        }
    }

    static func detect(_ input: [Sample], kind: TechnicalMEPKind = .pipe,
                       evidenceIDs: [UUID] = [], modelScore: Double? = nil) throws -> [TechnicalMEPSuggestion] {
        guard input.count <= 250_000, input.allSatisfy({ TechnicalPointEditing.valid($0.point) && TechnicalPointEditing.valid($0.normal) }) else {
            throw TechnicalCaptureJournal.JournalError.invalidEvidence
        }
        let step = max(1, (input.count + 5999) / 6000)
        var points = stride(from: 0, to: input.count, by: step).map { input[$0] }
        if kind == .rectangularDuct { return try rectangle(points, evidenceIDs: evidenceIDs, modelScore: modelScore).map { [$0] } ?? [] }
        var result: [TechnicalMEPSuggestion] = []
        var seed: UInt64 = 0x6d65702d7363616e
        func random(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int((seed >> 32) % UInt64(n)) }
        for _ in 0..<12 {
            try Task.checkCancellation()
            guard points.count >= 40 else { break }
            var best: (TechnicalMEPSuggestion, [Int])?
            for iteration in 0..<280 {
                if iteration % 32 == 0 { try Task.checkCancellation() }
                let a = points[random(points.count)], b = points[random(points.count)]
                let cross = MEPVector.cross(a.normal,b.normal)
                guard MEPVector.dot(cross,cross) > 0.12 else { continue }
                let axis = MEPVector.unit(cross), u = MEPVector.unit(a.normal), v = MEPVector.unit(MEPVector.cross(axis,u))
                let ax = MEPVector.dot(a.point,u), ay = MEPVector.dot(a.point,v)
                let bx = MEPVector.dot(b.point,u), by = MEPVector.dot(b.point,v)
                let nx = MEPVector.dot(b.normal,u), ny = MEPVector.dot(b.normal,v)
                guard abs(ny) > 0.2 else { continue }
                let t = ((bx-ax)*ny - (by-ay)*nx) / ny
                let center = MEPVector.add(MEPVector.mul(u,ax+t), MEPVector.mul(v,ay))
                let radius = abs(t)
                guard radius >= 0.012, radius <= (kind == .pipe ? 0.3 : 0.75) else { continue }
                let tolerance = max(0.003, min(0.015,radius*0.12))
                var support: [(Int,Double,Double,Double)] = []
                for (i,p) in points.enumerated() {
                    guard abs(MEPVector.dot(p.normal,axis)) < 0.3 else { continue }
                    let delta = MEPVector.sub(p.point,center), along = MEPVector.dot(delta,axis)
                    let radial = MEPVector.sub(delta, MEPVector.mul(axis,along))
                    let r = sqrt(MEPVector.dot(radial,radial)), residual = abs(r-radius)
                    guard residual < tolerance, abs(MEPVector.dot(MEPVector.unit(radial),p.normal)) > 0.8 else { continue }
                    support.append((i,along,residual,atan2(MEPVector.dot(radial,v),MEPVector.dot(radial,u))))
                }
                guard support.count >= 35 else { continue }
                // Split long unsupported gaps instead of inventing a hidden connecting pipe.
                support.sort { $0.1 < $1.1 }
                var groups: [[(Int,Double,Double,Double)]] = [[]]
                for item in support {
                    if let last = groups[groups.count-1].last, item.1-last.1 > max(0.12,radius*2) { groups.append([]) }
                    groups[groups.count-1].append(item)
                }
                guard let group = groups.max(by: { $0.count < $1.count }), group.count >= 35,
                      group.count > (best?.1.count ?? 0) else { continue }
                let lo = group[group.count/50].1, hi = group[group.count-1-group.count/50].1
                guard hi-lo >= max(0.25,radius*3) else { continue }
                let angles = group.map { $0.3 }.sorted()
                var largestGap = angles[0]+2 * Double.pi-angles[angles.count-1]
                for j in 1..<angles.count { largestGap = max(largestGap,angles[j]-angles[j-1]) }
                guard 2 * Double.pi-largestGap >= Double.pi/3 else { continue }
                let indices = group.map { $0.0 }
                let color = averageColor(indices.compactMap { points[$0].color })
                let item = TechnicalMEPSuggestion(kind: kind, start: MEPVector.add(center,MEPVector.mul(axis,lo)),
                    end: MEPVector.add(center,MEPVector.mul(axis,hi)), width: radius*2, height: radius*2, crossAxis: u,
                    color: color, method: modelScore == nil ? "normalPairCylinderRANSAC" : "aiMaskDepthCylinderRANSAC",
                    supportCount: group.count, residualMetres: group.reduce(0) { $0+$1.2 } / Double(group.count),
                    modelScore: modelScore, evidenceIDs: evidenceIDs)
                best = (item,indices)
            }
            guard let best else { break }
            try best.0.validate()
            result.append(best.0)
            let removed = Set(best.1)
            points = points.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        }
        return result
    }

    private static func rectangle(_ samples: [Sample], evidenceIDs: [UUID], modelScore: Double?) throws -> TechnicalMEPSuggestion? {
        guard samples.count >= 50 else { return nil }
        // Masked instance only: two perpendicular visible side planes are required.
        var subset: [Sample] = []
        for sample in samples where subset.count < 24 {
            if !subset.contains(where: { abs(MEPVector.dot($0.normal,sample.normal)) > 0.97 }) { subset.append(sample) }
        }
        var best: TechnicalMEPSuggestion?
        for a in subset.prefix(20) {
            try Task.checkCancellation()
            for b in subset.suffix(20) {
                guard abs(MEPVector.dot(a.normal,b.normal)) < 0.15 else { continue }
                let axis = MEPVector.unit(MEPVector.cross(a.normal,b.normal))
                let u = MEPVector.unit(a.normal), v = MEPVector.unit(MEPVector.cross(axis,u))
                func bounds(_ d: TechnicalPoint3) -> (Double,Double) {
                    let sorted = samples.map { MEPVector.dot($0.point,d) }.sorted()
                    return (sorted[sorted.count/50],sorted[sorted.count-1-sorted.count/50])
                }
                let x = bounds(u), y = bounds(v), z = bounds(axis)
                let width = x.1-x.0, height = y.1-y.0, length = z.1-z.0
                guard width >= 0.06, height >= 0.06, width <= 2, height <= 2,
                      length >= max(0.3,1.5 * max(width,height)) else { continue }
                let tolerance = 0.015
                var countU = 0, countV = 0, residual = 0.0, support: [Sample] = []
                for sample in samples {
                    let px = MEPVector.dot(sample.point,u), py = MEPVector.dot(sample.point,v)
                    let du = min(abs(px-x.0),abs(px-x.1)), dv = min(abs(py-y.0),abs(py-y.1))
                    if du < tolerance, abs(MEPVector.dot(sample.normal,u)) > 0.85 { countU += 1; residual += du; support.append(sample) }
                    else if dv < tolerance, abs(MEPVector.dot(sample.normal,v)) > 0.85 { countV += 1; residual += dv; support.append(sample) }
                }
                guard countU >= 15, countV >= 15, support.count > samples.count/2,
                      support.count > (best?.supportCount ?? 0) else { continue }
                let center = MEPVector.add(MEPVector.mul(u,(x.0+x.1)/2),MEPVector.mul(v,(y.0+y.1)/2))
                best = .init(kind: .rectangularDuct, start: MEPVector.add(center,MEPVector.mul(axis,z.0)),
                    end: MEPVector.add(center,MEPVector.mul(axis,z.1)), width: width, height: height, crossAxis: u,
                    color: averageColor(support.compactMap(\.color)), method: "aiMaskDepthTwoPlanePrismFit",
                    supportCount: support.count, residualMetres: residual/Double(support.count), modelScore: modelScore, evidenceIDs: evidenceIDs)
            }
        }
        return best
    }
    private static func averageColor(_ values: [TechnicalPoint3]) -> TechnicalPoint3? {
        guard !values.isEmpty else { return nil }
        return MEPVector.mul(values.reduce(MEPVector.zero,MEPVector.add),1/Double(values.count))
    }
}
