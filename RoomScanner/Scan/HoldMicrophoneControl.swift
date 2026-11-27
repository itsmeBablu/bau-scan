#if os(iOS)
import SwiftUI
import UIKit

/// UIKit owns one continuous touch; state updates never replace its hit region.
struct HoldMicrophoneControl:UIViewRepresentable {
    let recording:Bool
    let start:()->Void
    let finish:(Bool)->Void
    func makeUIView(context:Context) -> Control { let view = Control(); view.start = start; view.finish = finish; return view }
    func updateUIView(_ view:Control,context:Context) {
        view.start = start; view.finish = finish
        view.tintColor = recording ? DS.ColorToken.recording.platformColor : .label
        view.setImage(recording ? "mic.fill" : "mic")
    }
    final class Control:UIControl {
        var start:(()->Void)?
        var finish:((Bool)->Void)?
        private let icon = UIImageView()
        private var iconName = ""
        private var task:Task<Void,Never>?
        private var began = CGPoint.zero
        private var fired = false
        private var cancelled = false
        override init(frame:CGRect) {
            super.init(frame:frame); backgroundColor = .secondarySystemBackground; layer.cornerRadius = 24
            icon.contentMode = .center; icon.isUserInteractionEnabled = false; addSubview(icon)
            isAccessibilityElement = true; accessibilityTraits = .button
            accessibilityLabel = AppLanguage.text("Hold to record voice note")
        }
        required init?(coder:NSCoder) { nil }
        override func layoutSubviews() { super.layoutSubviews(); icon.frame = bounds }
        func setImage(_ name:String) { guard iconName != name else { return }; iconName = name; icon.image = UIImage(systemName:name,withConfiguration:UIImage.SymbolConfiguration(pointSize:20,weight:.medium)) }
        override func beginTracking(_ touch:UITouch,with event:UIEvent?) -> Bool {
            began = touch.location(in:self); fired = false; cancelled = false
            task?.cancel(); task = Task { @MainActor [weak self] in
                try? await Task.sleep(for:.milliseconds(180))
                guard !Task.isCancelled,let self,self.isTracking,!self.cancelled else { return }
                self.fired = true; self.start?()
            }; return true
        }
        override func continueTracking(_ touch:UITouch,with event:UIEvent?) -> Bool {
            if touch.location(in:self).x-began.x < -60,!cancelled {
                cancelled = true; task?.cancel(); if fired { finish?(true) }
            }; return true
        }
        override func endTracking(_ touch:UITouch?,with event:UIEvent?) {
            task?.cancel(); if fired && !cancelled { finish?(false) }; fired = false
        }
        override func cancelTracking(with event:UIEvent?) { task?.cancel(); if fired && !cancelled { finish?(true) }; fired = false }
        override func accessibilityActivate() -> Bool {
            if fired { finish?(false); fired = false } else { fired = true; start?() }; return true
        }
    }
}
#endif
