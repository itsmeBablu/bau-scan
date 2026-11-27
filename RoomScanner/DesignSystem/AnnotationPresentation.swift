import SwiftUI

/// Evidence markers are presentation only. These lengths do not describe a lens
/// calibration, captured field of view, or measured viewing volume.
enum AnnotationPresentation {
    static let cameraSymbol = "camera"
    static let audioSymbol = "waveform"
    static let iconSize:Float = 0.20
    static let directionCorners:[TechnicalPoint3] = [
        .init(x:-0.42,y:-0.28,z:-0.80),.init(x:0.42,y:-0.28,z:-0.80),
        .init(x:0.42,y:0.28,z:-0.80),.init(x:-0.42,y:0.28,z:-0.80)
    ]
    static let lineRadius:Float = 0.004
    static func noteIconPosition(_ note:ARNote,anchor:TechnicalPoint3,camera:TechnicalPoint3? = nil) -> TechnicalPoint3 {
        if note.audioFileName != nil,let camera = camera ?? note.viewingCameraPosition { return camera }
        return .init(x:anchor.x,y:anchor.y+(note.audioFileName == nil ? 0.12 : 0.28),z:anchor.z)
    }
    static let planDirectionLength:CGFloat = 36
    static let planDirectionHalfAngle = Double.pi/6
    static func planDirection(_ pose:[Double]) -> Double? {
        guard pose.count == 16,pose.allSatisfy(\.isFinite),hypot(pose[8],pose[10]) > 0.001 else { return nil }
        // Room camera forward = -Z; plan Y=-room Z and screen Y is downward.
        return atan2(-pose[10],-pose[8])
    }
}

struct EvidenceMarkerGlyph:View {
    let symbol:String
    var number:Int? = nil
    var selected = false
    var body:some View {
        HStack(spacing:DS.Spacing.xs/2) {
            Image(systemName:symbol).font(.title3.weight(.light))
            if let number { Text(String(number)).font(.caption2.weight(.semibold)).monospacedDigit() }
        }
        .foregroundStyle(selected ? DS.ColorToken.accent.color : DS.ColorToken.onBrand.color)
        .shadow(color:DS.ColorToken.mediaSurface.color,radius:1)
        .frame(minWidth:DS.Size.minimumTouchTarget,minHeight:DS.Size.minimumTouchTarget)
        .background(DS.ColorToken.mediaSurface.color.opacity(0.94),in:Capsule())
        .overlay { Capsule().strokeBorder(DS.ColorToken.onBrand.color.opacity(0.18),lineWidth:1) }
        .contentShape(Rectangle())
    }
}
