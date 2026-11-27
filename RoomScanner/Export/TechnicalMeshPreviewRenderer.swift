import Foundation
import CoreGraphics
import ImageIO

/// Bounded, offline isometric preview of captured triangles, never a replacement
/// for saved geometry. No camera, SceneKit renderer or export session is created.
enum TechnicalMeshPreviewRenderer {
    static func png(_ snapshot:TechnicalMeshSnapshot) -> Data? {
        guard let geometry = try? TechnicalSavedMeshGeometry(snapshot:snapshot.hidingCeilings(),reference:nil),!geometry.triangleIndices.isEmpty else { return nil }
        struct Face { let points:[CGPoint]; let depth:Double; let color:CGColor }
        let vertices = geometry.vertices
        let count = geometry.triangleIndices.count/3,step = max(1,(count+7999)/8000)
        var faces:[Face] = []
        for triangle in stride(from:0,to:count,by:step) {
            let indices = (0..<3).map { Int(geometry.triangleIndices[triangle*3+$0]) }
            guard indices.allSatisfy({ vertices.indices.contains($0) }) else { continue }
            let points = indices.map { vertices[$0] }
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else { continue }
            let projected = points.map { CGPoint(x:($0.x-$0.z)*0.7071,y:$0.y*0.8165-($0.x+$0.z)*0.4082) }
            let a = points[1],b = points[0],c = points[2]
            let ux = a.x-b.x,uy = a.y-b.y,uz = a.z-b.z,vx = c.x-b.x,vy = c.y-b.y,vz = c.z-b.z
            let nx = uy*vz-uz*vy,ny = uz*vx-ux*vz,nz = ux*vy-uy*vx
            let length = sqrt(nx*nx+ny*ny+nz*nz)
            let light = length > 0 ? 0.55+0.45*abs((nx*0.4+ny*0.8+nz*0.4)/length) : 0.7
            let colors = indices.compactMap { geometry.colors.indices.contains($0) ? geometry.colors[$0] : nil }
            let rgb:TechnicalPoint3
            if colors.isEmpty { rgb = .init(x:0.68,y:0.72,z:0.76) }
            else { rgb = .init(x:colors.reduce(0) { $0+$1.x }/Double(colors.count),y:colors.reduce(0) { $0+$1.y }/Double(colors.count),z:colors.reduce(0) { $0+$1.z }/Double(colors.count)) }
            let color = CGColor(red:min(1,max(0,rgb.x*light)),green:min(1,max(0,rgb.y*light)),blue:min(1,max(0,rgb.z*light)),alpha:1)
            faces.append(Face(points:projected,depth:points.reduce(0) { $0+$1.x+$1.y+$1.z },color:color))
        }
        guard !faces.isEmpty else { return nil }
        let all = faces.flatMap(\.points)
        let minX = all.map(\.x).min() ?? 0,maxX = all.map(\.x).max() ?? 0,minY = all.map(\.y).min() ?? 0,maxY = all.map(\.y).max() ?? 0
        let scale = min(552/max(0.01,maxX-minX),352/max(0.01,maxY-minY))
        guard let context = CGContext(data:nil,width:600,height:400,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray:0.97,alpha:1)); context.fill(CGRect(x:0,y:0,width:600,height:400))
        for face in faces.sorted(by:{ $0.depth < $1.depth }) {
            let points = face.points.map { CGPoint(x:300+($0.x-(minX+maxX)/2)*scale,y:200+($0.y-(minY+maxY)/2)*scale) }
            context.beginPath(); context.move(to:points[0]); context.addLine(to:points[1]); context.addLine(to:points[2]); context.closePath()
            context.setFillColor(face.color); context.fillPath()
        }
        return context.makeImage().flatMap(PlanRenderer.encodePNG)
    }
}

actor TechnicalMeshPreviewCache {
    static let shared = TechnicalMeshPreviewCache()
    private let cache = NSCache<NSString,CGImage>()
    init() { cache.countLimit = 24; cache.totalCostLimit = 12*1_048_576 }
    func image(packageURL:URL) throws -> CGImage? {
        try Task.checkCancellation()
        let preview = packageURL.appendingPathComponent("mesh-preview.png")
        let hasPreview = FileManager.default.fileExists(atPath:preview.path)
        let file = hasPreview ? preview : packageURL.appendingPathComponent("capture.json")
        guard FileManager.default.fileExists(atPath:file.path) else { return nil }
        let safe = try SafePackageRead.fileURL(file,root:packageURL),revision = try SavedFileRevision(safe)
        guard revision.bytes <= (hasPreview ? 10 : 32)*1_048_576 else { return nil }
        let key = "\(revision.path)|\(revision.modified?.timeIntervalSince1970 ?? 0)|\(revision.bytes)|\(revision.fileID)" as NSString
        if let image = cache.object(forKey:key) { return image }
        let data = try SafePackageRead.data(safe,root:packageURL,maximum:32*1_048_576,preflight:false)
        let png:Data?
        if hasPreview { png = data }
        else {
            struct Capture:Decodable { let meshes:[TechnicalMeshSnapshot] }
            let capture = try JSONDecoder().decode(Capture.self,from:data)
            png = TechnicalSavedMeshGeometry.latest(in:capture.meshes).flatMap(TechnicalMeshPreviewRenderer.png)
        }
        try Task.checkCancellation()
        guard let png else { return nil }
        let image = try PhotoImageProcessor.thumbnail(png,maximumPixelSize:600)
        cache.setObject(image,forKey:key,cost:image.bytesPerRow*image.height)
        return image
    }
}
