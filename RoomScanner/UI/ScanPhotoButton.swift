import SwiftUI

struct ScanPhotoButton: View {
    let busy: Bool
    let action: () -> Void
    var body: some View {
        Button(action:action) {
            ZStack {
                Circle().fill(.white)
                Circle().stroke(.gray,lineWidth:2).padding(5)
                if busy { ProgressView().dsCameraIndicatorTint() }
                else { Image(systemName:"camera.fill").foregroundStyle(.black) }
            }.frame(width:52,height:52)
        }.buttonStyle(.plain).accessibilityLabel("Take survey photo").disabled(busy)
    }
}

struct ScanPhotoFeedback: ViewModifier {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flashing = false
    func body(content: Content) -> some View {
        content.overlay {
            Color.white.opacity(flashing ? (reduceMotion ? 0.12 : 0.65) : 0)
                .ignoresSafeArea().allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight:.light),trigger:count)
        .task(id:count) {
            guard count > 0 else { return }
            flashing = true
            try? await Task.sleep(for:.milliseconds(25))
            guard !Task.isCancelled else { flashing = false; return }
            withAnimation(.easeOut(duration:reduceMotion ? 0.25 : 0.12)) { flashing = false }
        }
    }
}
