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
        let format = UIGraphicsImageRendererFormat(); format.opaque = false
        let rendered = UIGraphicsImageRenderer(size:CGSize(width:64,height:64),format:format).image { context in
            context.cgContext.setFillColor(UIColor.white.withAlphaComponent(0.96).cgColor)
            context.cgContext.fillEllipse(in:CGRect(x:2,y:2,width:60,height:60))
            context.cgContext.setShadow(offset:.zero,blur:2,color:DS.ColorToken.mediaSurface.platformColor.cgColor)
            UIImage(systemName:symbol,withConfiguration:UIImage.SymbolConfiguration(pointSize:44,weight:.light))?
                .withTintColor(DS.ColorToken.onBrand.platformColor,renderingMode:.alwaysOriginal).draw(in:CGRect(x:8,y:8,width:48,height:48))
        }.cgImage
        #else
        let canvas = NSImage(size:NSSize(width:64,height:64))
        canvas.lockFocus()
        NSColor.white.withAlphaComponent(0.96).setFill()
        NSBezierPath(ovalIn:NSRect(x:2,y:2,width:60,height:60)).fill()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = DS.ColorToken.mediaSurface.platformColor; shadow.shadowBlurRadius = 2; shadow.set()
        let icon = NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?
            .withSymbolConfiguration(.init(pointSize:44,weight:.light))?
            .withSymbolConfiguration(.init(paletteColors:[DS.ColorToken.onBrand.platformColor]))
        icon?.draw(in:NSRect(x:8,y:8,width:48,height:48)); NSGraphicsContext.restoreGraphicsState(); canvas.unlockFocus()
        let rendered = canvas.cgImage(forProposedRect:nil,context:nil,hints:nil)
        #endif
        if let rendered { images[symbol] = rendered }; return rendered
    }
    static func entity(symbol:String,name:String) -> Entity {
        var material = UnlitMaterial()
        if textures[symbol] == nil,let image = image(symbol) { textures[symbol] = try? TextureResource.generate(from:image,options:.init(semantic:.color)) }
        if let texture = textures[symbol] { material.color.texture = .init(texture) }
        material.blending = .transparent(opacity:.init(floatLiteral:1))
        let size = AnnotationPresentation.iconSize
        let model = ModelEntity(mesh:.generatePlane(width:size,height:size),materials:[material])
        model.components.set(AnnotationTarget()); model.components.set(ModelSortGroupComponent(group:.planarUIAlwaysInFront,order:0))
        model.name = name; model.components.set(BillboardComponent()); model.components.set(InputTargetComponent()); model.components.set(CollisionComponent(shapes:[.generateBox(size:SIMD3(size,size,0.02))]))
        return model
    }
    static func line(from a:TechnicalPoint3,to b:TechnicalPoint3) -> Entity? {
        let start = SIMD3<Float>(Float(a.x),Float(a.y),Float(a.z)),end = SIMD3<Float>(Float(b.x),Float(b.y),Float(b.z))
        let delta = end-start,length = simd_length(delta)
        guard length.isFinite,length > 0.001 else { return nil }
        let model = ModelEntity(mesh:.generateCylinder(height:length,radius:AnnotationPresentation.lineRadius),materials:[UnlitMaterial(color:.systemIndigo)])
        model.position = (start+end)/2; model.orientation = simd_quatf(from:SIMD3(0,1,0),to:delta/length)
        return model
    }
    static func noteEntity(_ note:ARNote,position:TechnicalPoint3? = nil,camera:TechnicalPoint3? = nil,name:String? = nil) -> Entity {
        let root = Entity()
        guard let p = position ?? note.viewingPosition else { return root }
        root.position = SIMD3(Float(p.x),Float(p.y),Float(p.z))
        let point = ModelEntity(mesh:.generateSphere(radius:0.012),materials:[UnlitMaterial(color:.systemIndigo)])
        root.addChild(point)
        let iconPoint = AnnotationPresentation.noteIconPosition(note,anchor:p,camera:camera)
        let localIcon = TechnicalPoint3(x:iconPoint.x-p.x,y:iconPoint.y-p.y,z:iconPoint.z-p.z)
        let icon = entity(symbol:note.audioFileName == nil ? "mappin" : AnnotationPresentation.audioSymbol,name:name ?? "scan-note:"+note.id.uuidString)
        icon.position = SIMD3(Float(localIcon.x),Float(localIcon.y),Float(localIcon.z)); root.addChild(icon)
        if let stem = line(from:.init(x:0,y:0,z:0),to:localIcon) { stem.name = "pin-label-leader"; root.addChild(stem) }
        if note.markerIconPosition == nil, note.audioFileName == nil,let c = camera ?? note.viewingCameraPosition,let beam = line(from:.init(x:c.x-p.x,y:c.y-p.y,z:c.z-p.z),to:.init(x:0,y:0,z:0)) { beam.name = "capture-to-pin"; root.addChild(beam) }
        return root
    }

}
