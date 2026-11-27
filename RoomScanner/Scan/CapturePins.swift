#if os(iOS)
import SwiftUI
import ARKit
import Observation

@MainActor @Observable final class CapturePins {
    struct Tap: Identifiable {
        let id = UUID()
        let target: ScanSurfaceTarget?
    }
    var placing = false
    var tap: Tap?
    var notes:[ARNote] = []
    var selected:UUID?
    var selection:ARNote? {
        guard let note = notes.first(where:{ $0.id == selected }) else { return nil }
        return note.anchorPinID.flatMap { id in notes.first { $0.id == id } } ?? note
    }
    func nearest(to point:TechnicalPoint3) -> ARNote? { ARNoteAttachment.nearest(to:point,in:notes) }
    func put(_ note:ARNote) {
        if let i = notes.firstIndex(where:{ $0.id == note.id }) { notes[i] = note } else { notes.append(note) }
    }
}
/// Projects scan-coordinate markers without taking ownership of the ARSession.
struct CapturePinOverlay:UIViewRepresentable {
    let session:ARSession
    let pins:CapturePins
    var scan: () -> ScanInput? = { nil }
    func makeUIView(context:Context) -> Overlay { let view = Overlay(); view.session = session; view.pins = pins; view.scan = scan; view.start(); return view }
    func updateUIView(_ view:Overlay,context:Context) { view.session = session; view.pins = pins; view.scan = scan; view.sync() }
    static func dismantleUIView(_ view:Overlay,coordinator:()) { view.timer?.invalidate() }
    final class Overlay:UIView, UIGestureRecognizerDelegate {
        weak var session:ARSession?
        var scan: () -> ScanInput? = { nil }
        var pins:CapturePins?
        var timer:Timer?
        private let leaders = CAShapeLayer()
        private let pinImage = UIImage(systemName:"mappin.circle.fill")
        private let voiceImage = UIImage(systemName:"mic.circle.fill")
        private var buttons:[UUID:UIButton] = [:]
        @objc private func place(_ recognizer: UITapGestureRecognizer) {
            guard let pins, pins.placing, let session, let orientation = window?.windowScene?.interfaceOrientation else { return }
            let target = CaptureSurfacePoint.tapped(recognizer.location(in: self), size: bounds.size,
                                                     orientation: orientation, session: session, scan: scan())
            pins.tap = .init(target: target)
            if target != nil { pins.placing = false }
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            pins?.placing == true
        }

        func start() {
            let tap = UITapGestureRecognizer(target: self, action: #selector(place(_:)))
            tap.delegate = self
            addGestureRecognizer(tap)
            isOpaque = false; leaders.actions = ["path":NSNull(),"position":NSNull(),"bounds":NSNull()]; leaders.strokeColor = UIColor.systemIndigo.cgColor; leaders.fillColor = UIColor.clear.cgColor; leaders.lineWidth = 1.5; layer.addSublayer(leaders); let value = Timer(timeInterval:1.0/15,repeats:true) { [weak self] _ in self?.sync() }; timer = value; RunLoop.main.add(value,forMode:.common) }
        override func hitTest(_ point:CGPoint,with event:UIEvent?) -> UIView? {
            if pins?.placing == true, bounds.contains(point) { return self }
            let hit = super.hitTest(point,with:event); return hit === self ? nil : hit
        }
        func sync() {
            guard let frame = session?.currentFrame,let pins else { return }
            let orientation = window?.windowScene?.interfaceOrientation ?? .portrait
            let lines = UIBezierPath()
            let ids = Set(pins.notes.suffix(256).map(\.id))
            for (id,button) in buttons where !ids.contains(id) { button.removeFromSuperview(); buttons.removeValue(forKey:id) }
            for note in pins.notes.suffix(256) {
                guard let p = note.position else { continue }
                let world = SIMD3<Float>(Float(p.x),Float(p.y),Float(p.z))
                let local = simd_inverse(frame.camera.transform)*SIMD4(world,1)
                let point = frame.camera.projectPoint(world,orientation:orientation,viewportSize:bounds.size)
                let button:UIButton
                if let existing = buttons[note.id] { button = existing } else {
                    button = UIButton(type:.system); button.setImage(note.audioFileName == nil ? pinImage : voiceImage,for:.normal)
                    button.backgroundColor = .secondarySystemBackground; button.layer.cornerRadius = 22
                    button.accessibilityLabel = AppLanguage.text("Pinned note")
                    button.addAction(UIAction { [weak pins] _ in pins?.selected = pins?.selected == note.id ? nil : note.id },for:.touchUpInside)
                    buttons[note.id] = button; addSubview(button)
                }
                button.tintColor = pins.selected == note.id ? .systemOrange : .systemPurple
                let floatY:CGFloat = note.audioFileName == nil ? 0 : -44
                button.setImage(note.audioFileName == nil ? pinImage : voiceImage,for:.normal)
                button.frame = CGRect(x:point.x-22,y:point.y-22+floatY,width:44,height:44)
                button.isHidden = local.z >= -0.05 || !point.x.isFinite || !point.y.isFinite || frame.camera.trackingState != .normal
                if !button.isHidden {
                    if floatY != 0 { lines.move(to:point); lines.addLine(to:.init(x:point.x,y:point.y+floatY)) }
                    if let selected = pins.selected,selected == note.id || selected == note.anchorPinID {
                        lines.move(to:.init(x:bounds.midX,y:bounds.midY)); lines.addLine(to:point)
                    }
                }
            }
            leaders.path = lines.cgPath
        }
    }
}
#endif
