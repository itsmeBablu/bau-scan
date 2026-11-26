import SwiftUI
import RealityKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct AnnotationTarget:Component {}

/// Two shared textures, independent of mesh size and annotation count.
@MainActor enum AnnotationIcon {
    private static var images:[String:CGImage] = [:]
    private static var textures:[String:TextureResource] = [:]
    static func image(_ symbol:String) -> CGImage? {
        if let existing = images[symbol] { return existing }
        #if os(iOS)
        let rendered = UIGraphicsImageRenderer(size:CGSize(width:64,height:64)).image { _ in
            UIColor.systemIndigo.setFill(); UIBezierPath(ovalIn:CGRect(x:2,y:2,width:60,height:60)).fill()
            UIImage(systemName:symbol)?.withTintColor(.white,renderingMode:.alwaysOriginal).draw(in:CGRect(x:16,y:16,width:32,height:32))
        }.cgImage
        #else
        let canvas = NSImage(size:NSSize(width:64,height:64))
        canvas.lockFocus(); NSColor.systemIndigo.setFill(); NSBezierPath(ovalIn:NSRect(x:2,y:2,width:60,height:60)).fill()
        let icon = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[.white]))
        icon?.draw(in:NSRect(x:16,y:16,width:32,height:32)); canvas.unlockFocus()
        let rendered = canvas.cgImage(forProposedRect:nil,context:nil,hints:nil)
        #endif
        if let rendered { images[symbol] = rendered }; return rendered
    }
    static func entity(symbol:String,name:String) -> Entity {
        var material = UnlitMaterial()
        if textures[symbol] == nil,let image = image(symbol) { textures[symbol] = try? TextureResource.generate(from:image,options:.init(semantic:.color)) }
        if let texture = textures[symbol] { material.color.texture = .init(texture) }
        material.blending = .transparent(opacity:.init(floatLiteral:1))
        let model = ModelEntity(mesh:.generatePlane(width:0.16,height:0.16),materials:[material])
        model.components.set(AnnotationTarget()); model.components.set(ModelSortGroupComponent(group:.planarUIAlwaysInFront,order:0))
        model.name = name; model.components.set(BillboardComponent()); model.components.set(InputTargetComponent()); model.components.set(CollisionComponent(shapes:[.generateBox(size:SIMD3(0.16,0.16,0.02))]))
        return model
    }
    static func line(from a:TechnicalPoint3,to b:TechnicalPoint3) -> Entity? {
        let start = SIMD3<Float>(Float(a.x),Float(a.y),Float(a.z)),end = SIMD3<Float>(Float(b.x),Float(b.y),Float(b.z))
        let delta = end-start,length = simd_length(delta)
        guard length.isFinite,length > 0.001 else { return nil }
        let model = ModelEntity(mesh:.generateCylinder(height:length,radius:0.002),materials:[UnlitMaterial(color:.systemIndigo)])
        model.position = (start+end)/2; model.orientation = simd_quatf(from:SIMD3(0,1,0),to:delta/length)
        return model
    }
    static func noteEntity(_ note:ARNote,position:TechnicalPoint3? = nil,camera:TechnicalPoint3? = nil,name:String? = nil) -> Entity {
        let root = Entity()
        guard let p = position ?? note.viewingPosition else { return root }
        root.position = SIMD3(Float(p.x),Float(p.y),Float(p.z))
        let point = ModelEntity(mesh:.generateSphere(radius:0.012),materials:[UnlitMaterial(color:.systemIndigo)])
        root.addChild(point)
        let height = note.audioFileName == nil ? 0.12 : 0.28
        let icon = entity(symbol:note.audioFileName == nil ? "mappin" : "mic.fill",name:name ?? "scan-note:"+note.id.uuidString)
        icon.position.y = Float(height); root.addChild(icon)
        if let stem = line(from:.init(x:0,y:0,z:0),to:.init(x:0,y:height,z:0)) { stem.name = "pin-label-leader"; root.addChild(stem) }
        if let c = camera ?? note.viewingCameraPosition,let beam = line(from:.init(x:c.x-p.x,y:c.y-p.y,z:c.z-p.z),to:.init(x:0,y:0,z:0)) { beam.name = "capture-to-pin"; root.addChild(beam) }
        return root
    }

}
