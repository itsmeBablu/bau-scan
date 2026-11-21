import Foundation

struct TechnicalMEPMaskResponse: Codable {
    var schemaVersion: Int
    var frameID: UUID
    var imageSHA256: String
    var model: String
    var instances: [Instance]
    struct Instance: Codable {
        var kind: TechnicalMEPKind
        var score: Double?
        var width: Int
        var height: Int
        /// Row-major alternating background/foreground runs, starting with background.
        var runs: [Int]
        func pixels(expectedWidth: Int, expectedHeight: Int) throws -> [Bool] {
            guard width == expectedWidth, height == expectedHeight, width > 0, height > 0,
                  width <= 1024, height <= 1024, runs.count <= width*height+1,
                  score == nil || (score!.isFinite && (0...1).contains(score!)) else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
            let total = width*height
            var pixels = [Bool](); pixels.reserveCapacity(total)
            for (i,count) in runs.enumerated() {
                guard count >= 0, count <= total-pixels.count else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
                pixels.append(contentsOf: repeatElement(i%2 == 1,count: count))
            }
            guard pixels.count == total else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
            return pixels
        }
    }
}

enum TechnicalMEPDepthPoints {
    static func samples(frame: TechnicalCaptureKeyframe, mask: [Bool], colors: [TechnicalPoint3?] = []) throws -> [TechnicalMEPFitter.Sample] {
        try frame.validate()
        let d = frame.depth
        guard mask.count == d.width*d.height, d.width > 2, d.height > 2 else { throw TechnicalCaptureJournal.JournalError.invalidEvidence }
        let k = d.intrinsics, m = d.cameraTransform
        func point(_ x: Int, _ y: Int) -> TechnicalPoint3? {
            let index = y*d.width+x
            guard let depth = d.depthMetres[index], (d.confidence?[index] ?? 0) >= 1,
                  let p = TechnicalDepthProjection.cameraPoint(pixelX: (Double(x)+0.5)*Double(d.imageWidth)/Double(d.width)-0.5,
                    pixelY: (Double(y)+0.5)*Double(d.imageHeight)/Double(d.height)-0.5, depthMetres: Double(depth),
                    fx: k[0],fy: k[4],cx: k[6],cy: k[7]) else { return nil }
            return .init(x: m[0]*p.x+m[4]*p.y+m[8]*p.z+m[12],
                         y: m[1]*p.x+m[5]*p.y+m[9]*p.z+m[13],
                         z: m[2]*p.x+m[6]*p.y+m[10]*p.z+m[14])
        }
        var samples: [TechnicalMEPFitter.Sample] = []
        let step = max(1,Int(sqrt(Double(mask.count)/6000)))
        for y in stride(from: 1,to: d.height-1,by: step) {
            for x in stride(from: 1,to: d.width-1,by: step) where mask[y*d.width+x] {
                guard let p = point(x,y), let right = point(x+1,y), let down = point(x,y+1),
                      p.distance(to: right) < 0.1, p.distance(to: down) < 0.1 else { continue }
                let normal = MEPVector.unit(MEPVector.cross(MEPVector.sub(right,p),MEPVector.sub(down,p)))
                guard MEPVector.dot(normal,normal) > 0.5 else { continue }
                let index = y*d.width+x
                samples.append(.init(point: p,normal: normal,color: colors.indices.contains(index) ? colors[index] : nil))
            }
        }
        return samples
    }
}
