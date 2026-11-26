import SwiftUI

/// Evidence markers are presentation only. These lengths do not describe a lens
/// calibration, captured field of view, or measured viewing volume.
enum AnnotationPresentation {
    static let cameraSymbol = "camera"
    static let audioSymbol = "waveform"
    static let directionCorners:[TechnicalPoint3] = [
        .init(x:-0.30,y:-0.20,z:-0.54),.init(x:0.30,y:-0.20,z:-0.54),
        .init(x:0.30,y:0.20,z:-0.54),.init(x:-0.30,y:0.20,z:-0.54)
    ]
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
        .contentShape(Rectangle())
    }
}
