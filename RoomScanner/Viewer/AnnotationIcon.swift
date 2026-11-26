import SwiftUI
import RealityKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

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
        model.name = name; model.components.set(BillboardComponent()); model.components.set(InputTargetComponent()); model.generateCollisionShapes(recursive:false)
        return model
    }
}
