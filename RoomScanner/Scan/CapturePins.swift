#if os(iOS)
import SwiftUI
import ARKit
import Observation

@MainActor @Observable final class CapturePins {
    var notes:[ARNote] = []
    var selected:UUID?
    var selection:ARNote? { notes.first { $0.id == selected } }
    func put(_ note:ARNote) {
        if let i = notes.firstIndex(where:{ $0.id == note.id }) { notes[i] = note } else { notes.append(note) }
    }
}
/// Projects scan-coordinate markers without taking ownership of the ARSession.
struct CapturePinOverlay:UIViewRepresentable {
    let session:ARSession
    let pins:CapturePins
    func makeUIView(context:Context) -> Overlay { let view = Overlay(); view.session = session; view.pins = pins; view.start(); return view }
    func updateUIView(_ view:Overlay,context:Context) { view.pins = pins; view.sync() }
    static func dismantleUIView(_ view:Overlay,coordinator:()) { view.timer?.invalidate() }
    final class Overlay:UIView {
        weak var session:ARSession?
        var pins:CapturePins?
        var timer:Timer?
        private var buttons:[UUID:UIButton] = [:]
        func start() { let value = Timer(timeInterval:1.0/15,repeats:true) { [weak self] _ in self?.sync() }; timer = value; RunLoop.main.add(value,forMode:.common) }
        override func hitTest(_ point:CGPoint,with event:UIEvent?) -> UIView? {
            let hit = super.hitTest(point,with:event); return hit === self ? nil : hit
        }
        func sync() {
            guard let frame = session?.currentFrame,let pins else { return }
            let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
            let ids = Set(pins.notes.suffix(256).map(\.id))
            for (id,button) in buttons where !ids.contains(id) { button.removeFromSuperview(); buttons.removeValue(forKey:id) }
            for note in pins.notes.suffix(256) {
                guard let p = note.position else { continue }
                let world = SIMD3<Float>(Float(p.x),Float(p.y),Float(p.z))
                let local = simd_inverse(frame.camera.transform)*SIMD4(world,1)
                let point = frame.camera.projectPoint(world,orientation:orientation,viewportSize:bounds.size)
                let button:UIButton
                if let existing = buttons[note.id] { button = existing } else {
                    button = UIButton(type:.system); button.setImage(UIImage(systemName:"mappin.circle.fill"),for:.normal)
                    button.backgroundColor = .secondarySystemBackground; button.layer.cornerRadius = 18
                    button.accessibilityLabel = AppLanguage.text("Pinned note")
                    button.addAction(UIAction { [weak pins] _ in pins?.selected = pins?.selected == note.id ? nil : note.id },for:.touchUpInside)
                    buttons[note.id] = button; addSubview(button)
                }
                button.tintColor = pins.selected == note.id ? .systemOrange : .systemPurple
                button.frame = CGRect(x:point.x-18,y:point.y-18,width:36,height:36)
                button.isHidden = local.z >= -0.05 || !point.x.isFinite || !point.y.isFinite || frame.camera.trackingState != .normal
            }
        }
    }
}
#endif
